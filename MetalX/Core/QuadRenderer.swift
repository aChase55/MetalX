import Metal
import MetalKit
import simd

// SIMPLE VERSION - Just render a textured quad
class QuadRenderer {
    let device: MTLDevice
    var pipelineState: MTLRenderPipelineState?
    var selectionPipelineState: MTLRenderPipelineState?
    var vertexBuffer: MTLBuffer?
    var indexBuffer: MTLBuffer?
    
    init(device: MTLDevice) {
        self.device = device
        setupPipeline()
        setupBuffers()
    }
    
    func setupPipeline() {
        // SIMPLE - No error handling yet, just crash if it fails
        let library = device.makeDefaultLibrary()!
        let vertexFunction = library.makeFunction(name: "simpleVertex")!
        let fragmentFunction = library.makeFunction(name: "simpleFragment")!
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        // Enable alpha blending for transparency
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        // Setup vertex descriptor
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
        
        pipelineState = try! device.makeRenderPipelineState(descriptor: descriptor)
        
        // Setup selection pipeline
        if let selectionVertex = library.makeFunction(name: "selectionVertex"),
           let selectionFragment = library.makeFunction(name: "selectionFragment") {
            let selectionDescriptor = MTLRenderPipelineDescriptor()
            selectionDescriptor.vertexFunction = selectionVertex
            selectionDescriptor.fragmentFunction = selectionFragment
            selectionDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            
            // Enable alpha blending for the outline
            selectionDescriptor.colorAttachments[0].isBlendingEnabled = true
            selectionDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            selectionDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            selectionDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            selectionDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            
            // Selection uses same vertex format as main shader
            selectionDescriptor.vertexDescriptor = vertexDescriptor
            
            selectionPipelineState = try? device.makeRenderPipelineState(descriptor: selectionDescriptor)
        }
    }
    
    func setupBuffers() {
        // Simple quad vertices (fixed texture coordinates)
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
    
    func render(encoder: MTLRenderCommandEncoder, texture: MTLTexture, transform: simd_float4x4 = matrix_identity_float4x4) {
        encoder.setRenderPipelineState(pipelineState!)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        
        // Pass transform matrix as uniform
        var uniforms = transform
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<simd_float4x4>.size, index: 1)
        
        encoder.setFragmentTexture(texture, index: 0)
        
        // Use linear filtering with mipmapping for better quality
        let sampler = MTLSamplerDescriptor()
        sampler.minFilter = .linear
        sampler.magFilter = .linear
        sampler.mipFilter = .linear  // Enable mipmap filtering
        let samplerState = device.makeSamplerState(descriptor: sampler)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        
        encoder.drawIndexedPrimitives(type: .triangle,
                                      indexCount: 6,
                                      indexType: .uint16,
                                      indexBuffer: indexBuffer!,
                                      indexBufferOffset: 0)
    }
    
    func renderSelection(encoder: MTLRenderCommandEncoder, transform: simd_float4x4, viewportSize: CGSize, time: Float) {
        guard let selectionPipelineState = selectionPipelineState else { return }
        
        encoder.setRenderPipelineState(selectionPipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)  // Use same vertex buffer
        
        // Pass uniforms
        struct SelectionUniforms {
            var transform: simd_float4x4
            var viewportSize: simd_float2
            var time: Float
            var padding: Float = 0
        }
        
        var uniforms = SelectionUniforms(
            transform: transform,
            viewportSize: simd_float2(Float(viewportSize.width), Float(viewportSize.height)),
            time: time
        )
        
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<SelectionUniforms>.size, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SelectionUniforms>.size, index: 0)
        
        // Draw as triangles for selection quad
        encoder.drawIndexedPrimitives(type: .triangle,
                                      indexCount: 6,
                                      indexType: .uint16,
                                      indexBuffer: indexBuffer!,
                                      indexBufferOffset: 0)
    }
}