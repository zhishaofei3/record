import CoreGraphics
import Foundation
import Vision

struct RecordingPerformanceProfile: Sendable {
    let previewFrameInterval: CFTimeInterval
    let previewSize: CGSize
    let segmentationInterval: CFTimeInterval
    let segmentationQuality: VNGeneratePersonSegmentationRequest.QualityLevel
    let maxVirtualBackgroundResolution: ResolutionPreset
    let name: String

    static var current: RecordingPerformanceProfile {
        #if arch(arm64)
        return .appleSilicon
        #elseif arch(x86_64)
        return .intel
        #else
        return .intel
        #endif
    }

    static let appleSilicon = RecordingPerformanceProfile(
        previewFrameInterval: 1.0 / 20.0,
        previewSize: CGSize(width: 960, height: 540),
        segmentationInterval: 1.0 / 15.0,
        segmentationQuality: .balanced,
        maxVirtualBackgroundResolution: .p4K,
        name: "Apple Silicon"
    )

    static let intel = RecordingPerformanceProfile(
        previewFrameInterval: 1.0 / 12.0,
        previewSize: CGSize(width: 480, height: 270),
        segmentationInterval: 1.0 / 8.0,
        segmentationQuality: .fast,
        maxVirtualBackgroundResolution: .p1080,
        name: "Intel"
    )

    func adjustedDecision(
        for decision: ResolutionDecision,
        virtualBackgroundEnabled: Bool
    ) -> ResolutionDecision {
        guard virtualBackgroundEnabled else {
            return decision
        }

        guard decision.actual.qualityRank > maxVirtualBackgroundResolution.qualityRank else {
            return decision
        }

        let downgradeMessage = "White virtual background is limited to \(maxVirtualBackgroundResolution.title) on \(name). Recording will use \(maxVirtualBackgroundResolution.title)."
        let combinedMessage: String
        if let existing = decision.message, !existing.isEmpty {
            combinedMessage = "\(existing) \(downgradeMessage)"
        } else {
            combinedMessage = downgradeMessage
        }

        return ResolutionDecision(
            requested: decision.requested,
            actual: maxVirtualBackgroundResolution,
            message: combinedMessage
        )
    }
}
