import AppKit
import Foundation
import RecordCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class RecorderViewModel: ObservableObject {
    @Published var previewImage: NSImage?
    @Published var videoDevices: [DeviceDescriptor] = []
    @Published var audioDevices: [DeviceDescriptor] = []
    @Published var selectedVideoDeviceID = ""
    @Published var selectedAudioDeviceID = ""
    @Published var selectedResolution: ResolutionPreset = .p1080
    @Published var resolutionSupport = ResolutionSupportMatrix(supportedPresets: [])
    @Published var virtualBackgroundEnabled = false
    @Published var phase: RecordingPhase = .booting
    @Published var statusMessage = "Initializing camera and microphone access..."

    private let engine = RecorderEngine()
    private var stateMachine = RecorderStateMachine()
    private var pendingExportURL: URL?

    init() {
        engine.previewHandler = { [weak self] image in
            self?.previewImage = image
        }
        engine.messageHandler = { [weak self] message in
            self?.statusMessage = message
        }

        Task {
            await bootstrap()
        }
    }

    var canStartRecording: Bool {
        phase == .previewReady || phase == .exportComplete(URL(fileURLWithPath: "/dev/null"))
    }

    var isRecording: Bool {
        if case .recording = phase {
            return true
        }
        return false
    }

    var needsExportPath: Bool {
        pendingExportURL != nil && !isRecording
    }

    var canConfigureDevices: Bool {
        !isRecording
    }

    var primaryButtonTitle: String {
        if isRecording {
            return "Stop Recording"
        }
        return "Start Recording"
    }

    var selectedVideoDeviceName: String {
        videoDevices.first(where: { $0.id == selectedVideoDeviceID })?.name ?? "Unavailable"
    }

    var selectedAudioDeviceName: String {
        audioDevices.first(where: { $0.id == selectedAudioDeviceID })?.name ?? "Unavailable"
    }

    func availability(for preset: ResolutionPreset) -> ResolutionAvailability {
        resolutionSupport.availability(for: preset)
    }

    func selectVideoDevice(_ id: String) async {
        do {
            let bootstrap = try await engine.selectVideoDevice(id: id, requestedResolution: selectedResolution)
            applyBootstrap(bootstrap)
        } catch {
            phase = .error(error.localizedDescription)
            statusMessage = error.localizedDescription
        }
    }

    func selectAudioDevice(_ id: String) async {
        do {
            let bootstrap = try await engine.selectAudioDevice(id: id, requestedResolution: selectedResolution)
            applyBootstrap(bootstrap)
        } catch {
            phase = .error(error.localizedDescription)
            statusMessage = error.localizedDescription
        }
    }

    func selectResolution(_ preset: ResolutionPreset) {
        let decision = resolutionSupport.decision(for: preset)
        selectedResolution = decision.actual
        if let message = decision.message {
            statusMessage = message
        }
    }

    func toggleRecording() async {
        if isRecording {
            await stopRecording()
        } else {
            await startRecording()
        }
    }

    func chooseSaveLocation() async {
        guard let pendingExportURL else {
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultExportFilename()
        panel.directoryURL = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first

        if panel.runModal() == .OK, let destinationURL = panel.url {
            do {
                try stateMachine.transition(.exportRequested)
                phase = stateMachine.phase
                statusMessage = "Exporting mp4 file..."
                let finalURL = try await engine.commitExport(from: pendingExportURL, to: destinationURL)
                self.pendingExportURL = nil
                try stateMachine.transition(.exportSucceeded(finalURL))
                phase = stateMachine.phase
                statusMessage = "Export complete. Finder opened the output folder."
            } catch {
                do {
                    try stateMachine.transition(.exportFailed(error.localizedDescription))
                } catch {
                    phase = .error(error.localizedDescription)
                }
                phase = stateMachine.phase
                statusMessage = error.localizedDescription
            }
        } else {
            statusMessage = "Export is waiting for a save location."
        }
    }

    private func bootstrap() async {
        do {
            let bootstrap = try await engine.prepare(requestedResolution: selectedResolution)
            try stateMachine.transition(.bootSucceeded)
            phase = stateMachine.phase
            applyBootstrap(bootstrap)
            statusMessage = bootstrap.resolutionDecision.message ?? "Preview is ready."
        } catch {
            do {
                try stateMachine.transition(.bootFailed(error.localizedDescription))
            } catch {
                phase = .error(error.localizedDescription)
            }
            phase = stateMachine.phase
            statusMessage = error.localizedDescription
        }
    }

    private func applyBootstrap(_ bootstrap: RecorderBootstrap) {
        videoDevices = bootstrap.videoDevices
        audioDevices = bootstrap.audioDevices
        selectedVideoDeviceID = bootstrap.selectedVideoDeviceID
        selectedAudioDeviceID = bootstrap.selectedAudioDeviceID
        resolutionSupport = bootstrap.resolutionSupport
        selectedResolution = bootstrap.resolutionDecision.actual
    }

    private func startRecording() async {
        do {
            try stateMachine.transition(.startRecording)
            phase = stateMachine.phase

            let configuration = RecorderConfiguration(
                videoDeviceID: selectedVideoDeviceID,
                audioDeviceID: selectedAudioDeviceID,
                requestedResolution: selectedResolution,
                actualResolution: selectedResolution,
                virtualBackgroundEnabled: virtualBackgroundEnabled
            )
            let decision = try await engine.startRecording(configuration: configuration)
            selectedResolution = decision.actual
            statusMessage = decision.message ?? "Recording in progress..."
        } catch {
            phase = .error(error.localizedDescription)
            statusMessage = error.localizedDescription
        }
    }

    private func stopRecording() async {
        do {
            let temporaryURL = try await engine.stopRecording()
            pendingExportURL = temporaryURL
            try stateMachine.transition(.stopRecording)
            phase = stateMachine.phase
            statusMessage = "Recording stopped. Choose where to save the mp4 file."
            await chooseSaveLocation()
        } catch {
            phase = .error(error.localizedDescription)
            statusMessage = error.localizedDescription
        }
    }

    private func defaultExportFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "Record-\(formatter.string(from: Date())).mp4"
    }
}
