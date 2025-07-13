import Metal
import MetalKit
import MetalPerformanceShaders
import CoreGraphics

class ShadowRenderer {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    
    // Pipeline states
    private var silhouettePipelineState: MTLRenderPipelineState?
    private var horizontalBlurPipelineState: MTLRenderPipelineState?
    private var verticalBlurPipelineState: MTLRenderPipelineState?
    private var shadowCompositePipelineState: MTLRenderPipelineState?
    
    // Textures for shadow rendering
    private var shadowTexture: MTLTexture?
    private var tempBlurTexture: MTLTexture?
    private var blurredShadowTexture: MTLTexture?
    
    // Gaussian weights buffer
    private var gaussianWeightsBuffer: MTLBuffer?
    
    // Vertex buffer for full-screen quad
    private var quadVertexBuffer: MTLBuffer?
    
    // MPS blur for better performance (optional)
    private var mpsGaussianBlur: MPSImageGaussianBlur?
    private var useMPS: Bool = true
    
    struct ShadowParameters {
        let offset: CGSize
        let blur: Float
        let color: SIMD4<Float>
        let opacity: Float
    }
    
    init(device: MTLDevice, commandQueue: MTLCommandQueue) throws {
        self.device = device
        self.commandQueue = commandQueue
        
        try setupPipelines()
        setupBuffers()
    }
    
    private func setupPipelines() throws {
        guard let library = device.makeDefaultLibrary() else {
            throw ShadowError.libraryNotFound
        }
        
        // 1. Silhouette Pipeline (renders shape as solid color)
        let silhouetteDescriptor = MTLRenderPipelineDescriptor()
        silhouetteDescriptor.label = "Shadow Silhouette Pipeline"
        silhouetteDescriptor.vertexFunction = library.makeFunction(name: "shadowSilhouetteVertex")
        silhouetteDescriptor.fragmentFunction = library.makeFunction(name: "shadowSilhouetteFragment")
        silhouetteDescriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
        silhouettePipelineState = try device.makeRenderPipelineState(descriptor: silhouetteDescriptor)
        
        // 2. Horizontal Blur Pipeline
        let hBlurDescriptor = MTLRenderPipelineDescriptor()
        hBlurDescriptor.label = "Horizontal Blur Pipeline"
        hBlurDescriptor.vertexFunction = library.makeFunction(name: "fullscreenQuadVertex")
        hBlurDescriptor.fragmentFunction = library.makeFunction(name: "horizontalGaussianBlur")
        hBlurDescriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
        horizontalBlurPipelineState = try device.makeRenderPipelineState(descriptor: hBlurDescriptor)
        
        // 3. Vertical Blur Pipeline
        let vBlurDescriptor = MTLRenderPipelineDescriptor()
        vBlurDescriptor.label = "Vertical Blur Pipeline"
        vBlurDescriptor.vertexFunction = library.makeFunction(name: "fullscreenQuadVertex")
        vBlurDescriptor.fragmentFunction = library.makeFunction(name: "verticalGaussianBlur")
        vBlurDescriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
        verticalBlurPipelineState = try device.makeRenderPipelineState(descriptor: vBlurDescriptor)
        
        // 4. Shadow Composite Pipeline
        let compositeDescriptor = MTLRenderPipelineDescriptor()
        compositeDescriptor.label = "Shadow Composite Pipeline"
        compositeDescriptor.vertexFunction = library.makeFunction(name: "shadowCompositeVertex")
        compositeDescriptor.fragmentFunction = library.makeFunction(name: "shadowCompositeFragment")
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
    }
    
