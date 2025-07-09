import UIKit
import Metal
import MetalKit

class ImageLayer: BaseLayer {
    var image: UIImage? {
        didSet {
            updateTexture()
        }
    }
    
    var texture: MTLTexture?
    private var device: MTLDevice?
    
    init(image: UIImage? = nil) {
        super.init()
        self.device = MTLCreateSystemDefaultDevice()
        self.image = image
        self.name = "Image Layer"
        updateTexture()
    }
    
    private func updateTexture() {
        guard let image = image,
              let cgImage = image.cgImage,
              let device = device else {
            texture = nil
            bounds = .zero
            return
        }
        
        // Update bounds
        bounds = CGRect(origin: .zero, size: image.size)
        
        // Create texture
        let textureLoader = MTKTextureLoader(device: device)
        do {
            texture = try textureLoader.newTexture(cgImage: cgImage, options: [
                .SRGB: false,
                .generateMipmaps: false
            ])
        } catch {
            // Failed to create texture
            texture = nil
        }
    }
    
    override func render(context: RenderContext) -> MTLTexture? {
        // For now, just return the texture
        // In a full implementation, we would apply transforms and effects here
        return texture
    }
    
    // Image-specific adjustments
    struct ImageAdjustments {
        var brightness: Float = 0
        var contrast: Float = 0
        var saturation: Float = 0
        var hue: Float = 0
        var exposure: Float = 0
    }
    
    var adjustments = ImageAdjustments()
    
    // Apply adjustments (simplified version)
    func applyAdjustments() {
        // In a full implementation, this would use Metal shaders
        // to apply the adjustments non-destructively
    }
}