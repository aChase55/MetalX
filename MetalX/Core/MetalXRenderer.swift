import Metal
import MetalKit
import simd

class MetalXRenderer {
    private let device: MTLDevice
    private var commandQueue: MTLCommandQueue?
    private var quadRenderer: QuadRenderer?
    private var advancedBlendRenderer: AdvancedBlendRenderer?
    private var shadowRenderer: ShadowRenderer?
    private var sharedRenderContext: RenderContext?
    
    // Render textures
    private var accumulationTexture: MTLTexture?
    private var tempTexture: MTLTexture?
    
    init(device: MTLDevice) {
        self.device = device
        setup()
    }
    
    private func setup() {
        commandQueue = device.makeCommandQueue()
        quadRenderer = QuadRenderer(device: device)
        advancedBlendRenderer = AdvancedBlendRenderer(device: device)
        
        // Initialize shadow renderer
        do {
            shadowRenderer = try ShadowRenderer(device: device)
        } catch {
            print("Failed to create shadow renderer: \(error)")
        }
        
        // Initialize shared render context
        do {
            let metalDevice = try MetalDevice(preferredDevice: device)
            sharedRenderContext = RenderContext(device: metalDevice)
        } catch {
            print("Failed to create shared render context: \(error)")
        }
    }
    
    func updateDrawableSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: Int(size.width),
            height: Int(size.height),
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .renderTarget]
        descriptor.storageMode = .shared
        
        accumulationTexture = device.makeTexture(descriptor: descriptor)
        tempTexture = device.makeTexture(descriptor: descriptor)
    }
    
    func render(canvas: Canvas, in view: MTKView, selectedLayer: (any Layer)?) {
        guard canvas.needsDisplay else { return }
        
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue?.makeCommandBuffer() else { return }
        
        let viewportSize = view.drawableSize
        let selectionTime = Float(CACurrentMediaTime())
        
        // Always use advanced rendering for consistent results
        if accumulationTexture != nil && tempTexture != nil {
            renderAdvanced(
                canvas: canvas,
                descriptor: descriptor,
                commandBuffer: commandBuffer,
                viewportSize: viewportSize,
                selectedLayer: selectedLayer,
                selectionTime: selectionTime
            )
        } else {
            renderSimple(
                canvas: canvas,
                descriptor: descriptor,
                commandBuffer: commandBuffer,
                viewportSize: viewportSize,
                selectedLayer: selectedLayer,
                selectionTime: selectionTime
            )
        }
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
        
        canvas.needsDisplay = false
    }
    
    private func renderAdvanced(
        canvas: Canvas,
        descriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer,
        viewportSize: CGSize,
        selectedLayer: (any Layer)?,
        selectionTime: Float
    ) {
        guard let accumulationTexture = accumulationTexture,
              let tempTexture = tempTexture,
              let advancedBlendRenderer = advancedBlendRenderer else {
            renderSimple(canvas: canvas, descriptor: descriptor, commandBuffer: commandBuffer, viewportSize: viewportSize, selectedLayer: selectedLayer, selectionTime: selectionTime)
            return
        }
        
        // Clear accumulation texture
        let clearDescriptor = MTLRenderPassDescriptor()
        clearDescriptor.colorAttachments[0].texture = accumulationTexture
        clearDescriptor.colorAttachments[0].loadAction = .clear
        clearDescriptor.colorAttachments[0].clearColor = descriptor.colorAttachments[0].clearColor
        clearDescriptor.colorAttachments[0].storeAction = .store
        
        if let clearEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: clearDescriptor) {
            clearEncoder.endEncoding()
        }
        
        // Render layers with advanced blending
        var currentTexture = accumulationTexture
        var targetTexture = tempTexture
        
        for layer in canvas.layers where layer.isVisible {
            guard let layerTexture = getLayerTexture(layer) else { continue }
            
            // Copy current to target for ping-pong rendering
            if let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
                blitEncoder.copy(
                    from: currentTexture,
                    sourceSlice: 0,
                    sourceLevel: 0,
                    sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                    sourceSize: MTLSize(width: currentTexture.width, height: currentTexture.height, depth: 1),
                    to: targetTexture,
                    destinationSlice: 0,
                    destinationLevel: 0,
                    destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
                )
                blitEncoder.endEncoding()
            }
            
            // Render shadow if enabled
            if layer.dropShadow.isEnabled, let shadowRenderer = shadowRenderer {
                let transform = calculateTransformMatrix(for: layer, canvasSize: canvas.size)
                shadowRenderer.renderShadow(
                    layerTexture: layerTexture,
                    targetTexture: targetTexture,
                    commandBuffer: commandBuffer,
                    dropShadow: layer.dropShadow,
                    transform: transform,
                    viewportSize: viewportSize,
                    layerBounds: layer.bounds
                )
            }
            
            // Render layer with blending
            let blendDescriptor = MTLRenderPassDescriptor()
            blendDescriptor.colorAttachments[0].texture = targetTexture
            blendDescriptor.colorAttachments[0].loadAction = .load
            blendDescriptor.colorAttachments[0].storeAction = .store
            
            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: blendDescriptor) {
                let transform = calculateTransformMatrix(for: layer, canvasSize: canvas.size)
                
                advancedBlendRenderer.render(
                    encoder: encoder,
                    sourceTexture: layerTexture,
                    destinationTexture: currentTexture,
                    transform: transform,
                    opacity: layer.opacity,
                    blendMode: layer.blendMode
                )
                encoder.endEncoding()
            }
            
            // Swap textures
            swap(&currentTexture, &targetTexture)
        }
        
        // Final pass: copy result to drawable
        if let finalEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) {
            quadRenderer?.render(
                encoder: finalEncoder,
                texture: currentTexture,
                transform: matrix_identity_float4x4,
                opacity: 1.0,
                blendMode: .normal
            )
            
            // Draw selection on top
            if let selectedLayer = selectedLayer {
                renderSelection(
                    for: selectedLayer,
                    encoder: finalEncoder,
                    canvasSize: canvas.size,
                    viewportSize: viewportSize,
                    time: selectionTime
                )
            }
            
            finalEncoder.endEncoding()
        }
    }
    
    private func renderSimple(
        canvas: Canvas,
        descriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer,
        viewportSize: CGSize,
        selectedLayer: (any Layer)?,
        selectionTime: Float
    ) {
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        
        for layer in canvas.layers where layer.isVisible {
            renderLayer(layer, encoder: encoder, canvasSize: canvas.size)
        }
        
        if let selectedLayer = selectedLayer {
            renderSelection(
                for: selectedLayer,
                encoder: encoder,
                canvasSize: canvas.size,
                viewportSize: viewportSize,
                time: selectionTime
            )
        }
        
        encoder.endEncoding()
    }
    
    private func renderLayer(_ layer: any Layer, encoder: MTLRenderCommandEncoder, canvasSize: CGSize) {
        guard let texture = getLayerTexture(layer) else { return }
        
        let transform = calculateTransformMatrix(for: layer, canvasSize: canvasSize)
        quadRenderer?.render(
            encoder: encoder,
            texture: texture,
            transform: transform,
            opacity: layer.opacity,
            blendMode: layer.blendMode
        )
    }
    
    private func renderSelection(
        for layer: any Layer,
        encoder: MTLRenderCommandEncoder,
        canvasSize: CGSize,
        viewportSize: CGSize,
        time: Float
    ) {
        let transform = calculateTransformMatrix(for: layer, canvasSize: canvasSize)
        quadRenderer?.renderSelection(
            encoder: encoder,
            transform: transform,
            viewportSize: viewportSize,
            time: time
        )
    }
    
    // MARK: - Helper Methods
    
    private func getLayerTexture(_ layer: any Layer) -> MTLTexture? {
        if let imageLayer = layer as? ImageLayer {
            return imageLayer.texture
        } else if let textLayer = layer as? TextLayer {
            return textLayer.texture
        } else if let shapeLayer = layer as? VectorShapeLayer {
            if let context = sharedRenderContext {
                return shapeLayer.render(context: context)
            }
        }
        return nil
    }
    
    func calculateTransformMatrix(for layer: any Layer, canvasSize: CGSize) -> simd_float4x4 {
        let transform = layer.transform
        let layerSize = layer.bounds.size
        
        // Scale to convert from canvas coordinates to NDC
        let pixelToNDC = simd_float2(2.0 / Float(canvasSize.width), -2.0 / Float(canvasSize.height))
        
        // Calculate position in NDC space
        let centerX = Float(transform.position.x)
        let centerY = Float(transform.position.y)
        
        // Layer dimensions in canvas space
        let halfWidth = Float(layerSize.width * transform.scale) * 0.5
        let halfHeight = Float(layerSize.height * transform.scale) * 0.5
        
        // Build transform matrix
        var matrix = matrix_identity_float4x4
        
        // Apply rotation
        let angle = Float(transform.rotation)
        let cos_r = cos(angle)
        let sin_r = sin(angle)
        
        // Scale and rotate
        matrix.columns.0.x = cos_r * halfWidth * pixelToNDC.x
        matrix.columns.0.y = sin_r * halfWidth * pixelToNDC.y
        matrix.columns.1.x = -sin_r * halfHeight * pixelToNDC.x
        matrix.columns.1.y = cos_r * halfHeight * pixelToNDC.y
        
        // Translation (convert from canvas center to NDC)
        matrix.columns.3.x = (centerX - Float(canvasSize.width) * 0.5) * pixelToNDC.x
        matrix.columns.3.y = (centerY - Float(canvasSize.height) * 0.5) * pixelToNDC.y
        
        return matrix
    }
}