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
    private var keyboardMonitor: Any?

    init() {
        engine.previewHandler = { [weak self] image in
            self?.previewImage = image
        }
        engine.messageHandler = { [weak self] message in
            self?.statusMessage = message
        }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 50 else {
                return event
            }

            Task { @MainActor in
                await self?.handlePauseResumeShortcut()
            }
            return nil
        }

        Task {
            await bootstrap()
        }
    }

    var canStartRecording: Bool {
        switch phase {
        case .previewReady, .exportComplete:
            return true
        default:
            return false
        }
    }

    var isRecording: Bool {
        if case .recording = phase {
            return true
        }
        return false
    }

    var isPaused: Bool {
        if case .paused = phase {
            return true
        }
        return false
    }

    var hasActiveRecordingSession: Bool {
        isRecording || isPaused
    }

    var needsExportPath: Bool {
        pendingExportURL != nil && !hasActiveRecordingSession
    }

    var canConfigureDevices: Bool {
        !hasActiveRecordingSession
    }

    var primaryButtonTitle: String {
        if hasActiveRecordingSession {
            return "Stop Recording"
        }
        return "Start Recording"
    }

    var pauseResumeButtonTitle: String {
        isPaused ? "Resume (`)" : "Pause (`)"
    }

    var canPauseResume: Bool {
        isRecording || isPaused
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
            resetToPreviewReadyIfPossible()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func selectAudioDevice(_ id: String) async {
        do {
            let bootstrap = try await engine.selectAudioDevice(id: id, requestedResolution: selectedResolution)
            applyBootstrap(bootstrap)
            resetToPreviewReadyIfPossible()
        } catch {
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
        if hasActiveRecordingSession {
            await stopRecording()
        } else if canStartRecording {
            await startRecording()
        } else {
            statusMessage = "Camera preview is not ready yet. Wait for preview or reselect a working camera and microphone."
        }
    }

    func togglePauseResume() async {
        if isPaused {
            await resumeRecording()
        } else if isRecording {
            await pauseRecording()
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

    func discardPendingRecording() async {
        guard let pendingExportURL else {
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Discard this recording?"
        alert.informativeText = "This will permanently delete the current take that has not been saved yet."
        alert.addButton(withTitle: "Discard Recording")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.keyEquivalent = "\r"
        alert.buttons.last?.keyEquivalent = "\u{1b}"

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            statusMessage = "Discard cancelled."
            return
        }

        await engine.discardTemporaryRecording(at: pendingExportURL)
        self.pendingExportURL = nil

        do {
            try stateMachine.transition(.discardRecording)
            phase = stateMachine.phase
        } catch {
            resetToPreviewReadyIfPossible()
        }

        statusMessage = "Recording discarded."
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
            resetToPreviewReadyIfPossible()
            statusMessage = readableMessage(for: error)
        }
    }

    private func pauseRecording() async {
        do {
            try await engine.pauseRecording()
            try stateMachine.transition(.pauseRecording)
            phase = stateMachine.phase
            statusMessage = "Recording paused. Press ` to resume."
        } catch {
            statusMessage = readableMessage(for: error)
        }
    }

    private func resumeRecording() async {
        do {
            try await engine.resumeRecording()
            try stateMachine.transition(.resumeRecording)
            phase = stateMachine.phase
            statusMessage = "Recording resumed."
        } catch {
            statusMessage = readableMessage(for: error)
        }
    }

    private func stopRecording() async {
        do {
            let temporaryURL = try await engine.stopRecording()
            pendingExportURL = temporaryURL
            try stateMachine.transition(.stopRecording)
            phase = stateMachine.phase
            statusMessage = "Recording stopped. Choose whether to save or discard this take."
        } catch {
            resetToPreviewReadyIfPossible()
            statusMessage = readableMessage(for: error)
        }
    }

    private func defaultExportFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "Record-\(formatter.string(from: Date())).mp4"
    }

    private func handlePauseResumeShortcut() async {
        guard canPauseResume else {
            return
        }
        await togglePauseResume()
    }

    private func resetToPreviewReadyIfPossible() {
        guard !selectedVideoDeviceID.isEmpty, !selectedAudioDeviceID.isEmpty else {
            return
        }
        stateMachine = RecorderStateMachine(phase: .previewReady)
        phase = .previewReady
    }

    private func readableMessage(for error: Error) -> String {
        if let stateError = error as? RecorderStateMachineError {
            switch stateError {
            case .invalidTransition:
                return "Recording can only start after preview is ready. Verify the selected camera and microphone, then try again."
            }
        }

        return error.localizedDescription
    }
}
