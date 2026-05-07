import XCTest
@testable import RecordCore

final class RecorderDomainTests: XCTestCase {
    func testResolutionDecisionReturnsRequestedPresetWhenSupported() {
        let support = ResolutionSupportMatrix(supportedPresets: [.p720, .p1080, .p4K])

        let decision = support.decision(for: .p4K)

        XCTAssertEqual(decision.actual, .p4K)
        XCTAssertNil(decision.message)
    }

    func testResolutionDecisionFallsBackTo1080pWhen4KIsUnavailable() {
        let support = ResolutionSupportMatrix(supportedPresets: [.p720, .p1080])

        let decision = support.decision(for: .p4K)

        XCTAssertEqual(decision.actual, .p1080)
        XCTAssertEqual(
            decision.message,
            "4K is unavailable on the selected camera. Recording will use 1080p."
        )
    }

    func testResolutionDecisionReturnsNoSupportMessageWhenNothingIsAvailable() {
        let support = ResolutionSupportMatrix(supportedPresets: [])

        let decision = support.decision(for: .p1080)

        XCTAssertEqual(decision.actual, .p720)
        XCTAssertEqual(
            decision.message,
            "No supported capture preset was detected for the selected camera."
        )
    }

    func testStateMachineTransitionsIntoPreviewReadyAfterBoot() throws {
        var machine = RecorderStateMachine()

        try machine.transition(.bootSucceeded)

        XCTAssertEqual(machine.phase, .previewReady)
    }

    func testStateMachineRejectsStartRecordingBeforeBootCompletes() {
        var machine = RecorderStateMachine()

        XCTAssertThrowsError(try machine.transition(.startRecording)) { error in
            XCTAssertEqual(
                error as? RecorderStateMachineError,
                .invalidTransition(phase: "booting", event: "startRecording")
            )
        }
    }

    func testStateMachineSupportsRecordingAndExportFlow() throws {
        let outputURL = URL(fileURLWithPath: "/tmp/output.mp4")
        var machine = RecorderStateMachine(phase: .previewReady)

        try machine.transition(.startRecording)
        try machine.transition(.stopRecording)
        try machine.transition(.exportRequested)
        try machine.transition(.exportSucceeded(outputURL))

        XCTAssertEqual(machine.phase, .exportComplete(outputURL))
    }

    func testStateMachineSupportsPauseAndResumeFlow() throws {
        var machine = RecorderStateMachine(phase: .previewReady)

        try machine.transition(.startRecording)
        try machine.transition(.pauseRecording)
        XCTAssertEqual(machine.phase, .paused)

        try machine.transition(.resumeRecording)
        XCTAssertEqual(machine.phase, .recording)
    }

    func testStateMachineAllowsStoppingWhilePaused() throws {
        var machine = RecorderStateMachine(phase: .previewReady)

        try machine.transition(.startRecording)
        try machine.transition(.pauseRecording)
        try machine.transition(.stopRecording)

        XCTAssertEqual(machine.phase, .awaitingExportPath)
    }

    func testStateMachineCanRecoverFromExportError() throws {
        var machine = RecorderStateMachine(phase: .previewReady)

        try machine.transition(.startRecording)
        try machine.transition(.stopRecording)
        try machine.transition(.exportRequested)
        try machine.transition(.exportFailed("disk full"))
        try machine.transition(.recover)

        XCTAssertEqual(machine.phase, .previewReady)
    }
}
