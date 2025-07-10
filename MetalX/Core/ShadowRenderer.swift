import Metal
import MetalKit
import CoreGraphics
import simd

// Advanced shadow renderer with Gaussian blur
class ShadowRenderer {
    private let device: MTLDevice
    private let library: MTLLibrary
    
    // Pipeline states
    private var horizontalBlurPipelineState: MTLRenderPipelineState?
    private var verticalBlurPipelineState: MTLRenderPipelineState?
    private var shadowCompositePipelineState: MTLRenderPipelineState?
    private var quadPipelineState: MTLRenderPipelineState?
    
    // Temporary textures for blur passes
    private var blurIntermediateTexture: MTLTexture?
    private var blurredShadowTexture: MTLTexture?
    
    // Vertex and index buffers for quad
    private var vertexBuffer: MTLBuffer?
    private var indexBuffer: MTLBuffer?
    
    init(device: MTLDevice) throws {
        self.device = device
        
        guard let library = device.makeDefaultLibrary() else {
            throw ShadowRendererError.failedToLoadLibrary
        }
        self.library = library
        
        try setupPipeline()
        setupBuffers()
    }
    
    private func setupPipeline() throws {
        // Setup horizontal blur pipeline
        let horizontalDescriptor = MTLRenderPipelineDescriptor()
        guard let blurVertex = library.makeFunction(name: "blurVertex") else {
            throw ShadowRendererError.functionNotFound("blurVertex")
        }
        guard let horizontalBlurFragment = library.makeFunction(name: "gaussianBlurHorizontal") else {
            throw ShadowRendererError.functionNotFound("gaussianBlurHorizontal")
        }
        horizontalDescriptor.vertexFunction = blurVertex
        horizontalDescriptor.fragmentFunction = horizontalBlurFragment
        horizontalDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        horizontalBlurPipelineState = try device.makeRenderPipelineState(descriptor: horizontalDescriptor)
        
        // Setup vertical blur pipeline
        let verticalDescriptor = MTLRenderPipelineDescriptor()
        guard let verticalBlurFragment = library.makeFunction(name: "gaussianBlurVertical") else {
            throw ShadowRendererError.functionNotFound("gaussianBlurVertical")
        }
        verticalDescriptor.vertexFunction = blurVertex
        verticalDescriptor.fragmentFunction = verticalBlurFragment
        verticalDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        verticalBlurPipelineState = try device.makeRenderPipelineState(descriptor: verticalDescriptor)
        
        // Setup shadow composite pipeline
        let compositeDescriptor = MTLRenderPipelineDescriptor()
        guard let simpleVertex = library.makeFunction(name: "simpleVertex") else {
            throw ShadowRendererError.functionNotFound("simpleVertex")
        }
        guard let shadowCompositeFragment = library.makeFunction(name: "shadowComposite") else {
            throw ShadowRendererError.functionNotFound("shadowComposite")
        }
        
        compositeDescriptor.vertexFunction = simpleVertex
        compositeDescriptor.fragmentFunction = shadowCompositeFragment
        
        // Setup vertex descriptor for composite
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.size * 2
        vertexDescriptor.attributes[1].bufferIndex = 0
        
        vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.size * 4
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        
        compositeDescriptor.vertexDescriptor = vertexDescriptor
        compositeDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        // Enable blending for shadow compositing
        compositeDescriptor.colorAttachments[0].isBlendingEnabled = true
        compositeDescriptor.colorAttachments[0].rgbBlendOperation = .add
        compositeDescriptor.colorAttachments[0].alphaBlendOperation = .add
        compositeDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        compositeDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        compositeDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        compositeDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        shadowCompositePipelineState = try device.makeRenderPipelineState(descriptor: compositeDescriptor)
        
        // Setup quad pipeline for initial render
        quadPipelineState = try createSimpleQuadPipeline()
    }
    
    private func setupBuffers() {
        // Simple quad vertices with texture coordinates
        let vertices: [Float] = [
            -1.0, -1.0, 0.0, 0.0,  // bottom left
             1.0, -1.0, 1.0, 0.0,  // bottom right
             1.0,  1.0, 1.0, 1.0,  // top right
            -1.0,  1.0, 0.0, 1.0   // top left
        ]
        
        let indices: [UInt16] = [0, 1, 2, 2, 3, 0]
        
        vertexBuffer = device.makeBuffer(bytes: vertices,
                                         length: vertices.count * MemoryLayout<Float>.size,
                                         options: [])
        
        indexBuffer = device.makeBuffer(bytes: indices,
                                        length: indices.count * MemoryLayout<UInt16>.size,
                                        options: [])
    }
    
    // Create or update blur textures if needed
    private func updateBlurTextures(size: CGSize) {
        let width = Int(size.width)
        let height = Int(size.height)
        
        // Check if we need to recreate textures
        if let existing = blurIntermediateTexture,
           existing.width == width && existing.height == height {
            return
        }
        
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .renderTarget]
        descriptor.storageMode = .shared
        