    private func setupBuffers() {
        // Create quad vertices for full-screen rendering
        let quadVertices: [Float] = [
            -1.0, -1.0, 0.0, 1.0,  // bottom left
             1.0, -1.0, 1.0, 1.0,  // bottom right
            -1.0,  1.0, 0.0, 0.0,  // top left
             1.0,  1.0, 1.0, 0.0   // top right
        ]
        
        quadVertexBuffer = device.makeBuffer(
            bytes: quadVertices,
            length: quadVertices.count * MemoryLayout<Float>.size,
            options: []
        )
        
        // Precompute Gaussian weights for blur kernel
        let kernelSize = 9
        var weights = [Float](repeating: 0, count: kernelSize)
        let sigma: Float = 2.0
        var sum: Float = 0
        
        for i in 0..<kernelSize {
            let x = Float(i - kernelSize / 2)
            weights[i] = exp(-(x * x) / (2 * sigma * sigma))
            sum += weights[i]
        }
        
        // Normalize weights
        for i in 0..<kernelSize {
            weights[i] /= sum
        }
        
        gaussianWeightsBuffer = device.makeBuffer(
            bytes: weights,
            length: weights.count * MemoryLayout<Float>.size,
            options: []
        )
    }
    
    private func updateShadowTextures(size: CGSize) {
        let width = Int(size.width)
        let height = Int(size.height)
        
        // Check if we need to recreate textures
        if let existing = shadowTexture,
           existing.width == width && existing.height == height {
            return
        }
        
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        
        shadowTexture = device.makeTexture(descriptor: descriptor)
        tempBlurTexture = device.makeTexture(descriptor: descriptor)
        blurredShadowTexture = device.makeTexture(descriptor: descriptor)
    }
    
    func renderShadow(
        layerTexture: MTLTexture,
        targetTexture: MTLTexture,
        commandBuffer: MTLCommandBuffer,
        shadowParams: ShadowParameters,
        transform: float4x4
    ) {
        // Update textures if needed
        let renderSize = CGSize(
            width: CGFloat(targetTexture.width),
            height: CGFloat(targetTexture.height)
        )
        updateShadowTextures(size: renderSize)
        
        guard let shadowTexture = shadowTexture,
              let tempBlurTexture = tempBlurTexture,
              let blurredShadowTexture = blurredShadowTexture else {
            return
        }
        
        // Step 1: Render silhouette to shadow texture
        renderSilhouette(
            sourceTexture: layerTexture,
            to: shadowTexture,
            transform: transform,
            commandBuffer: commandBuffer
        )
        
        // Apply blur using MPS if available and appropriate, otherwise use custom blur
        if useMPS && shadowParams.blur > 0.1 {
            applyMPSBlur(
                from: shadowTexture,
                to: blurredShadowTexture,
                blurRadius: shadowParams.blur,
                commandBuffer: commandBuffer
            )
        } else if shadowParams.blur > 0.001 {
            // Step 2: Apply horizontal blur
            applyHorizontalBlur(
                from: shadowTexture,
                to: tempBlurTexture,
                blurRadius: shadowParams.blur,
                commandBuffer: commandBuffer
            )
            
            // Step 3: Apply vertical blur
            applyVerticalBlur(
                from: tempBlurTexture,
                to: blurredShadowTexture,
                blurRadius: shadowParams.blur,
                commandBuffer: commandBuffer
            )
        } else {
            // No blur needed, just copy the shadow texture
            guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else { return }
            blitEncoder.copy(from: shadowTexture, to: blurredShadowTexture)
            blitEncoder.endEncoding()
        }
        
        // Step 4: Composite shadow with offset
        compositeShadow(
            shadowTexture: blurredShadowTexture,
            to: targetTexture,
            shadowParams: shadowParams,
            transform: transform,
            commandBuffer: commandBuffer
        )
    }
    
