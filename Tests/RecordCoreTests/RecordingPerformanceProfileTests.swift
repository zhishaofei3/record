import XCTest
@testable import RecordCore

final class RecordingPerformanceProfileTests: XCTestCase {
    func testIntelProfileDowngradesVirtualBackgroundTo1080p() {
        let profile = RecordingPerformanceProfile.intel
        let decision = ResolutionDecision(requested: .p4K, actual: .p4K, message: nil)

        let adjusted = profile.adjustedDecision(for: decision, virtualBackgroundEnabled: true)

        XCTAssertEqual(adjusted.actual, .p1080)
        XCTAssertEqual(
            adjusted.message,
            "White virtual background is limited to 1080p on Intel. Recording will use 1080p."
        )
    }

    func testAppleSiliconProfileKeeps4KVirtualBackground() {
        let profile = RecordingPerformanceProfile.appleSilicon
        let decision = ResolutionDecision(requested: .p4K, actual: .p4K, message: nil)

        let adjusted = profile.adjustedDecision(for: decision, virtualBackgroundEnabled: true)

        XCTAssertEqual(adjusted.actual, .p4K)
        XCTAssertNil(adjusted.message)
    }
}
