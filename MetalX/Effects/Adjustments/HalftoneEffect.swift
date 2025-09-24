import Foundation
import Metal
import simd

class HalftoneEffect: BaseEffect {
    @Published var dotSize: Float = 8.0 {
        didSet { onUpdate?() }
    }
    @Published var angle: Float = 45.0 {
        didSet { onUpdate?() }
    }
    @Published var sharpness: Float = 0.8 {
        didSet { onUpdate?() }
    }
    
    private var pipelineState: MTLComputePipelineState?
    
    init() {
        super.init(name: "Halftone")
    }
    
    override func apply(to texture: MTLTexture, commandBuffer: MTLCommandBuffer, device: MTLDevice) -> MTLTexture? {
        guard isEnabled else { return texture }
        
        // Create pipeline state if needed
        if pipelineState == nil {
            guard let library = device.mxMakeDefaultLibrary(),
                  let function = library.makeFunction(name: "halftoneEffect") else {
                print("Failed to create halftone function")
                return texture
            }
            
            do {
                pipelineState = try device.makeComputePipelineState(function: function)
            } catch {
                print("Failed to create halftone pipeline state: \(error)")
                return texture
            }
        }
        
        guard let pipelineState = pipelineState else { return texture }
        
        // Create output texture
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: texture.pixelFormat,
            width: texture.width,
            height: texture.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        
        guard let outputTexture = device.makeTexture(descriptor: descriptor) else {
            return texture
        }
        
        // Create compute encoder
        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            return texture
        }
        
        computeEncoder.setComputePipelineState(pipelineState)
        computeEncoder.setTexture(texture, index: 0)
        computeEncoder.setTexture(outputTexture, index: 1)
        
        // Set parameters
        let angleRad = angle * Float.pi / 180.0
        var params = simd_float4(dotSize, angleRad, sharpness, intensity)
        var dimensions = simd_float2(Float(texture.width), Float(texture.height))
        
        computeEncoder.setBytes(&params, length: MemoryLayout<simd_float4>.size, index: 0)
        computeEncoder.setBytes(&dimensions, length: MemoryLayout<simd_float2>.size, index: 1)
        
        // Dispatch
        let threadsPerGroup = MTLSize(width: 16, height: 16, depth: 1)
        let groupsPerGrid = MTLSize(
            width: (texture.width + threadsPerGroup.width - 1) / threadsPerGroup.width,
            height: (texture.height + threadsPerGroup.height - 1) / threadsPerGroup.height,
            depth: 1
        )
        
        computeEncoder.dispatchThreadgroups(groupsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        computeEncoder.endEncoding()
        
        return outputTexture
    }
}
