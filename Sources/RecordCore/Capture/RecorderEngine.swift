@preconcurrency import AVFoundation
import AppKit
import CoreImage
import CoreMedia
import Foundation

public final class RecorderEngine: NSObject, @unchecked Sendable {
    public var previewHandler: ((NSImage) -> Void)?
    public var messageHandler: ((String) -> Void)?

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let mediaQueue = DispatchQueue(label: "record.capture.engine")
    private let ciContext = CIContext()
    private let segmentationProcessor = PersonSegmentationProcessor()
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    private var activeVideoInput: AVCaptureDeviceInput?
    private var activeAudioInput: AVCaptureDeviceInput?
    private var availableVideoDevices: [AVCaptureDevice] = []
    private var availableAudioDevices: [AVCaptureDevice] = []
    private var selectedVideoDeviceID: String?
    private var selectedAudioDeviceID: String?
    private var currentResolutionDecision = ResolutionDecision(requested: .p1080, actual: .p1080, message: nil)
    private var virtualBackgroundEnabled = false
    private var lastPreviewTimestamp = CFAbsoluteTimeGetCurrent()
    private var didReportSegmentationFailure = false
    private var recordingSession: RecordingSession?

    private final class RecordingSession: @unchecked Sendable {
        let writer: AVAssetWriter
        let videoInput: AVAssetWriterInput
        let audioInput: AVAssetWriterInput
        let adaptor: AVAssetWriterInputPixelBufferAdaptor
        let tempURL: URL
        let resolution: ResolutionPreset
        var sessionStarted = false

        init(
            writer: AVAssetWriter,
            videoInput: AVAssetWriterInput,
            audioInput: AVAssetWriterInput,
            adaptor: AVAssetWriterInputPixelBufferAdaptor,
            tempURL: URL,
            resolution: ResolutionPreset
        ) {
            self.writer = writer
            self.videoInput = videoInput
            self.audioInput = audioInput
            self.adaptor = adaptor
            self.tempURL = tempURL
            self.resolution = resolution
        }
    }

    public override init() {
        super.init()
    }

    deinit {
        session.stopRunning()
    }

    public func prepare(requestedResolution: ResolutionPreset = .p1080) async throws -> RecorderBootstrap {
        let videoAllowed = await requestAccess(for: .video)
        let audioAllowed = await requestAccess(for: .audio)

        guard videoAllowed, audioAllowed else {
            throw RecorderEngineError.permissionsDenied
        }

        return try await runOnQueue {
            self.discoverDevices()

            guard let selectedVideo = self.availableVideoDevices.first else {
                throw RecorderEngineError.noVideoDevice
            }

            guard let selectedAudio = self.availableAudioDevices.first else {
                throw RecorderEngineError.noAudioDevice
            }

            let bootstrap = try self.applyConfiguration(
                videoDeviceID: selectedVideo.uniqueID,
                audioDeviceID: selectedAudio.uniqueID,
                requestedPreset: requestedResolution
            )

            if !self.session.isRunning {
                self.session.startRunning()
            }

            return bootstrap
        }
    }

    public func selectVideoDevice(id: String, requestedResolution: ResolutionPreset) async throws -> RecorderBootstrap {
        try await runOnQueue {
            let audioID = try self.requireSelectedAudioDeviceID()
            return try self.applyConfiguration(
                videoDeviceID: id,
                audioDeviceID: audioID,
                requestedPreset: requestedResolution
            )
        }
    }

    public func selectAudioDevice(id: String, requestedResolution: ResolutionPreset) async throws -> RecorderBootstrap {
        try await runOnQueue {
            let videoID = try self.requireSelectedVideoDeviceID()
            return try self.applyConfiguration(
                videoDeviceID: videoID,
                audioDeviceID: id,
                requestedPreset: requestedResolution
            )
        }
    }

    public func startRecording(configuration: RecorderConfiguration) async throws -> ResolutionDecision {
        try await runOnQueue {
            let bootstrap = try self.applyConfiguration(
                videoDeviceID: configuration.videoDeviceID,
                audioDeviceID: configuration.audioDeviceID,
                requestedPreset: configuration.requestedResolution
            )

            self.virtualBackgroundEnabled = configuration.virtualBackgroundEnabled
            self.didReportSegmentationFailure = false

            guard self.recordingSession == nil else {
                throw RecorderEngineError.recordingAlreadyActive
            }

            let session = try self.makeRecordingSession(for: bootstrap.resolutionDecision.actual)
            self.recordingSession = session

            return bootstrap.resolutionDecision
        }
    }

