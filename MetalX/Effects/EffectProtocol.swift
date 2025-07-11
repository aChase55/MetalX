import Foundation
import Metal
import CoreGraphics

// MARK: - Effect Protocol

protocol Effect: AnyObject {
    var id: UUID { get }
    var name: String { get }
    var isEnabled: Bool { get set }
    var intensity: Float { get set }
    
    func apply(to texture: MTLTexture, commandBuffer: MTLCommandBuffer, device: MTLDevice) -> MTLTexture?
}

// MARK: - Base Effect Class

class BaseEffect: Effect, ObservableObject {
    let id = UUID()
    var name: String
    @Published var isEnabled: Bool = true {
        didSet { onUpdate?() }
    }
    @Published var intensity: Float = 1.0 {
        didSet { onUpdate?() }
    }
    
    var onUpdate: (() -> Void)?
    
    init(name: String) {
        self.name = name
    }
    
    func apply(to texture: MTLTexture, commandBuffer: MTLCommandBuffer, device: MTLDevice) -> MTLTexture? {
        // To be overridden by subclasses
        return texture
    }
}

// MARK: - Effect Target

enum EffectTarget {
    case layer
    case canvas
}

// MARK: - Effect Stack

class EffectStack: ObservableObject {
    @Published var effects: [Effect] = []
    var onUpdate: (() -> Void)?
    
    func addEffect(_ effect: Effect) {
        effects.append(effect)
        if let baseEffect = effect as? BaseEffect {
            baseEffect.onUpdate = { [weak self] in
                self?.onUpdate?()
            }
        }
        onUpdate?()
    }
    
    func removeEffect(_ effect: Effect) {
        effects.removeAll { $0.id == effect.id }
        onUpdate?()
    }
    
    func moveEffect(from source: IndexSet, to destination: Int) {
        effects.move(fromOffsets: source, toOffset: destination)
        onUpdate?()
    }
    
    func applyEffects(to texture: MTLTexture, commandBuffer: MTLCommandBuffer, device: MTLDevice) -> MTLTexture? {
        var currentTexture = texture
        
        for effect in effects where effect.isEnabled {
            if let resultTexture = effect.apply(to: currentTexture, commandBuffer: commandBuffer, device: device) {
                currentTexture = resultTexture
            }
        }
        
        return currentTexture
    }
}