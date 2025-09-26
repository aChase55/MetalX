import Foundation
import Metal
import CoreImage
import UIKit

class CMYKHalftoneEffect: BaseEffect {
    @Published var dotSize: Float = 6.0 { didSet { onUpdate?() } }
    @Published var angle: Float = 0.0 { didSet { onUpdate?() } }
    @Published var sharpness: Float = 0.7 { didSet { onUpdate?() } }
    @Published var grayComponentReplacement: Float = 1.0 { didSet { onUpdate?() } }
    @Published var underColorRemoval: Float = 0.5 { didSet { onUpdate?() } }

    private let context = CIContext()

    init() {
        super.init(name: "CMYK Halftone")
    }

    override func apply(to texture: MTLTexture, commandBuffer: MTLCommandBuffer, device: MTLDevice) -> MTLTexture? {
        guard isEnabled else { return texture }

        // Convert Metal texture to CIImage
        guard let ciImage = CIImage(mtlTexture: texture, options: [.colorSpace: CGColorSpaceCreateDeviceRGB()]) else {
            return texture
        }

        // Apply Core Image CMYK Halftone filter
        guard let filter = CIFilter(name: "CICMYKHalftone") else {
            return texture
        }

        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: CGFloat(texture.width) / 2, y: CGFloat(texture.height) / 2), forKey: "inputCenter")
        filter.setValue(dotSize, forKey: "inputWidth")
        filter.setValue(angle * .pi / 180.0, forKey: "inputAngle") // degrees → radians
        filter.setValue(sharpness, forKey: "inputSharpness")
        filter.setValue(grayComponentReplacement, forKey: "inputGCR")
        filter.setValue(underColorRemoval, forKey: "inputUCR")

        guard let outputImage = filter.outputImage else {
            return texture
        }

        // Create output texture
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: texture.pixelFormat,
            width: texture.width,
            height: texture.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        guard let outputTexture = device.makeTexture(descriptor: descriptor) else {
            return texture
        }

        // Render CIImage to Metal texture
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        context.render(
            outputImage,
            to: outputTexture,
            commandBuffer: commandBuffer,
            bounds: CGRect(x: 0, y: 0, width: texture.width, height: texture.height),
            colorSpace: colorSpace
        )

        return outputTexture
    }
}