    public func stopRecording() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            mediaQueue.async {
                guard let session = self.recordingSession else {
                    continuation.resume(throwing: RecorderEngineError.recordingNotActive)
                    return
                }

                self.recordingSession = nil

                guard session.sessionStarted else {
                    try? FileManager.default.removeItem(at: session.tempURL)
                    continuation.resume(throwing: RecorderEngineError.noVideoFramesCaptured)
                    return
                }

                session.videoInput.markAsFinished()
                session.audioInput.markAsFinished()
                session.writer.finishWriting {
                    if let error = session.writer.error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: session.tempURL)
                    }
                }
            }
        }
    }

    public func commitExport(from temporaryURL: URL, to destinationURL: URL) async throws -> URL {
        try await runOnQueue {
            let fileManager = FileManager.default

            if fileManager.fileExists(atPath: destinationURL.path()) {
                try fileManager.removeItem(at: destinationURL)
            }

            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)

            DispatchQueue.main.async {
                NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
            }

            return destinationURL
        }
    }

    public func discardTemporaryRecording(at url: URL) async {
        await withCheckedContinuation { continuation in
            mediaQueue.async {
                try? FileManager.default.removeItem(at: url)
                continuation.resume()
            }
        }
    }

    private func requestAccess(for mediaType: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: mediaType) { granted in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }

    private func runOnQueue<T>(_ block: @Sendable @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            mediaQueue.async {
                do {
                    continuation.resume(returning: try block())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func discoverDevices() {
        let videoDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        availableVideoDevices = videoDiscovery.devices
            .sorted(by: { $0.localizedName < $1.localizedName })

        let audioDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        availableAudioDevices = audioDiscovery.devices
            .sorted(by: { $0.localizedName < $1.localizedName })
    }

    private func applyConfiguration(
        videoDeviceID: String,
        audioDeviceID: String,
        requestedPreset: ResolutionPreset
    ) throws -> RecorderBootstrap {
        guard let videoDevice = availableVideoDevices.first(where: { $0.uniqueID == videoDeviceID }) else {
            throw RecorderEngineError.noVideoDevice
        }

        guard let audioDevice = availableAudioDevices.first(where: { $0.uniqueID == audioDeviceID }) else {
            throw RecorderEngineError.noAudioDevice
        }

        let support = Self.makeResolutionSupport(for: videoDevice)
        let decision = support.decision(for: requestedPreset)

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if let activeVideoInput {
            session.removeInput(activeVideoInput)
        }

        if let activeAudioInput {
            session.removeInput(activeAudioInput)
        }

        let newVideoInput = try AVCaptureDeviceInput(device: videoDevice)
        let newAudioInput = try AVCaptureDeviceInput(device: audioDevice)

        guard session.canAddInput(newVideoInput), session.canAddInput(newAudioInput) else {
            throw RecorderEngineError.cannotConfigureInputs
        }

        session.addInput(newVideoInput)
        session.addInput(newAudioInput)
        activeVideoInput = newVideoInput
        activeAudioInput = newAudioInput

        configureOutputsIfNeeded()

        if session.canSetSessionPreset(decision.actual.sessionPreset) {
            session.sessionPreset = decision.actual.sessionPreset
        }

        selectedVideoDeviceID = videoDevice.uniqueID
        selectedAudioDeviceID = audioDevice.uniqueID
        currentResolutionDecision = decision

        return RecorderBootstrap(
            videoDevices: availableVideoDevices.map { DeviceDescriptor(id: $0.uniqueID, name: $0.localizedName) },
            audioDevices: availableAudioDevices.map { DeviceDescriptor(id: $0.uniqueID, name: $0.localizedName) },
            selectedVideoDeviceID: videoDevice.uniqueID,
            selectedAudioDeviceID: audioDevice.uniqueID,
            resolutionSupport: support,
            resolutionDecision: decision
        )
    }

    private func configureOutputsIfNeeded() {
        if !session.outputs.contains(videoOutput) {
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: mediaQueue)

            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }
        }

        if !session.outputs.contains(audioOutput) {
            audioOutput.setSampleBufferDelegate(self, queue: mediaQueue)

            if session.canAddOutput(audioOutput) {
                session.addOutput(audioOutput)
            }
        }
    }

    private func makeRecordingSession(for preset: ResolutionPreset) throws -> RecordingSession {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("record-\(UUID().uuidString)")
            .appendingPathExtension("mp4")

        let writer = try AVAssetWriter(outputURL: tempURL, fileType: .mp4)
        let dimensions = preset.dimensions

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: dimensions.width,
            AVVideoHeightKey: dimensions.height
        ]

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: dimensions.width,
                kCVPixelBufferHeightKey as String: dimensions.height
            ]
        )

        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
        audioInput.expectsMediaDataInRealTime = true

        guard writer.canAdd(videoInput), writer.canAdd(audioInput) else {
            throw RecorderEngineError.cannotCreateWriter
        }

        writer.add(videoInput)
        writer.add(audioInput)

        return RecordingSession(
            writer: writer,
            videoInput: videoInput,
            audioInput: audioInput,
            adaptor: adaptor,
            tempURL: tempURL,
            resolution: preset
        )
    }

    private func processVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let outputImage: CIImage
        do {
            outputImage = try segmentationProcessor.makeOutputImage(
                from: pixelBuffer,
                virtualBackgroundEnabled: virtualBackgroundEnabled
            )
        } catch {
            outputImage = CIImage(cvPixelBuffer: pixelBuffer)
            if virtualBackgroundEnabled, !didReportSegmentationFailure {
                didReportSegmentationFailure = true
                let handler = messageHandler
                DispatchQueue.main.async {
                    handler?("Virtual background processing failed. Recording continues with the original camera image.")
                }
            }
        }

        emitPreviewImageIfNeeded(from: outputImage)

        guard let recordingSession else {
            return
        }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if !recordingSession.sessionStarted {
            recordingSession.writer.startWriting()
            recordingSession.writer.startSession(atSourceTime: presentationTime)
            recordingSession.sessionStarted = true
        }

        guard
            recordingSession.videoInput.isReadyForMoreMediaData,
            let pixelBufferPool = recordingSession.adaptor.pixelBufferPool
        else {
            return
        }

        var outputBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &outputBuffer)

        guard let outputBuffer else {
            return
        }

        render(
            outputImage,
            into: outputBuffer,
            targetSize: CGSize(
                width: recordingSession.resolution.dimensions.width,
                height: recordingSession.resolution.dimensions.height
            )
        )

        _ = recordingSession.adaptor.append(outputBuffer, withPresentationTime: presentationTime)
    }

    private func processAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let recordingSession else {
            return
        }

        guard recordingSession.sessionStarted, recordingSession.audioInput.isReadyForMoreMediaData else {
            return
        }

        _ = recordingSession.audioInput.append(sampleBuffer)
    }

    private func emitPreviewImageIfNeeded(from image: CIImage) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastPreviewTimestamp >= (1.0 / 15.0) else {
            return
        }
        lastPreviewTimestamp = now

        let previewRect = CGRect(origin: .zero, size: CGSize(width: 960, height: 540))
        let previewImage = imageAspectFill(image, in: previewRect).cropped(to: previewRect)

        guard let cgImage = ciContext.createCGImage(previewImage, from: previewRect) else {
            return
        }

        let image = NSImage(cgImage: cgImage, size: NSSize(width: previewRect.width, height: previewRect.height))
        let handler = previewHandler
        DispatchQueue.main.async {
            handler?(image)
        }
    }

    private func render(_ image: CIImage, into pixelBuffer: CVPixelBuffer, targetSize: CGSize) {
        let targetRect = CGRect(origin: .zero, size: targetSize)
        let outputImage = imageAspectFill(image, in: targetRect).cropped(to: targetRect)
        ciContext.render(outputImage, to: pixelBuffer, bounds: targetRect, colorSpace: colorSpace)
    }

    private func imageAspectFill(_ image: CIImage, in targetRect: CGRect) -> CIImage {
        let scale = max(
            targetRect.width / image.extent.width,
            targetRect.height / image.extent.height
        )
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let x = targetRect.origin.x + (targetRect.width - scaled.extent.width) / 2 - scaled.extent.origin.x
        let y = targetRect.origin.y + (targetRect.height - scaled.extent.height) / 2 - scaled.extent.origin.y
        return scaled.transformed(by: CGAffineTransform(translationX: x, y: y))
    }

    private func requireSelectedVideoDeviceID() throws -> String {
        guard let selectedVideoDeviceID else {
            throw RecorderEngineError.noVideoDevice
        }
        return selectedVideoDeviceID
    }

    private func requireSelectedAudioDeviceID() throws -> String {
        guard let selectedAudioDeviceID else {
            throw RecorderEngineError.noAudioDevice
        }
        return selectedAudioDeviceID
    }

    static func makeResolutionSupport(for device: AVCaptureDevice) -> ResolutionSupportMatrix {
        var supportedPresets = Set<ResolutionPreset>()

        for format in device.formats {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            for preset in ResolutionPreset.allCases {
                let target = preset.dimensions
                if Int(dimensions.width) >= target.width && Int(dimensions.height) >= target.height {
                    supportedPresets.insert(preset)
                }
            }
        }

        return ResolutionSupportMatrix(supportedPresets: supportedPresets)
    }
}

extension RecorderEngine: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        if output === videoOutput {
            processVideoSampleBuffer(sampleBuffer)
        } else if output === audioOutput {
            processAudioSampleBuffer(sampleBuffer)
        }
    }
}

public enum RecorderEngineError: LocalizedError {
    case permissionsDenied
    case noVideoDevice
    case noAudioDevice
    case cannotConfigureInputs
    case cannotCreateWriter
    case recordingAlreadyActive
    case recordingNotActive
    case noVideoFramesCaptured

    public var errorDescription: String? {
        switch self {
        case .permissionsDenied:
            return "Camera or microphone permission was denied."
        case .noVideoDevice:
            return "No camera device is available."
        case .noAudioDevice:
            return "No microphone device is available."
        case .cannotConfigureInputs:
            return "The selected camera or microphone could not be configured."
        case .cannotCreateWriter:
            return "The MP4 writer could not be created."
        case .recordingAlreadyActive:
            return "A recording session is already active."
        case .recordingNotActive:
            return "No active recording session exists."
        case .noVideoFramesCaptured:
            return "No video frames were captured before recording stopped."
        }
    }
}