    private func renderSilhouette(
        sourceTexture: MTLTexture,
        to texture: MTLTexture,
        transform: float4x4,
        commandBuffer: MTLCommandBuffer
    ) {
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        encoder.label = "Silhouette Render Pass"
        
        encoder.setRenderPipelineState(silhouettePipelineState!)
        encoder.setVertexBuffer(quadVertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(sourceTexture, index: 0)
        
        // Set viewport to render source texture centered in the larger texture
        let paddingX = (texture.width - sourceTexture.width) / 2
        let paddingY = (texture.height - sourceTexture.height) / 2
        encoder.setViewport(MTLViewport(
            originX: Double(paddingX),
            originY: Double(paddingY),
            width: Double(sourceTexture.width),
            height: Double(sourceTexture.height),
            znear: 0.0,
            zfar: 1.0
        ))
        
        // Draw quad
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        
        encoder.endEncoding()
    }
    
    private func applyHorizontalBlur(
        from sourceTexture: MTLTexture,
        to destinationTexture: MTLTexture,
        blurRadius: Float,
        commandBuffer: MTLCommandBuffer
    ) {
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = destinationTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        encoder.label = "Horizontal Blur Pass"
        
        encoder.setRenderPipelineState(horizontalBlurPipelineState!)
        encoder.setVertexBuffer(quadVertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(sourceTexture, index: 0)
        encoder.setFragmentBuffer(gaussianWeightsBuffer, offset: 0, index: 0)
        
        var radius = blurRadius
        encoder.setFragmentBytes(&radius, length: MemoryLayout<Float>.size, index: 1)
        
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
    }
    
    private func applyVerticalBlur(
        from sourceTexture: MTLTexture,
        to destinationTexture: MTLTexture,
        blurRadius: Float,
        commandBuffer: MTLCommandBuffer
    ) {
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = destinationTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        encoder.label = "Vertical Blur Pass"
        
        encoder.setRenderPipelineState(verticalBlurPipelineState!)
        encoder.setVertexBuffer(quadVertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(sourceTexture, index: 0)
        encoder.setFragmentBuffer(gaussianWeightsBuffer, offset: 0, index: 0)
        
        var radius = blurRadius
        encoder.setFragmentBytes(&radius, length: MemoryLayout<Float>.size, index: 1)
        
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
    }
    
    private func compositeShadow(
        shadowTexture: MTLTexture,
        to destinationTexture: MTLTexture,
        shadowParams: ShadowParameters,
        transform: float4x4,
        commandBuffer: MTLCommandBuffer
    ) {
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = destinationTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .load
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        encoder.label = "Shadow Composite Pass"
        
        encoder.setRenderPipelineState(shadowCompositePipelineState!)
        encoder.setVertexBuffer(quadVertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(shadowTexture, index: 0)
        
        // Shadow offset is now baked into the transform, so just use it directly
        var shadowTransform = transform
        encoder.setVertexBytes(&shadowTransform, length: MemoryLayout<float4x4>.size, index: 1)
        
        var color = shadowParams.color
        encoder.setFragmentBytes(&color, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
        
        var opacity = shadowParams.opacity
        encoder.setFragmentBytes(&opacity, length: MemoryLayout<Float>.size, index: 1)
        
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
    }
    
    private func applyMPSBlur(
        from sourceTexture: MTLTexture,
        to destinationTexture: MTLTexture,
        blurRadius: Float,
        commandBuffer: MTLCommandBuffer
    ) {
        // Create or update MPS blur with the desired radius
        // For a more visible blur, use a larger sigma relative to the radius
        let sigma = blurRadius // Use radius directly as sigma for stronger blur
        if mpsGaussianBlur == nil || mpsGaussianBlur!.sigma != sigma {
            mpsGaussianBlur = MPSImageGaussianBlur(device: device, sigma: sigma)
            // Ensure the blur doesn't extend beyond the texture bounds
            mpsGaussianBlur?.edgeMode = .clamp
        }
        
        // Apply the blur
        mpsGaussianBlur?.encode(
            commandBuffer: commandBuffer,
            sourceTexture: sourceTexture,
            destinationTexture: destinationTexture
        )
    }
}

enum ShadowError: Error {
    case libraryNotFound
    case commandBufferCreationFailed
    case textureCreationFailed
}