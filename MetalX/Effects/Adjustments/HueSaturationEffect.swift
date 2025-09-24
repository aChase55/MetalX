import Foundation
import Metal
import MetalKit
import Combine

class HueSaturationEffect: BaseEffect {
    @Published var hueShift: Float = 0.0 {     // -180 to 180 degrees
        didSet { onUpdate?() }
    }
    @Published var saturation: Float = 1.0 {   // 0 to 2
        didSet { onUpdate?() }
    }
    @Published var lightness: Float = 0.0 {    // -1 to 1 (using as brightness)
        didSet { onUpdate?() }
    }
    
    private var pipelineState: MTLComputePipelineState?
    
    init() {
        super.init(name: "Hue/Saturation")
    }
    
    override func apply(to texture: MTLTexture, commandBuffer: MTLCommandBuffer, device: MTLDevice) -> MTLTexture? {
        // Create pipeline state if needed
        if pipelineState == nil {
            guard let library = device.mxMakeDefaultLibrary(),
                  let function = library.makeFunction(name: "hueSaturationBrightness"),
                  let pipeline = try? device.makeComputePipelineState(function: function) else {
                return nil
            }
            pipelineState = pipeline
        }
        
        // Create output texture
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: texture.pixelFormat,
            width: texture.width,
            height: texture.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = texture.storageMode
        
        guard let outputTexture = device.makeTexture(descriptor: descriptor),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            return nil
        }
        
        computeEncoder.setComputePipelineState(pipelineState!)
        computeEncoder.setTexture(texture, index: 0)
        computeEncoder.setTexture(outputTexture, index: 1)
        
        // Set parameters with intensity applied
        var hueValue = hueShift * intensity
        var saturationValue = mix(1.0, saturation, intensity)
        var brightnessValue = lightness * intensity
        
        computeEncoder.setBytes(&hueValue, length: MemoryLayout<Float>.size, index: 0)
        computeEncoder.setBytes(&saturationValue, length: MemoryLayout<Float>.size, index: 1)
        computeEncoder.setBytes(&brightnessValue, length: MemoryLayout<Float>.size, index: 2)
        
        // Dispatch threads
        let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroupCount = MTLSize(
            width: (texture.width + threadgroupSize.width - 1) / threadgroupSize.width,
            height: (texture.height + threadgroupSize.height - 1) / threadgroupSize.height,
            depth: 1
        )
        
        computeEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
        computeEncoder.endEncoding()
        
        return outputTexture
    }
}

private func mix(_ a: Float, _ b: Float, _ t: Float) -> Float {
    return a + (b - a) * t
}
