import Foundation
import UIKit
import Metal
import MetalKit
import CoreGraphics
import simd

// Background layer that covers the entire canvas
class BackgroundLayer: BaseLayer {
    enum FillType {
        case solid(CGColor)
        case gradient(Gradient)
        case image(UIImage)
    }
    
    var fillType: FillType = .solid(UIColor.white.cgColor) {
        didSet {
            invalidateRenderCache()
        }
    }
    
    private weak var canvas: Canvas?
    private var cachedTexture: MTLTexture?
    private var cachedFillType: String = ""
    
    init(canvas: Canvas) {
        self.canvas = canvas
        super.init()
        self.name = "Background"
        self.isLocked = true // Background should typically stay locked
        self.zIndex = -1000 // Always render first
        updateBoundsToCanvas()
    }
    
    // Background layers are internal and shown differently in UI
    override var isInternal: Bool { true }
    
    override func render(context: RenderContext) -> MTLTexture? {
        guard let canvas = canvas else { return nil }
        
        // Update bounds if canvas size changed
        if bounds.size != canvas.size {
            updateBoundsToCanvas()
            cachedTexture = nil
        }
        
        // Check if we need to re-render
        let currentFillType = fillTypeDescription
        if let cached = cachedTexture,
           cached.width == Int(canvas.size.width),
           cached.height == Int(canvas.size.height),
           cachedFillType == currentFillType {
            return cached
        }
        
        // Create texture matching canvas size
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: Int(canvas.size.width),
            height: Int(canvas.size.height),
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        
        guard let texture = context.device.device.makeTexture(descriptor: descriptor),
              let commandBuffer = context.device.commandQueue.makeCommandBuffer() else {
            return nil
        }
        
        // Render based on fill type
        switch fillType {
        case .solid(let color):
            renderSolidColor(color, to: texture, commandBuffer: commandBuffer)
            
        case .gradient(let gradient):
            renderGradient(gradient, to: texture, context: context, commandBuffer: commandBuffer)
            
        case .image(let image):
            renderImage(image, to: texture, context: context, commandBuffer: commandBuffer)
        }
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        cachedTexture = texture
        cachedFillType = currentFillType
        
        return texture
    }
    
    private func renderSolidColor(_ color: CGColor, to texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        
        let components = color.components ?? [0, 0, 0, 1]
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: Double(components[safe: 0] ?? 0),
            green: Double(components[safe: 1] ?? 0),
            blue: Double(components[safe: 2] ?? 0),
            alpha: Double(components[safe: 3] ?? 1)
        )
        
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        encoder.endEncoding()
    }
    
    private func renderGradient(_ gradient: Gradient, to texture: MTLTexture, context: RenderContext, commandBuffer: MTLCommandBuffer) {
        // For now, just render a solid color as placeholder
        // TODO: Implement proper gradient rendering
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        
        // Use first color stop as solid fill
        if let firstStop = gradient.colorStops.first {
            let components = firstStop.color.components ?? [0, 0, 0, 1]
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(
                red: Double(components[safe: 0] ?? 0),
                green: Double(components[safe: 1] ?? 0),
                blue: Double(components[safe: 2] ?? 0),
                alpha: Double(components[safe: 3] ?? 1)
            )
        }
        
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        encoder.endEncoding()
    }
    
    private func renderImage(_ image: UIImage, to texture: MTLTexture, context: RenderContext, commandBuffer: MTLCommandBuffer) {
        // Create texture from UIImage using MTKTextureLoader
        guard let cgImage = image.cgImage else { return }
        
        let textureLoader = MTKTextureLoader(device: context.device.device)
        guard let imageTexture = try? textureLoader.newTexture(cgImage: cgImage, options: [
            .SRGB: false,
            .generateMipmaps: false
        ]) else { return }
        
        // Calculate how to fit image to canvas
        let canvasSize = canvas?.size ?? .zero
        let imageSize = image.size
        
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        
        // Create a quad renderer
        let renderer = QuadRenderer(device: context.device.device)
        
        // Calculate transform to fit image
        var transform = matrix_identity_float4x4
        
        // Scale to fill canvas (you could also add fit/fill/stretch options)
        let scaleX = Float(canvasSize.width / imageSize.width)
        let scaleY = Float(canvasSize.height / imageSize.height)
        let scale = max(scaleX, scaleY) // Fill mode - use min for fit mode
        
        transform.columns.0.x = scale
        transform.columns.1.y = scale
        
        renderer.render(
            encoder: encoder,
            texture: imageTexture,
            transform: transform,
            opacity: 1.0,
            blendMode: .normal
        )
        
        encoder.endEncoding()
    }
    
    override func getBounds(includeEffects: Bool) -> CGRect {
        return bounds
    }
    
    override func hitTest(point: CGPoint) -> Bool {
        // Background always fills the canvas
        return bounds.contains(point)
    }
    
    func updateBoundsToCanvas() {
        guard let canvas = canvas else { return }
        
        self.bounds = CGRect(origin: .zero, size: canvas.size)
        self.transform.position = CGPoint(x: canvas.size.width / 2, y: canvas.size.height / 2)
        self.transform.scale = 1.0
        
        invalidateRenderCache()
    }
    
    private func invalidateRenderCache() {
        cachedTexture = nil
        NotificationCenter.default.post(name: NSNotification.Name("CanvasNeedsDisplay"), object: nil)
    }
    
    private var fillTypeDescription: String {
        switch fillType {
        case .solid(let color):
            return "solid:\(color.components?.description ?? "")"
        case .gradient(let gradient):
            return "gradient:\(gradient.colorStops.count)"
        case .image(let image):
            return "image:\(image.size)"
        }
    }
}
