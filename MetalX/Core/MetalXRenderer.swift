import Metal
import MetalKit
import simd

class MetalXRenderer {
    private let device: MTLDevice
    private var commandQueue: MTLCommandQueue?
    internal var quadRenderer: QuadRenderer?
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
            shadowRenderer = try ShadowRenderer(device: device, commandQueue: commandQueue!)
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
            
            // Shadow is now handled as a separate layer, no special handling needed
            
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
        guard let texture = getLayerTexture(layer) else { 
            print("MetalXRenderer: No texture for layer: \(layer.name)")
            return 
        }
        
        print("MetalXRenderer: Got texture \(texture.width)x\(texture.height) for layer: \(layer.name)")
        
        let transform = calculateTransformMatrix(for: layer, canvasSize: canvasSize)
        quadRenderer?.render(
            encoder: encoder,
            texture: texture,
            transform: transform,
            opacity: layer.opacity,
            blendMode: layer.blendMode
        )
    }
    
    private func renderLayerForExport(_ layer: any Layer, encoder: MTLRenderCommandEncoder, canvasSize: CGSize, exportSize: CGSize, scale: CGFloat) {
        guard let texture = getLayerTexture(layer) else { 
            print("MetalXRenderer: No texture for layer: \(layer.name)")
            return 
        }
        
        print("MetalXRenderer: Got texture \(texture.width)x\(texture.height) for layer: \(layer.name)")
        
        // Create a scaled transform for export
        var scaledTransform = layer.transform
        scaledTransform.position = CGPoint(
            x: layer.transform.position.x * scale,
            y: layer.transform.position.y * scale
        )
        scaledTransform.scale = layer.transform.scale * scale
        
        let transform = calculateTransformMatrix(for: scaledTransform, layerSize: layer.bounds.size, canvasSize: exportSize)
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
        } else if let shadowLayer = layer as? ShadowLayer {
            if let context = sharedRenderContext {
                return shadowLayer.render(context: context)
            }
        }
        return nil
    }
    
    func calculateTransformMatrix(for layer: any Layer, canvasSize: CGSize) -> simd_float4x4 {
        return calculateTransformMatrix(for: layer.transform, layerSize: layer.bounds.size, canvasSize: canvasSize)
    }
    
    func calculateTransformMatrix(for transform: LayerTransform, layerSize: CGSize, canvasSize: CGSize) -> simd_float4x4 {
        
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
        
        // Apply flips by negating scale
        let scaleX: Float = transform.flipHorizontal ? -1.0 : 1.0
        let scaleY: Float = transform.flipVertical ? -1.0 : 1.0
        
        // Scale, flip and rotate
        matrix.columns.0.x = cos_r * halfWidth * pixelToNDC.x * scaleX
        matrix.columns.0.y = sin_r * halfWidth * pixelToNDC.y * scaleX
        matrix.columns.1.x = -sin_r * halfHeight * pixelToNDC.x * scaleY
        matrix.columns.1.y = cos_r * halfHeight * pixelToNDC.y * scaleY
        
        // Translation (convert from canvas center to NDC)
        matrix.columns.3.x = (centerX - Float(canvasSize.width) * 0.5) * pixelToNDC.x
        matrix.columns.3.y = (centerY - Float(canvasSize.height) * 0.5) * pixelToNDC.y
        
        return matrix
    }
    
    // MARK: - Offscreen Rendering for Export
    
    func renderToTexture(canvas: Canvas, size: CGSize) -> MTLTexture? {
        guard size.width > 0, size.height > 0 else { 
            print("MetalXRenderer: Invalid size for texture: \(size)")
            return nil 
        }
        
        print("MetalXRenderer: Creating texture with size: \(size)")
        
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: Int(size.width),
            height: Int(size.height),
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .renderTarget]
        descriptor.storageMode = .shared
        
        guard let texture = device.makeTexture(descriptor: descriptor),
              let commandBuffer = commandQueue?.makeCommandBuffer() else { 
            print("MetalXRenderer: Failed to create texture or command buffer")
            return nil 
        }
        
        // Create render pass descriptor
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        // Use white background for export/preview
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: 1.0,
            green: 1.0,
            blue: 1.0,
            alpha: 1.0
        )
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        
        // Calculate scale factor for export
        let scaleX = size.width / canvas.size.width
        let scaleY = size.height / canvas.size.height
        let scale = min(scaleX, scaleY) // Maintain aspect ratio
        
        // Render all visible layers
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            print("MetalXRenderer: Rendering \(canvas.layers.filter { $0.isVisible }.count) visible layers")
            print("MetalXRenderer: Canvas size: \(canvas.size), Export size: \(size), Scale: \(scale)")
            
            for layer in canvas.layers where layer.isVisible {
                print("MetalXRenderer: Rendering layer: \(layer.name) at position: \(layer.transform.position)")
                renderLayerForExport(layer, encoder: encoder, canvasSize: canvas.size, exportSize: size, scale: scale)
            }
            encoder.endEncoding()
        } else {
            print("MetalXRenderer: Failed to create render encoder")
        }
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return texture
    }
    
    func renderToUIImage(canvas: Canvas, size: CGSize) -> UIImage? {
        print("MetalXRenderer: renderToUIImage called with size: \(size), canvas has \(canvas.layers.count) layers")
        guard let texture = renderToTexture(canvas: canvas, size: size) else { 
            print("MetalXRenderer: Failed to render to texture")
            return nil 
        }
        
        let width = texture.width
        let height = texture.height
        let bytesPerRow = width * 4
        let dataSize = bytesPerRow * height
        
        var imageBytes = [UInt8](repeating: 0, count: dataSize)
        texture.getBytes(&imageBytes,
                        bytesPerRow: bytesPerRow,
                        from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                       size: MTLSize(width: width, height: height, depth: 1)),
                        mipmapLevel: 0)
        
        // Convert BGRA to RGBA
        for i in stride(from: 0, to: imageBytes.count, by: 4) {
            imageBytes.swapAt(i, i + 2)
        }
        
        // Create CGImage
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let dataProvider = CGDataProvider(data: Data(imageBytes) as CFData),
              let cgImage = CGImage(width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bitsPerPixel: 32,
                                  bytesPerRow: bytesPerRow,
                                  space: colorSpace,
                                  bitmapInfo: bitmapInfo,
                                  provider: dataProvider,
                                  decode: nil,
                                  shouldInterpolate: true,
                                  intent: .defaultIntent) else { return nil }
        
        return UIImage(cgImage: cgImage)
    }
}