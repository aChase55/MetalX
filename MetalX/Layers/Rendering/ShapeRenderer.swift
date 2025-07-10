import Metal
import MetalKit
import CoreGraphics

// Shape renderer for vector graphics
class ShapeRenderer {
    private let device: MTLDevice
    private let library: MTLLibrary
    private var solidFillPipelineState: MTLRenderPipelineState?
    private var linearGradientPipelineState: MTLRenderPipelineState?
    private var radialGradientPipelineState: MTLRenderPipelineState?
    private var angularGradientPipelineState: MTLRenderPipelineState?
    private var imageFillPipelineState: MTLRenderPipelineState?
    private var strokePipelineState: MTLRenderPipelineState?
    // private var shadowPipelineState: MTLRenderPipelineState? // Using ShadowRenderer instead
    
    // Uniform buffer for shape data
    struct ShapeUniforms {
        var transform: matrix_float4x4
        var fillColor: SIMD4<Float>
        var strokeColor: SIMD4<Float>
        var strokeWidth: Float
        var shapeSize: SIMD2<Float>
        var time: Float
        var shapeType: Int32  // 0: rectangle, 1: ellipse, 2: polygon
        
        init() {
            self.transform = matrix_identity_float4x4
            self.fillColor = SIMD4<Float>(1, 1, 1, 1)
            self.strokeColor = SIMD4<Float>(0, 0, 0, 1)
            self.strokeWidth = 1.0
            self.shapeSize = SIMD2<Float>(100, 100)
            self.time = 0.0
            self.shapeType = 0
        }
    }
    
    // Shadow uniforms moved to ShadowRenderer
    
    struct GradientUniforms {
        var transform: matrix_float4x4
        var color0: SIMD4<Float>
        var color1: SIMD4<Float>
        var color2: SIMD4<Float>
        var color3: SIMD4<Float>
        var color4: SIMD4<Float>
        var color5: SIMD4<Float>
        var color6: SIMD4<Float>
        var color7: SIMD4<Float>
        var location0: Float
        var location1: Float
        var location2: Float
        var location3: Float
        var location4: Float
        var location5: Float
        var location6: Float
        var location7: Float
        var colorCount: Int32
        var gradientType: Int32     // 0: linear, 1: radial, 2: angular
        var startPoint: SIMD2<Float>
        var endPoint: SIMD2<Float>
        
        init() {
            self.transform = matrix_identity_float4x4
            self.color0 = SIMD4<Float>(0, 0, 0, 0)
            self.color1 = SIMD4<Float>(0, 0, 0, 0)
            self.color2 = SIMD4<Float>(0, 0, 0, 0)
            self.color3 = SIMD4<Float>(0, 0, 0, 0)
            self.color4 = SIMD4<Float>(0, 0, 0, 0)
            self.color5 = SIMD4<Float>(0, 0, 0, 0)
            self.color6 = SIMD4<Float>(0, 0, 0, 0)
            self.color7 = SIMD4<Float>(0, 0, 0, 0)
            self.location0 = 0.0
            self.location1 = 0.0
            self.location2 = 0.0
            self.location3 = 0.0
            self.location4 = 0.0
            self.location5 = 0.0
            self.location6 = 0.0
            self.location7 = 0.0
            self.colorCount = 0
            self.gradientType = 0
            self.startPoint = SIMD2<Float>(0, 0)
            self.endPoint = SIMD2<Float>(1, 1)
        }
        
        mutating func setColor(at index: Int, color: SIMD4<Float>) {
            switch index {
            case 0: color0 = color
            case 1: color1 = color
            case 2: color2 = color
            case 3: color3 = color
            case 4: color4 = color
            case 5: color5 = color
            case 6: color6 = color
            case 7: color7 = color
            default: break
            }
        }
        
        mutating func setLocation(at index: Int, location: Float) {
            switch index {
            case 0: location0 = location
            case 1: location1 = location
            case 2: location2 = location
            case 3: location3 = location
            case 4: location4 = location
            case 5: location5 = location
            case 6: location6 = location
            case 7: location7 = location
            default: break
            }
        }
    }
    
