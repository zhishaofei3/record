import AVFoundation
import Foundation

public struct DeviceDescriptor: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public enum ResolutionPreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case p720 = "720p"
    case p1080 = "1080p"
    case p4K = "4K"

    public var id: String { rawValue }

    public var title: String { rawValue }

    public var dimensions: (width: Int, height: Int) {
        switch self {
        case .p720:
            return (1280, 720)
        case .p1080:
            return (1920, 1080)
        case .p4K:
            return (3840, 2160)
        }
    }

    public var sessionPreset: AVCaptureSession.Preset {
        switch self {
        case .p720:
            return .hd1280x720
        case .p1080:
            return .hd1920x1080
        case .p4K:
            return .hd4K3840x2160
        }
    }

    public static var descendingQuality: [ResolutionPreset] {
        [.p4K, .p1080, .p720]
    }

    public var qualityRank: Int {
        switch self {
        case .p720:
            return 0
        case .p1080:
            return 1
        case .p4K:
            return 2
        }
    }
}

public enum ResolutionAvailability: Equatable, Sendable {
    case available
    case unavailable
}

public struct ResolutionDecision: Equatable, Sendable {
    public let requested: ResolutionPreset
    public let actual: ResolutionPreset
    public let message: String?

    public init(requested: ResolutionPreset, actual: ResolutionPreset, message: String?) {
        self.requested = requested
        self.actual = actual
        self.message = message
    }
}

public struct ResolutionSupportMatrix: Equatable, Sendable {
    public let supportedPresets: Set<ResolutionPreset>

    public init(supportedPresets: Set<ResolutionPreset>) {
        self.supportedPresets = supportedPresets
    }

    public func availability(for preset: ResolutionPreset) -> ResolutionAvailability {
        supportedPresets.contains(preset) ? .available : .unavailable
    }

    public func decision(for requested: ResolutionPreset) -> ResolutionDecision {
        if supportedPresets.contains(requested) {
            return ResolutionDecision(requested: requested, actual: requested, message: nil)
        }

        let qualityOrder = ResolutionPreset.descendingQuality
        if let requestedIndex = qualityOrder.firstIndex(of: requested),
           let fallback = qualityOrder[(requestedIndex + 1)...].first(where: { supportedPresets.contains($0) }) {
            return ResolutionDecision(
                requested: requested,
                actual: fallback,
                message: "\(requested.title) is unavailable on the selected camera. Recording will use \(fallback.title)."
            )
        }

        if let bestAvailable = ResolutionPreset.descendingQuality.first(where: { supportedPresets.contains($0) }) {
            return ResolutionDecision(
                requested: requested,
                actual: bestAvailable,
                message: "\(requested.title) is unavailable on the selected camera. Recording will use \(bestAvailable.title)."
            )
        }

        return ResolutionDecision(
            requested: requested,
            actual: .p720,
            message: "No supported capture preset was detected for the selected camera."
        )
    }
}

public struct RecorderBootstrap: Equatable, Sendable {
    public let videoDevices: [DeviceDescriptor]
    public let audioDevices: [DeviceDescriptor]
    public let selectedVideoDeviceID: String
    public let selectedAudioDeviceID: String
    public let resolutionSupport: ResolutionSupportMatrix
    public let resolutionDecision: ResolutionDecision

    public init(
        videoDevices: [DeviceDescriptor],
        audioDevices: [DeviceDescriptor],
        selectedVideoDeviceID: String,
        selectedAudioDeviceID: String,
        resolutionSupport: ResolutionSupportMatrix,
        resolutionDecision: ResolutionDecision
    ) {
        self.videoDevices = videoDevices
        self.audioDevices = audioDevices
        self.selectedVideoDeviceID = selectedVideoDeviceID
        self.selectedAudioDeviceID = selectedAudioDeviceID
        self.resolutionSupport = resolutionSupport
        self.resolutionDecision = resolutionDecision
    }
}

public struct RecorderConfiguration: Equatable, Sendable {
    public let videoDeviceID: String
    public let audioDeviceID: String
    public let requestedResolution: ResolutionPreset
    public let actualResolution: ResolutionPreset

    public init(
        videoDeviceID: String,
        audioDeviceID: String,
        requestedResolution: ResolutionPreset,
        actualResolution: ResolutionPreset
    ) {
        self.videoDeviceID = videoDeviceID
        self.audioDeviceID = audioDeviceID
        self.requestedResolution = requestedResolution
        self.actualResolution = actualResolution
    }
}

public enum RecordingPhase: Equatable, Sendable {
    case booting
    case previewReady
    case recording
    case paused
    case awaitingExportPath
    case exporting
    case exportComplete(URL)
    case error(String)
}

public enum RecorderEvent: Equatable, Sendable {
    case bootSucceeded
    case bootFailed(String)
    case startRecording
    case pauseRecording
    case resumeRecording
    case stopRecording
    case discardRecording
    case exportRequested
    case exportSucceeded(URL)
    case exportFailed(String)
    case recover
}
