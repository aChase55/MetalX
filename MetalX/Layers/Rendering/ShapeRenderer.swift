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
    private var strokePipelineState: MTLRenderPipelineState?
    
    // Uniform buffer for shape data
    struct ShapeUniforms {
        var transform: matrix_float4x4
        var fillColor: SIMD4<Float>
        var strokeColor: SIMD4<Float>
        var strokeWidth: Float
        var shapeSize: SIMD2<Float>
        var time: Float
        
        init() {
            self.transform = matrix_identity_float4x4
            self.fillColor = SIMD4<Float>(1, 1, 1, 1)
            self.strokeColor = SIMD4<Float>(0, 0, 0, 1)
            self.strokeWidth = 1.0
            self.shapeSize = SIMD2<Float>(100, 100)
            self.time = 0.0
        }
    }
    
    struct GradientUniforms {
        var transform: matrix_float4x4
        var colors: [SIMD4<Float>] // Up to 8 color stops
        var locations: [Float]      // Color stop locations
        var colorCount: Int32
        var gradientType: Int32     // 0: linear, 1: radial, 2: angular
        var startPoint: SIMD2<Float>
        var endPoint: SIMD2<Float>
        var padding: SIMD2<Float>   // Padding to align to 16 bytes
        
        init() {
            self.transform = matrix_identity_float4x4
            self.colors = Array(repeating: SIMD4<Float>(0, 0, 0, 0), count: 8)
            self.locations = Array(repeating: 0.0, count: 8)
            self.colorCount = 0
            self.gradientType = 0
            self.startPoint = SIMD2<Float>(0, 0)
            self.endPoint = SIMD2<Float>(1, 1)
            self.padding = SIMD2<Float>(0, 0)
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
        
        // Stroke pipeline
        strokePipelineState = try createPipelineState(
            vertexFunction: "shapeVertex",
            fragmentFunction: "shapeStroke",
            vertexDescriptor: vertexDescriptor
        )
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
        
        print("ShapeRenderer: Rendering shape with \(shape.indexCount) indices (\(shape.indexCount/3) triangles)")
        print("Transform matrix:")
        print("  [\(transform.columns.0.x), \(transform.columns.1.x), \(transform.columns.2.x), \(transform.columns.3.x)]")
        print("  [\(transform.columns.0.y), \(transform.columns.1.y), \(transform.columns.2.y), \(transform.columns.3.y)]")
        
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
        
        // Render fill
        if let fillType = shape.fillType {
            renderFill(
                fillType: fillType,
                shape: shape,
                vertices: vertices,
                indices: indices,
                transform: transform,
                encoder: renderEncoder
            )
        }
        
        // Render stroke
        if let strokeColor = shape.strokeColor, shape.strokeWidth > 0 {
            renderStroke(
                color: strokeColor,
                width: shape.strokeWidth,
                shape: shape,
                vertices: vertices,
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
            // TODO: Implement pattern fill
            break
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
            // TODO: Implement angular gradient
            return
        }
        
        guard let pipeline = pipelineState else { return }
        
        encoder.setRenderPipelineState(pipeline)
        
        // Setup gradient uniforms
        var uniforms = GradientUniforms()
        uniforms.transform = transform
        uniforms.gradientType = gradient.type == .linear ? 0 : 1
        uniforms.startPoint = SIMD2<Float>(Float(gradient.startPoint.x), Float(gradient.startPoint.y))
        uniforms.endPoint = SIMD2<Float>(Float(gradient.endPoint.x), Float(gradient.endPoint.y))
        uniforms.colorCount = Int32(min(gradient.colorStops.count, 8))
        
        // Copy color stops
        for (index, stop) in gradient.colorStops.prefix(8).enumerated() {
            uniforms.colors[index] = colorToSIMD(stop.color)
            uniforms.locations[index] = stop.location
        }
        
        var shapeSize = SIMD2<Float>(Float(shape.bounds.width), Float(shape.bounds.height))
        
        encoder.setVertexBuffer(vertices, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<ShapeUniforms>.stride, index: 1)
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
    
    private func renderStroke(
        color: CGColor,
        width: Float,
        shape: VectorShapeLayer,
        vertices: MTLBuffer,
        transform: matrix_float4x4,
        encoder: MTLRenderCommandEncoder
    ) {
        // TODO: Implement proper stroke rendering
        // This would require generating stroke geometry from the path
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
}

enum ShapeRendererError: Error {
    case failedToLoadLibrary
    case failedToCreatePipelineState
}