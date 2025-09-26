import Foundation
import Metal
#if canImport(MetalPerformanceShaders)
import MetalPerformanceShaders

class BlurEffect: BaseEffect {
    @Published var radius: Float = 5.0 { didSet { onUpdate?() } }
    
    init() { super.init(name: "Blur") }
    
    override func apply(to texture: MTLTexture, commandBuffer: MTLCommandBuffer, device: MTLDevice) -> MTLTexture? {
        guard isEnabled else { return texture }
        
        // Create destination texture
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: texture.pixelFormat,
            width: texture.width,
            height: texture.height,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite]
        guard let dst = device.makeTexture(descriptor: desc) else { return texture }
        
        // Use MPS Gaussian blur
        let sigma = max(0.1, radius * intensity)
        let blur = MPSImageGaussianBlur(device: device, sigma: sigma)
        blur.encode(commandBuffer: commandBuffer, sourceTexture: texture, destinationTexture: dst)
        return dst
    }
}
#endif