    init(device: MTLDevice) throws {
        self.device = device
        
        // Load shader library
        guard let library = device.makeDefaultLibrary() else {
            throw ShapeRendererError.failedToLoadLibrary
        }
        self.library = library
        
        // Setup pipeline states
        try setupPipelineStates()
    }
    
    private func setupPipelineStates() throws {
        // Vertex descriptor for shape vertices
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<SIMD2<Float>>.stride
        
        // Solid fill pipeline
        solidFillPipelineState = try createPipelineState(
            vertexFunction: "shapeVertex",
            fragmentFunction: "shapeSolidFill",
            vertexDescriptor: vertexDescriptor
        )
        
        // Linear gradient pipeline
        linearGradientPipelineState = try createPipelineState(
            vertexFunction: "shapeVertex",
            fragmentFunction: "shapeLinearGradient",
            vertexDescriptor: vertexDescriptor
        )
        
        // Radial gradient pipeline
        radialGradientPipelineState = try createPipelineState(
            vertexFunction: "shapeVertex",
            fragmentFunction: "shapeRadialGradient",
            vertexDescriptor: vertexDescriptor
        )
        
        // Angular gradient pipeline
        angularGradientPipelineState = try createPipelineState(
            vertexFunction: "shapeVertex",
            fragmentFunction: "shapeAngularGradient",
            vertexDescriptor: vertexDescriptor
        )
        
        // Image fill pipeline
        imageFillPipelineState = try createPipelineState(
            vertexFunction: "shapeVertex",
            fragmentFunction: "shapeImageFill",
            vertexDescriptor: vertexDescriptor
        )
        
        // Stroke pipeline
        strokePipelineState = try createPipelineState(
            vertexFunction: "shapeVertex",
            fragmentFunction: "shapeStroke",
            vertexDescriptor: vertexDescriptor
        )
        
        // Shadow pipeline - commenting out for now as we're using ShadowRenderer instead
        // shadowPipelineState = try createPipelineState(
        //     vertexFunction: "shapeShadowVertex",
        //     fragmentFunction: "shapeShadow",
        //     vertexDescriptor: vertexDescriptor
        // )
    }
    
