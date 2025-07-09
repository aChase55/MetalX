import Metal
import MetalKit

// SIMPLE VERSION - Just render a textured quad
class QuadRenderer {
    let device: MTLDevice
    var pipelineState: MTLRenderPipelineState?
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
    }
    
    func setupBuffers() {
        // Simple quad vertices
        let vertices: [Float] = [
            -1.0, -1.0, 0.0, 1.0,  // bottom left
             1.0, -1.0, 1.0, 1.0,  // bottom right
             1.0,  1.0, 1.0, 0.0,  // top right
            -1.0,  1.0, 0.0, 0.0   // top left
        ]
        
        let indices: [UInt16] = [0, 1, 2, 2, 3, 0]
        
        vertexBuffer = device.makeBuffer(bytes: vertices,
                                         length: vertices.count * MemoryLayout<Float>.size,
                                         options: [])
        
        indexBuffer = device.makeBuffer(bytes: indices,
                                        length: indices.count * MemoryLayout<UInt16>.size,
                                        options: [])
    }
    
    func render(encoder: MTLRenderCommandEncoder, texture: MTLTexture) {
        encoder.setRenderPipelineState(pipelineState!)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        
        // Simple nearest neighbor sampling for now
        let sampler = MTLSamplerDescriptor()
        sampler.minFilter = .nearest
        sampler.magFilter = .nearest
        let samplerState = device.makeSamplerState(descriptor: sampler)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        
        encoder.drawIndexedPrimitives(type: .triangle,
                                      indexCount: 6,
                                      indexType: .uint16,
                                      indexBuffer: indexBuffer!,
                                      indexBufferOffset: 0)
    }
}