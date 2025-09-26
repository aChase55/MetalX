import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

enum ImageProcessing {
    static func removeBackground(from image: UIImage) -> UIImage {
        if #available(iOS 17.0, *) {
            print("[ImageProcessing] Starting background removal (iOS 17)")
            guard let input = CIImage(image: image) else { return image }
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(ciImage: input)
            do {
                try handler.perform([request])
                if let result = request.results?.first,
                   let maskPixelBuffer = try? result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler) {
                    print("[ImageProcessing] Mask generated with \(CVPixelBufferGetWidth(maskPixelBuffer))x\(CVPixelBufferGetHeight(maskPixelBuffer))")
                    let mask = CIImage(cvPixelBuffer: maskPixelBuffer)
                    let filter = CIFilter.blendWithMask()
                    filter.inputImage = input
                    filter.maskImage = mask
                    filter.backgroundImage = CIImage.empty()
                    if let output = filter.outputImage,
                       let cg = CIContext(options: nil).createCGImage(output, from: output.extent) {
                        print("[ImageProcessing] Background removal complete")
                        return UIImage(cgImage: cg)
                    }
                    print("[ImageProcessing] Failed to create output image from mask")
                }
            } catch {
                print("[ImageProcessing] Error during Vision request: \(error)")
                return image
            }
            return image
        } else {
            // Fallback: return original on iOS 16 (Vision API not available)
            print("[ImageProcessing] Background removal unavailable on iOS < 17")
            return image
        }
    }
}
