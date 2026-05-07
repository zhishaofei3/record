import Foundation

public enum RecorderStateMachineError: Error, Equatable, Sendable {
    case invalidTransition(phase: String, event: String)
}

public struct RecorderStateMachine: Sendable {
    public private(set) var phase: RecordingPhase

    public init(phase: RecordingPhase = .booting) {
        self.phase = phase
    }

    public mutating func transition(_ event: RecorderEvent) throws {
        switch (phase, event) {
        case (.booting, .bootSucceeded):
            phase = .previewReady
        case (.booting, .bootFailed(let message)):
            phase = .error(message)
        case (.previewReady, .startRecording),
             (.exportComplete, .startRecording):
            phase = .recording
        case (.recording, .pauseRecording):
            phase = .paused
        case (.paused, .resumeRecording):
            phase = .recording
        case (.recording, .stopRecording),
             (.paused, .stopRecording):
            phase = .awaitingExportPath
        case (.awaitingExportPath, .exportRequested),
             (.error, .exportRequested):
            phase = .exporting
        case (.exporting, .exportSucceeded(let url)):
            phase = .exportComplete(url)
        case (.exporting, .exportFailed(let message)):
            phase = .error(message)
        case (.error, .recover),
             (.exportComplete, .recover):
            phase = .previewReady
        default:
            throw RecorderStateMachineError.invalidTransition(
                phase: String(describing: phase),
                event: String(describing: event)
            )
        }
    }
}
