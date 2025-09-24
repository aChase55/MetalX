import Foundation
import Metal
import simd

class VHSEffect: BaseEffect {
    @Published var lineIntensity: Float = 0.5 {
        didSet { onUpdate?() }
    }
    @Published var noiseIntensity: Float = 0.3 {
        didSet { onUpdate?() }
    }
    @Published var colorBleed: Float = 0.2 {
        didSet { onUpdate?() }
    }
    @Published var distortion: Float = 0.1 {
        didSet { onUpdate?() }
    }
    
    private var pipelineState: MTLComputePipelineState?
    private var timeOffset: Float = 0.0
    
    init() {
        super.init(name: "VHS")
    }
    
    override func apply(to texture: MTLTexture, commandBuffer: MTLCommandBuffer, device: MTLDevice) -> MTLTexture? {
        guard isEnabled else { return texture }
        
        // Create pipeline state if needed
        if pipelineState == nil {
            guard let library = device.mxMakeDefaultLibrary(),
                  let function = library.makeFunction(name: "vhsEffect") else {
                print("Failed to create VHS function")
                return texture
            }
            
            do {
                pipelineState = try device.makeComputePipelineState(function: function)
            } catch {
                print("Failed to create VHS pipeline state: \(error)")
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
        
        // Update time offset to ensure re-rendering on parameter changes
        timeOffset += 0.1
        
        // Set parameters - pack into two float4s
        var params1 = simd_float4(lineIntensity * intensity, noiseIntensity * intensity, colorBleed * intensity, distortion * intensity)
        var params2 = simd_float4(Float(texture.width), Float(texture.height), timeOffset, 0)
        
        computeEncoder.setBytes(&params1, length: MemoryLayout<simd_float4>.size, index: 0)
        computeEncoder.setBytes(&params2, length: MemoryLayout<simd_float4>.size, index: 1)
        
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
