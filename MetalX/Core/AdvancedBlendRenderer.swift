import Metal
import MetalKit

/// Handles rendering with advanced blend modes that require destination texture
class AdvancedBlendRenderer {
    private let device: MTLDevice
    private var pipelineStates: [BlendMode: MTLRenderPipelineState] = [:]
    private let vertexBuffer: MTLBuffer?
    private let indexBuffer: MTLBuffer?
    
    init(device: MTLDevice) {
        self.device = device
        
        // Create vertex buffer for a quad
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
        
        setupPipelines()
    }
    
    private func setupPipelines() {
        guard let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: "blendVertex"),
              let blendFunction = library.makeFunction(name: "advancedBlendFragment") else { return }
        
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
        
        // Create pipeline state for advanced blending
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = blendFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.vertexDescriptor = vertexDescriptor
        
        // No blending in the pipeline - we handle it in the shader
        descriptor.colorAttachments[0].isBlendingEnabled = false
        
        // Create a single pipeline that handles all blend modes via uniforms
        if let pipelineState = try? device.makeRenderPipelineState(descriptor: descriptor) {
            // Store for all advanced blend modes
            for mode in [BlendMode.overlay, .softLight, .hardLight, .colorDodge, .colorBurn,
                         .darken, .lighten, .difference, .exclusion] {
                pipelineStates[mode] = pipelineState
            }
        }
    }
    
    func canRender(blendMode: BlendMode) -> Bool {
        return pipelineStates[blendMode] != nil
    }
    
    func render(
        encoder: MTLRenderCommandEncoder,
        sourceTexture: MTLTexture,
        destinationTexture: MTLTexture,
        transform: simd_float4x4,
        opacity: Float,
        blendMode: BlendMode
    ) {
        guard let pipelineState = pipelineStates[blendMode] else { return }
        
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        
        // Pass transform
        var uniforms = transform
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<simd_float4x4>.size, index: 1)
        
        // Pass blend uniforms
        struct BlendUniforms {
            var opacity: Float
            var blendMode: Int32
            var padding: simd_float2 = simd_float2(0, 0)
        }
        
        var blendUniforms = BlendUniforms(
            opacity: opacity,
            blendMode: blendModeToInt(blendMode)
        )
        encoder.setFragmentBytes(&blendUniforms, length: MemoryLayout<BlendUniforms>.size, index: 0)
        
        // Set textures
        encoder.setFragmentTexture(sourceTexture, index: 0)
        encoder.setFragmentTexture(destinationTexture, index: 1)
        
        // Set sampler
        let sampler = MTLSamplerDescriptor()
        sampler.minFilter = .linear
        sampler.magFilter = .linear
        sampler.mipFilter = .notMipmapped
        sampler.sAddressMode = .clampToEdge
        sampler.tAddressMode = .clampToEdge
        if let samplerState = device.makeSamplerState(descriptor: sampler) {
            encoder.setFragmentSamplerState(samplerState, index: 0)
        }
        
        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: 6,
            indexType: .uint16,
            indexBuffer: indexBuffer!,
            indexBufferOffset: 0
        )
    }
    
    private func blendModeToInt(_ mode: BlendMode) -> Int32 {
        switch mode {
        case .overlay: return 0
        case .softLight: return 1
        case .hardLight: return 2
        case .colorDodge: return 3
        case .colorBurn: return 4
        case .darken: return 5
        case .lighten: return 6
        case .difference: return 7
        case .exclusion: return 8
        default: return 0
        }
    }
}