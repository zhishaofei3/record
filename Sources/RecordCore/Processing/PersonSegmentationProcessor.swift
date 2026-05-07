import CoreImage
import Foundation
import Vision

final class PersonSegmentationProcessor {
    private let request: VNGeneratePersonSegmentationRequest = {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return request
    }()

    func makeOutputImage(from pixelBuffer: CVPixelBuffer, virtualBackgroundEnabled: Bool) throws -> CIImage {
        let sourceImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard virtualBackgroundEnabled else {
            return sourceImage
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        try handler.perform([request])

        guard let maskObservation = request.results?.first as? VNPixelBufferObservation else {
            return sourceImage
        }

        let maskImage = CIImage(cvPixelBuffer: maskObservation.pixelBuffer)
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
