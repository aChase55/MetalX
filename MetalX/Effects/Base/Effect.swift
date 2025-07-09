import Foundation
import Metal

// Base effect implementation
class BaseEffect: Effect {
    let id = UUID()
    var name: String
    var enabled: Bool = true
    var intensity: Float = 1.0
    
    // Cached resources
    var pipelineState: MTLRenderPipelineState?
    weak var device: MTLDevice?
    
    init(name: String, device: MTLDevice) {
        self.name = name
        self.device = device
        setupPipeline()
    }
    
    // Override in subclasses to setup specific pipeline
    func setupPipeline() {
        // Subclasses implement this
    }
    
    func apply(to texture: MTLTexture, context: RenderContext) -> MTLTexture? {
        guard enabled else { return texture }
        
        // Subclasses implement the actual effect
        return texture
    }
    
    func requiredTexturePasses() -> Int {
        // Most effects need just one pass
        return 1
    }
}

// Effect chain for managing multiple effects
class EffectChain {
    private var effects: [Effect] = []
    private var texturePool: TexturePool
    
    init(device: MTLDevice) {
        guard let metalDevice = device as? MetalDevice else {
            // Create a wrapper if needed
            do {
                let wrapper = try MetalDevice(preferredDevice: device)
                self.texturePool = TexturePool(device: wrapper)
            } catch {
                // Fallback - create with default device
                if let defaultDevice = try? MetalDevice() {
                    self.texturePool = TexturePool(device: defaultDevice)
                } else {
                    // This should not happen in practice
                    fatalError("Failed to create MetalDevice")
                }
            }
            return
        }
        self.texturePool = TexturePool(device: metalDevice)
    }
    
    func addEffect(_ effect: Effect) {
        effects.append(effect)
    }
    
    func removeEffect(_ effect: Effect) {
        effects.removeAll { $0.id == effect.id }
    }
    
    func apply(to inputTexture: MTLTexture, context: RenderContext) -> MTLTexture? {
        guard !effects.isEmpty else { return inputTexture }
        
        var currentTexture = inputTexture
        
        for (index, effect) in effects.enumerated() {
            guard effect.enabled else { continue }
            
            // Get temporary texture for intermediate results
            let isLastEffect = index == effects.count - 1
            let outputTexture: MTLTexture?
            
            if isLastEffect {
                // Last effect can write to final output
                outputTexture = effect.apply(to: currentTexture, context: context)
            } else {
                // Need intermediate texture
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: currentTexture.pixelFormat,
                    width: currentTexture.width,
                    height: currentTexture.height,
                    mipmapped: false
                )
                descriptor.usage = [.renderTarget, .shaderRead]
                
                if let tempTexture = try? texturePool.acquireTexture(descriptor: descriptor) {
                    outputTexture = effect.apply(to: currentTexture, context: context)
                    
                    // Return previous temp texture to pool
                    if currentTexture !== inputTexture {
                        texturePool.returnTexture(currentTexture)
                    }
                } else {
                    outputTexture = nil
                }
            }
            
            if let output = outputTexture {
                currentTexture = output
            }
        }
        
        return currentTexture
    }
}