import Foundation
import Metal
import simd

class VHSEffect: ObservableObject, Effect {
    let id = UUID()
    let name = "VHS"
    @Published var isEnabled: Bool = true
    @Published var intensity: Float = 1.0
    @Published var lineIntensity: Float = 0.5
    @Published var noiseIntensity: Float = 0.3
    @Published var colorBleed: Float = 0.2
    @Published var distortion: Float = 0.1
    
    private var pipelineState: MTLComputePipelineState?
    
    func apply(to texture: MTLTexture, commandBuffer: MTLCommandBuffer, device: MTLDevice) -> MTLTexture? {
        guard isEnabled else { return texture }
        
        // Create pipeline state if needed
        if pipelineState == nil {
            guard let library = device.makeDefaultLibrary(),
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
        
        // Set parameters - pack into two float4s
        var params1 = simd_float4(lineIntensity * intensity, noiseIntensity * intensity, colorBleed * intensity, distortion * intensity)
        var params2 = simd_float4(Float(texture.width), Float(texture.height), Float.random(in: 0...1000), 0)
        
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