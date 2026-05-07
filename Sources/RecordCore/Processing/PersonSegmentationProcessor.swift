import CoreImage
import Foundation
import Vision

final class PersonSegmentationProcessor {
    private let minimumSegmentationInterval: CFTimeInterval = 1.0 / 12.0
    private let request: VNGeneratePersonSegmentationRequest = {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .fast
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return request
    }()
    private var lastMaskImage: CIImage?
    private var lastSegmentationTimestamp: CFAbsoluteTime = 0
    private var hasWarmedUpMask = false

    func reset() {
        lastMaskImage = nil
        lastSegmentationTimestamp = 0
        hasWarmedUpMask = false
    }

    func makeOutputImage(from pixelBuffer: CVPixelBuffer, virtualBackgroundEnabled: Bool) throws -> CIImage {
        let sourceImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard virtualBackgroundEnabled else {
            return sourceImage
        }

        let now = CFAbsoluteTimeGetCurrent()
        if lastMaskImage == nil || now - lastSegmentationTimestamp >= minimumSegmentationInterval {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
            try handler.perform([request])

            guard let maskObservation = request.results?.first as? VNPixelBufferObservation else {
                return sourceImage
            }

            lastMaskImage = CIImage(cvPixelBuffer: maskObservation.pixelBuffer)
            lastSegmentationTimestamp = now

            if !hasWarmedUpMask {
                hasWarmedUpMask = true
                return sourceImage
            }
        }

        guard hasWarmedUpMask, let maskImage = lastMaskImage else {
            return sourceImage
        }

        let scaledMask = maskImage.transformed(by: CGAffineTransform(
            scaleX: sourceImage.extent.width / maskImage.extent.width,
            y: sourceImage.extent.height / maskImage.extent.height
        ))
        let whiteBackground = CIImage(
            color: CIColor(red: 1, green: 1, blue: 1, alpha: 1)
        ).cropped(to: sourceImage.extent)

        return sourceImage.applyingFilter(
            "CIBlendWithMask",
            parameters: [
                kCIInputBackgroundImageKey: whiteBackground,
                kCIInputMaskImageKey: scaledMask
            ]
        )
    }
}