    private func createPipelineState(
        vertexFunction: String,
        fragmentFunction: String,
        vertexDescriptor: MTLVertexDescriptor
    ) throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: vertexFunction)
        descriptor.fragmentFunction = library.makeFunction(name: fragmentFunction)
        descriptor.vertexDescriptor = vertexDescriptor
        
        // Configure for BGRA8Unorm render target
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        // Enable sample coverage for better anti-aliasing
        descriptor.isAlphaToCoverageEnabled = false
        descriptor.sampleCount = 1  // Will use texture-based AA instead of MSAA
        
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    // MARK: - Rendering
    
    func render(
        shape: VectorShapeLayer,
        to texture: MTLTexture,
        commandBuffer: MTLCommandBuffer,
        transform: matrix_float4x4
    ) {
        // Get vertex and index buffers from the shape
        guard let vertices = shape.vertexBuffer,
              let indices = shape.indexBuffer,
              shape.indexCount > 0 else {
            print("ShapeRenderer: No buffers - vb:\(shape.vertexBuffer != nil), ib:\(shape.indexBuffer != nil), count:\(shape.indexCount)")
            return
        }
        
        
        // Create render pass descriptor
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        
        // Set viewport
        renderEncoder.setViewport(MTLViewport(
            originX: 0,
            originY: 0,
            width: Double(texture.width),
            height: Double(texture.height),
            znear: -1.0,
            zfar: 1.0
        ))
        
        // Drop shadow is now handled at the canvas level by ShadowRenderer
        // if shape.dropShadow.isEnabled {
        //     renderDropShadow(
        //         shape: shape,
        //         vertices: vertices,
        //         indices: indices,
        //         transform: transform,
        //         encoder: renderEncoder
        //     )
        // }
        
        // Handle different rendering cases
        if let fillType = shape.fillType {
            // Case 1: Has fill - render stroke first, then fill on top
            if let strokeColor = shape.strokeColor, shape.strokeWidth > 0 {
                renderStroke(
                    color: strokeColor,
                    width: shape.strokeWidth,
                    shape: shape,
                    vertices: vertices,
                    indices: indices,
                    transform: transform,
                    encoder: renderEncoder
                )
            }
            
            // Render fill on top
            renderFill(
                fillType: fillType,
                shape: shape,
                vertices: vertices,
                indices: indices,
                transform: transform,
                encoder: renderEncoder
            )
        } else if let strokeColor = shape.strokeColor, shape.strokeWidth > 0 {
            // Case 2: No fill, only stroke - render stroke outline
            renderStrokeOnly(
                color: strokeColor,
                width: shape.strokeWidth,
                shape: shape,
                vertices: vertices,
                indices: indices,
                transform: transform,
                encoder: renderEncoder
            )
        }
        
        renderEncoder.endEncoding()
    }
    
    private func renderFill(
        fillType: FillType,
        shape: VectorShapeLayer,
        vertices: MTLBuffer,
        indices: MTLBuffer,
        transform: matrix_float4x4,
        encoder: MTLRenderCommandEncoder
    ) {
        switch fillType {
        case .solid(let color):
            renderSolidFill(
                color: color,
                shape: shape,
                vertices: vertices,
                indices: indices,
                transform: transform,
                encoder: encoder
            )
            
        case .gradient(let gradient):
            renderGradientFill(
                gradient: gradient,
                shape: shape,
                vertices: vertices,
                indices: indices,
                transform: transform,
                encoder: encoder
            )
            
        case .pattern(let texture):
            renderImageFill(
                texture: texture,
                shape: shape,
                vertices: vertices,
                indices: indices,
                transform: transform,
                encoder: encoder
            )
        }
    }
    
    private func renderSolidFill(
        color: CGColor,
        shape: VectorShapeLayer,
        vertices: MTLBuffer,
        indices: MTLBuffer,
        transform: matrix_float4x4,
        encoder: MTLRenderCommandEncoder
    ) {
        guard let pipelineState = solidFillPipelineState else { return }
        
        encoder.setRenderPipelineState(pipelineState)
        
        // Setup uniforms
        var uniforms = ShapeUniforms()
        uniforms.transform = transform
        uniforms.fillColor = colorToSIMD(color)
        uniforms.shapeSize = SIMD2<Float>(Float(shape.bounds.width), Float(shape.bounds.height))
        
        encoder.setVertexBuffer(vertices, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<ShapeUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShapeUniforms>.stride, index: 0)
        
        // Draw indexed triangles
        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: shape.indexCount,
            indexType: .uint16,
            indexBuffer: indices,
            indexBufferOffset: 0
        )
    }
    
    private func renderGradientFill(
        gradient: Gradient,
        shape: VectorShapeLayer,
        vertices: MTLBuffer,
        indices: MTLBuffer,
        transform: matrix_float4x4,
        encoder: MTLRenderCommandEncoder
    ) {
        let pipelineState: MTLRenderPipelineState?
        
        switch gradient.type {
        case .linear:
            pipelineState = linearGradientPipelineState
        case .radial:
            pipelineState = radialGradientPipelineState
        case .angular:
            pipelineState = angularGradientPipelineState
        }
        
        guard let pipeline = pipelineState else { return }
        
        encoder.setRenderPipelineState(pipeline)
        
        // Setup gradient uniforms
        var uniforms = GradientUniforms()
        uniforms.transform = transform
        
        // Set gradient type: 0 = linear, 1 = radial, 2 = angular
        switch gradient.type {
        case .linear:
            uniforms.gradientType = 0
        case .radial:
            uniforms.gradientType = 1
        case .angular:
            uniforms.gradientType = 2
        }
        
        uniforms.startPoint = SIMD2<Float>(Float(gradient.startPoint.x), Float(gradient.startPoint.y))
        uniforms.endPoint = SIMD2<Float>(Float(gradient.endPoint.x), Float(gradient.endPoint.y))
        uniforms.colorCount = Int32(min(gradient.colorStops.count, 8))
        
        // Copy color stops
        for (index, stop) in gradient.colorStops.prefix(8).enumerated() {
            uniforms.setColor(at: index, color: colorToSIMD(stop.color))
            uniforms.setLocation(at: index, location: stop.location)
        }
        
        var shapeSize = SIMD2<Float>(Float(shape.bounds.width), Float(shape.bounds.height))
        
        encoder.setVertexBuffer(vertices, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<GradientUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GradientUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&shapeSize, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
        
        // Draw indexed triangles
        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: shape.indexCount,
            indexType: .uint16,
            indexBuffer: indices,
            indexBufferOffset: 0
        )
    }
    
    private func renderImageFill(
        texture: MTLTexture,
        shape: VectorShapeLayer,
        vertices: MTLBuffer,
        indices: MTLBuffer,
        transform: matrix_float4x4,
        encoder: MTLRenderCommandEncoder
    ) {
        guard let pipelineState = imageFillPipelineState else { return }
        
        encoder.setRenderPipelineState(pipelineState)
        
        // Setup uniforms
        var uniforms = ShapeUniforms()
        uniforms.transform = transform
        uniforms.shapeSize = SIMD2<Float>(Float(shape.bounds.width), Float(shape.bounds.height))
        
        encoder.setVertexBuffer(vertices, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<ShapeUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShapeUniforms>.stride, index: 0)
        
        // Set the image texture and sampler
        encoder.setFragmentTexture(texture, index: 0)
        
        // Create a sampler for the texture
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        
        if let sampler = device.makeSamplerState(descriptor: samplerDescriptor) {
            encoder.setFragmentSamplerState(sampler, index: 0)
        }
        
        // Draw indexed triangles
        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: shape.indexCount,
            indexType: .uint16,
            indexBuffer: indices,
            indexBufferOffset: 0
        )
    }
    
    private func renderStroke(
        color: CGColor,
        width: Float,
        shape: VectorShapeLayer,
        vertices: MTLBuffer,
        indices: MTLBuffer,
        transform: matrix_float4x4,
        encoder: MTLRenderCommandEncoder
    ) {
        guard let pipelineState = solidFillPipelineState else { return }
        
        encoder.setRenderPipelineState(pipelineState)
        
        // Create a slightly scaled up transform for the stroke
        var strokeTransform = transform
        
        // Calculate stroke scale factor based on the original bounds (not padded)
        let strokeScale = 1.0 + (width / min(Float(shape.bounds.width), Float(shape.bounds.height)))
        
        // Apply additional scale to the transform
        strokeTransform.columns.0 *= strokeScale
        strokeTransform.columns.1 *= strokeScale
        
        // Setup uniforms with stroke color
        var uniforms = ShapeUniforms()
        uniforms.transform = strokeTransform
        uniforms.fillColor = colorToSIMD(color)
        uniforms.shapeSize = SIMD2<Float>(Float(shape.bounds.width), Float(shape.bounds.height))
        
        encoder.setVertexBuffer(vertices, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<ShapeUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShapeUniforms>.stride, index: 0)
        
        // Draw the stroke shape
        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: shape.indexCount,
            indexType: .uint16,
            indexBuffer: indices,
            indexBufferOffset: 0
        )
    }
    
    private func renderStrokeOnly(
        color: CGColor,
        width: Float,
        shape: VectorShapeLayer,
        vertices: MTLBuffer,
        indices: MTLBuffer,
        transform: matrix_float4x4,
        encoder: MTLRenderCommandEncoder
    ) {
        guard let pipelineState = strokePipelineState else { return }
        
        encoder.setRenderPipelineState(pipelineState)
        
        // Setup uniforms for stroke-only rendering
        var uniforms = ShapeUniforms()
        uniforms.transform = transform
        uniforms.strokeColor = colorToSIMD(color)
        uniforms.strokeWidth = width
        uniforms.shapeSize = SIMD2<Float>(Float(shape.bounds.width), Float(shape.bounds.height))
        
        // Determine shape type based on layer name
        if shape.name.contains("Rectangle") || shape.name.contains("Square") {
            uniforms.shapeType = 0  // Rectangle
        } else if shape.name.contains("Ellipse") || shape.name.contains("Circle") {
            uniforms.shapeType = 1  // Ellipse
        } else {
            uniforms.shapeType = 2  // Polygon
        }
        
        encoder.setVertexBuffer(vertices, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<ShapeUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShapeUniforms>.stride, index: 0)
        
        // Draw the stroke outline
        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: shape.indexCount,
            indexType: .uint16,
            indexBuffer: indices,
            indexBufferOffset: 0
        )
    }
    
    // MARK: - Buffer Creation
    
    // Removed - now using buffers from VectorShapeLayer directly
    
    // MARK: - Utilities
    
    private func colorToSIMD(_ color: CGColor) -> SIMD4<Float> {
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
            // Grayscale
            let gray = Float(components[0])
            let alpha = components.count >= 2 ? Float(components[1]) : 1.0
            return SIMD4<Float>(gray, gray, gray, alpha)
        }
        
        return SIMD4<Float>(0, 0, 0, 1)
    }
    
    // MARK: - Drop Shadow Rendering
    
    // Drop shadow is now handled at the canvas level by ShadowRenderer
    // private func renderDropShadow(
    //     shape: VectorShapeLayer,
    //     vertices: MTLBuffer,
    //     indices: MTLBuffer,
    //     transform: matrix_float4x4,
    //     encoder: MTLRenderCommandEncoder
    // ) {
    //     guard let shadowPipelineState = shadowPipelineState else {
    //         print("ShapeRenderer: Shadow pipeline state not available")
    //         return
    //     }
    //     
    //     // Set pipeline state
    //     encoder.setRenderPipelineState(shadowPipelineState)
    //     
    //     // Set vertex buffer
    //     encoder.setVertexBuffer(vertices, offset: 0, index: 0)
    //     
    //     // Create shadow uniforms
    //     var shadowUniforms = ShadowUniforms()
    //     shadowUniforms.transform = transform
    //     shadowUniforms.shadowColor = colorToSIMD(shape.dropShadow.color)
    //     shadowUniforms.shadowOffset = SIMD2<Float>(
    //         Float(shape.dropShadow.offset.width),
    //         Float(shape.dropShadow.offset.height)
    //     )
    //     shadowUniforms.shadowBlur = Float(shape.dropShadow.blur)
    //     shadowUniforms.shadowOpacity = shape.dropShadow.opacity
    //     shadowUniforms.shapeSize = SIMD2<Float>(
    //         Float(shape.bounds.width),
    //         Float(shape.bounds.height)
    //     )
    //     
    //     // Determine shape type
    //     if shape.name.lowercased().contains("rectangle") {
    //         shadowUniforms.shapeType = 0
    //     } else if shape.name.lowercased().contains("circle") || shape.name.lowercased().contains("ellipse") {
    //         shadowUniforms.shapeType = 1
    //     } else {
    //         shadowUniforms.shapeType = 2 // polygon
    //     }
    //     
    //     // Set uniforms
    //     encoder.setVertexBytes(&shadowUniforms, length: MemoryLayout<ShadowUniforms>.size, index: 0)
    //     encoder.setFragmentBytes(&shadowUniforms, length: MemoryLayout<ShadowUniforms>.size, index: 0)
    //     
    //     // Draw indexed primitives
    //     encoder.drawIndexedPrimitives(
    //         type: .triangle,
    //         indexCount: shape.indexCount,
    //         indexType: .uint16,
    //         indexBuffer: indices,
    //         indexBufferOffset: 0
    //     )
    // }
}

enum ShapeRendererError: Error {
    case failedToLoadLibrary
    case failedToCreatePipelineState
}