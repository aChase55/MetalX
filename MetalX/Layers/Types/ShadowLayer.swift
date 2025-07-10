import Foundation
import Metal
import CoreGraphics
import simd

// Shadow layer that renders a blurred shadow of its source layer
class ShadowLayer: BaseLayer {
    weak var sourceLayer: (any Layer)?
    var shadowOffset: CGSize = CGSize(width: 2, height: 2)
    var shadowBlur: CGFloat = 4.0
    var shadowColor: CGColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0.5)
    
    private var shadowRenderer: ShadowRenderer?
    
    init(sourceLayer: any Layer) {
        self.sourceLayer = sourceLayer
        super.init()
        self.name = "\(sourceLayer.name) Shadow"
        self.isLocked = true // Shadow layers shouldn't be directly editable
        
        // Initialize shadow renderer
        if let device = MTLCreateSystemDefaultDevice(),
           let commandQueue = device.makeCommandQueue() {
            try? self.shadowRenderer = ShadowRenderer(device: device, commandQueue: commandQueue)
        }
    }
    
    override func render(context: RenderContext) -> MTLTexture? {
        guard let sourceLayer = sourceLayer,
              let sourceTexture = sourceLayer.render(context: context),
              let shadowRenderer = shadowRenderer else {
            return nil
        }
        
        // Calculate padding needed for blur - fixed padding regardless of blur amount
        // This ensures the shadow size stays constant
        let maxBlurPadding = 100 // Maximum padding for any blur amount
        
        // Create texture for shadow with fixed padding
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: sourceTexture.width + maxBlurPadding * 2,
            height: sourceTexture.height + maxBlurPadding * 2,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        
        guard let shadowTexture = context.device.device.makeTexture(descriptor: descriptor),
              let commandBuffer = context.device.commandQueue.makeCommandBuffer() else {
            return nil
        }
        
        // Render shadow - we need to center the source in the padded texture
        let shadowParams = ShadowRenderer.ShadowParameters(
            offset: .zero, // We'll handle offset via layer position
            blur: Float(shadowBlur),
            color: colorToSIMD4(shadowColor),
            opacity: 1.0
        )
        
        // Create a transform that centers the source texture in the larger shadow texture
        var centerTransform = matrix_identity_float4x4
        
        // We need to render the source at its original size but centered in the padded texture
        // This requires no scaling, just translation to center it
        let offsetX = Float(maxBlurPadding) / Float(shadowTexture.width) * 2.0
        let offsetY = Float(maxBlurPadding) / Float(shadowTexture.height) * 2.0
        
        // Adjust the transform to render centered (NDC space is -1 to 1)
        centerTransform.columns.3.x = 0.0  // Keep centered
        centerTransform.columns.3.y = 0.0  // Keep centered
        
        shadowRenderer.renderShadow(
            layerTexture: sourceTexture,
            targetTexture: shadowTexture,
            commandBuffer: commandBuffer,
            shadowParams: shadowParams,
            transform: centerTransform
        )
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return shadowTexture
    }
    
    override func getBounds(includeEffects: Bool) -> CGRect {
        guard let sourceLayer = sourceLayer else { return .zero }
        
        // Get source bounds
        var bounds = sourceLayer.getBounds(includeEffects: false)
        
        // Use minimal expansion since we have fixed padding in render
        // This keeps the interactive bounds close to the visible shadow
        let minExpansion: CGFloat = 20
        bounds = bounds.insetBy(dx: -minExpansion, dy: -minExpansion)
        
        // Apply offset after expansion
        bounds.origin.x += shadowOffset.width
        bounds.origin.y += shadowOffset.height
        
        return bounds
    }
    
    func updateFromSource() {
        guard let sourceLayer = sourceLayer else { return }
        
        // Update position to follow source layer with offset
        self.transform.position = CGPoint(
            x: sourceLayer.transform.position.x + shadowOffset.width,
            y: sourceLayer.transform.position.y + shadowOffset.height
        )
        self.transform.scale = sourceLayer.transform.scale
        self.transform.rotation = sourceLayer.transform.rotation
        
        // Update bounds with minimal expansion
        let minExpansion: CGFloat = 20
        self.bounds = sourceLayer.bounds.insetBy(dx: -minExpansion, dy: -minExpansion)
    }
    
    private func colorToSIMD4(_ color: CGColor) -> SIMD4<Float> {
        let components = color.components ?? [0, 0, 0, 1]
        return SIMD4<Float>(
            Float(components[safe: 0] ?? 0),
            Float(components[safe: 1] ?? 0),
            Float(components[safe: 2] ?? 0),
            Float(components[safe: 3] ?? 1)
        )
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}