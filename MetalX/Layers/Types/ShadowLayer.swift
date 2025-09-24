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
    
    // Shadow layers are internal and not shown in UI
    override var isInternal: Bool { true }
    
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
        
        // Calculate padding needed for blur - use minimum padding when blur is 0
        let minPadding = 20 // Minimum padding to ensure shadow is visible
        let blurPadding = Int(shadowBlur * 1.5) // Padding based on blur amount
        let padding = max(minPadding, blurPadding)
        
        // Create texture for shadow with appropriate padding
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: sourceTexture.width + padding * 2,
            height: sourceTexture.height + padding * 2,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        
        guard let shadowTexture = context.device.device.makeTexture(descriptor: descriptor),
              let commandBuffer = context.device.commandQueue.makeCommandBuffer() else {
            return nil
        }
        
        // Render shadow - we need to center the source in the padded texture
        // Compensate blur for the scale that will be applied later
        let compensatedBlur = Float(shadowBlur) / Float(sourceLayer.transform.scale)
        let shadowParams = ShadowRenderer.ShadowParameters(
            offset: .zero, // We'll handle offset via layer position
            blur: max(0.001, compensatedBlur), // Ensure blur is never exactly 0
            color: colorToSIMD4(shadowColor),
            opacity: 1.0
        )
        
        // Create a transform that centers the source texture in the larger shadow texture
        var centerTransform = matrix_identity_float4x4
        
        // We need to render the source at its original size but centered in the padded texture
        // This requires no scaling, just translation to center it
        let offsetX = Float(padding) / Float(shadowTexture.width) * 2.0
        let offsetY = Float(padding) / Float(shadowTexture.height) * 2.0
        
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
        
        // Use dynamic expansion based on blur
        let minExpansion: CGFloat = 20
        let blurExpansion = shadowBlur * 1.5
        let expansion = max(minExpansion, blurExpansion)
        bounds = bounds.insetBy(dx: -expansion, dy: -expansion)
        
        // Apply offset after expansion
        bounds.origin.x += shadowOffset.width
        bounds.origin.y += shadowOffset.height
        
        return bounds
    }
    
    func updateFromSource() {
        guard let sourceLayer = sourceLayer else { return }
        
        // Update position to follow source layer with offset
        // Scale the offset to maintain relative position
        let scaledOffset = CGSize(
            width: shadowOffset.width * sourceLayer.transform.scale,
            height: shadowOffset.height * sourceLayer.transform.scale
        )
        self.transform.position = CGPoint(
            x: sourceLayer.transform.position.x + scaledOffset.width,
            y: sourceLayer.transform.position.y + scaledOffset.height
        )
        // Apply both source layer scale and shadow scale
        self.transform.scale = sourceLayer.transform.scale * sourceLayer.dropShadow.scale
        self.transform.rotation = sourceLayer.transform.rotation
        
        // Update bounds with dynamic expansion
        let minExpansion: CGFloat = 20
        let blurExpansion = shadowBlur * 1.5
        let expansion = max(minExpansion, blurExpansion)
        self.bounds = sourceLayer.bounds.insetBy(dx: -expansion, dy: -expansion)
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