        blurIntermediateTexture = device.makeTexture(descriptor: descriptor)
        blurredShadowTexture = device.makeTexture(descriptor: descriptor)
    }
    
    // Calculate the padded texture size needed for shadow with blur and offset
    private func calculateShadowTextureSize(layerBounds: CGRect, dropShadow: DropShadow) -> (size: CGSize, padding: CGFloat) {
        // For now, just use the layer bounds without padding to simplify positioning
        // The blur will be slightly clipped at edges but positioning will be correct
        return (layerBounds.size, 0)
    }
    
    // Main shadow rendering function with Gaussian blur
    func renderShadow(
        layerTexture: MTLTexture,
        targetTexture: MTLTexture,
        commandBuffer: MTLCommandBuffer,
        dropShadow: DropShadow,
        transform: matrix_float4x4,
        viewportSize: CGSize,
        layerBounds: CGRect
    ) {
        guard dropShadow.isEnabled,
              let horizontalBlurPipelineState = horizontalBlurPipelineState,
              let verticalBlurPipelineState = verticalBlurPipelineState,
              let shadowCompositePipelineState = shadowCompositePipelineState else {
            return
        }
        
        // Calculate the texture size needed for the shadow
        let (shadowTextureSize, padding) = calculateShadowTextureSize(layerBounds: layerBounds, dropShadow: dropShadow)
        
        // Update blur textures with the calculated size
        updateBlurTextures(size: shadowTextureSize)
        
        guard let blurIntermediateTexture = blurIntermediateTexture,
              let blurredShadowTexture = blurredShadowTexture else {
            return
        }
        
        // Viewport for shadow textures
        let shadowViewport = MTLViewport(
            originX: 0,
            originY: 0,
            width: Double(shadowTextureSize.width),
            height: Double(shadowTextureSize.height),
            znear: 0,
            zfar: 1
        )
        
        // Viewport for final composite
        let targetViewport = MTLViewport(
            originX: 0,
            originY: 0,
            width: Double(viewportSize.width),
            height: Double(viewportSize.height),
            znear: 0,
            zfar: 1
        )
        
        // Step 1: Render layer to intermediate texture centered in the padded area
        let renderDescriptor = MTLRenderPassDescriptor()
        renderDescriptor.colorAttachments[0].texture = blurIntermediateTexture
        renderDescriptor.colorAttachments[0].loadAction = .clear
        renderDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        renderDescriptor.colorAttachments[0].storeAction = .store
        
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderDescriptor) {
            encoder.label = "Shadow Layer Render"
            encoder.setViewport(shadowViewport)
            
            // Use the quad renderer approach - render the layer texture centered in padded texture
            if let quadPipelineState = quadPipelineState {
                encoder.setRenderPipelineState(quadPipelineState)
                encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
                
                // Since we're not using padding, render at full size
                var mutableTransform = matrix_identity_float4x4
                encoder.setVertexBytes(&mutableTransform, length: MemoryLayout<matrix_float4x4>.size, index: 1)
                encoder.setFragmentTexture(layerTexture, index: 0)
                
                // Create sampler state
                let samplerDescriptor = MTLSamplerDescriptor()
                samplerDescriptor.minFilter = .linear
                samplerDescriptor.magFilter = .linear
                samplerDescriptor.sAddressMode = .clampToEdge
                samplerDescriptor.tAddressMode = .clampToEdge
                if let samplerState = device.makeSamplerState(descriptor: samplerDescriptor) {
                    encoder.setFragmentSamplerState(samplerState, index: 0)
                }
                
                encoder.drawIndexedPrimitives(type: .triangle,
                                            indexCount: 6,
                                            indexType: .uint16,
                                            indexBuffer: indexBuffer!,
                                            indexBufferOffset: 0)
            }
            encoder.endEncoding()
        }
        
        // Step 2: Horizontal blur pass
        let horizontalBlurDescriptor = MTLRenderPassDescriptor()
        horizontalBlurDescriptor.colorAttachments[0].texture = blurredShadowTexture
        horizontalBlurDescriptor.colorAttachments[0].loadAction = .clear
        horizontalBlurDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        horizontalBlurDescriptor.colorAttachments[0].storeAction = .store
        
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: horizontalBlurDescriptor) {
            encoder.label = "Horizontal Blur Pass"
            encoder.setViewport(shadowViewport)
            encoder.setRenderPipelineState(horizontalBlurPipelineState)
            encoder.setFragmentTexture(blurIntermediateTexture, index: 0)
            
            // Pass blur radius
            var blurRadius = Float(dropShadow.blur)
            encoder.setFragmentBytes(&blurRadius, length: MemoryLayout<Float>.size, index: 0)
            
            // Draw full-screen triangle
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }
        
        // Step 3: Vertical blur pass (render back to intermediate)
        let verticalBlurDescriptor = MTLRenderPassDescriptor()
        verticalBlurDescriptor.colorAttachments[0].texture = blurIntermediateTexture
        verticalBlurDescriptor.colorAttachments[0].loadAction = .clear
        verticalBlurDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        verticalBlurDescriptor.colorAttachments[0].storeAction = .store
        
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: verticalBlurDescriptor) {
            encoder.label = "Vertical Blur Pass"
            encoder.setViewport(shadowViewport)
            encoder.setRenderPipelineState(verticalBlurPipelineState)
            encoder.setFragmentTexture(blurredShadowTexture, index: 0)
            
            // Pass blur radius
            var blurRadius = Float(dropShadow.blur)
            encoder.setFragmentBytes(&blurRadius, length: MemoryLayout<Float>.size, index: 0)
            
            // Draw full-screen triangle
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }
        
        // Step 4: Composite the blurred shadow with offset and color tint
        let compositeDescriptor = createRenderPassDescriptor(for: targetTexture)
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: compositeDescriptor) {
            encoder.label = "Shadow Composite Pass"
            encoder.setViewport(targetViewport)
            encoder.setRenderPipelineState(shadowCompositePipelineState)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            
            // Since we're not using padding anymore, just apply the offset to the original transform
            
            // Convert shadow offset from pixels to NDC
            let offsetX = Float(dropShadow.offset.width) / (Float(viewportSize.width) / 2.0)
            let offsetY = -Float(dropShadow.offset.height) / (Float(viewportSize.height) / 2.0) // Flip Y
            
            // Copy the original transform and add the offset
            var shadowTransform = transform
            shadowTransform.columns.3.x += offsetX
            shadowTransform.columns.3.y += offsetY
            
            encoder.setVertexBytes(&shadowTransform, length: MemoryLayout<matrix_float4x4>.size, index: 1)
            
            // Set the blurred shadow texture
            encoder.setFragmentTexture(blurIntermediateTexture, index: 0)
            
            // Create sampler state for composite
            let samplerDescriptor = MTLSamplerDescriptor()
            samplerDescriptor.minFilter = .linear
            samplerDescriptor.magFilter = .linear
            samplerDescriptor.sAddressMode = .clampToEdge
            samplerDescriptor.tAddressMode = .clampToEdge
            if let samplerState = device.makeSamplerState(descriptor: samplerDescriptor) {
                encoder.setFragmentSamplerState(samplerState, index: 0)
            }
            
            // Pass shadow color and opacity
            var shadowColor = colorToSIMD4(dropShadow.color)
            var shadowOpacity = dropShadow.opacity
            encoder.setFragmentBytes(&shadowColor, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
            encoder.setFragmentBytes(&shadowOpacity, length: MemoryLayout<Float>.size, index: 1)
            
            // Draw the shadow quad
            encoder.drawIndexedPrimitives(type: .triangle,
                                        indexCount: 6,
                                        indexType: .uint16,
                                        indexBuffer: indexBuffer!,
                                        indexBufferOffset: 0)
            
            encoder.endEncoding()
        }
    }
    
    // Helper function to create render pass descriptor
    private func createRenderPassDescriptor(for texture: MTLTexture) -> MTLRenderPassDescriptor {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        descriptor.colorAttachments[0].loadAction = .load
        descriptor.colorAttachments[0].storeAction = .store
        return descriptor
    }
    
    
    // Helper to create a simple quad pipeline for rendering layer to texture
    private func createSimpleQuadPipeline() throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        
        guard let vertexFunction = library.makeFunction(name: "simpleVertex"),
              let fragmentFunction = library.makeFunction(name: "simplePassthroughFragment") else {
            throw ShadowRendererError.functionNotFound("simpleVertex/simplePassthroughFragment")
        }
        
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.size * 2
        vertexDescriptor.attributes[1].bufferIndex = 0
        
        vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.size * 4
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        
        descriptor.vertexDescriptor = vertexDescriptor
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    // Convert CGColor to SIMD4<Float>
    private func colorToSIMD4(_ color: CGColor) -> SIMD4<Float> {
        let components = color.components ?? [0, 0, 0, 1]
        
        if components.count >= 4 {
            return SIMD4<Float>(
                Float(components[0]),
                Float(components[1]),
                Float(components[2]),
                Float(components[3])
            )
        } else if components.count >= 3 {
            return SIMD4<Float>(
                Float(components[0]),
                Float(components[1]),
                Float(components[2]),
                1.0
            )
        } else if components.count >= 1 {
            let gray = Float(components[0])
            let alpha = components.count >= 2 ? Float(components[1]) : 1.0
            return SIMD4<Float>(gray, gray, gray, alpha)
        }
        
        return SIMD4<Float>(0, 0, 0, 1)
    }
}

enum ShadowRendererError: Error {
    case failedToLoadLibrary
    case functionNotFound(String)
}