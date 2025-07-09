import Foundation
import Metal
import CoreGraphics

// MARK: - Effect Support

protocol EffectableLayer: Layer {
    var effects: [Effect] { get set }
    func applyEffects(to texture: MTLTexture, context: RenderContext) -> MTLTexture?
}

// MARK: - Shape Support

enum FillType {
    case solid(CGColor)
    case gradient(Gradient)
    case pattern(MTLTexture)
}

struct Gradient {
    enum GradientType {
        case linear
        case radial
        case angular
    }
    
    struct ColorStop {
        let color: CGColor
        let location: Float
    }
    
    let type: GradientType
    let colorStops: [ColorStop]
    let startPoint: CGPoint
    let endPoint: CGPoint
}

protocol ShapeLayer: Layer {
    var path: CGPath { get set }
    var fillType: FillType? { get set }
    var strokeColor: CGColor? { get set }
    var strokeWidth: Float { get set }
    var lineCap: CGLineCap { get set }
    var lineJoin: CGLineJoin { get set }
}

// MARK: - Mask Support

enum MaskMode {
    case alpha
    case luminance
    case inverseAlpha
    case inverseLuminance
}

protocol MaskableLayer: Layer {
    var mask: Layer? { get set }
    var maskMode: MaskMode { get set }
}

// MARK: - Group Support

protocol GroupLayer: Layer {
    var children: [Layer] { get set }
    var clipsToChildren: Bool { get set }
    var renderAsGroup: Bool { get set }
    
    func addChild(_ layer: Layer)
    func removeChild(_ layer: Layer)
    func reorderChild(_ layer: Layer, to index: Int)
}

// MARK: - Effect Protocol

protocol Effect: AnyObject {
    var id: UUID { get }
    var name: String { get }
    var enabled: Bool { get set }
    var intensity: Float { get set }
    
    func apply(to texture: MTLTexture, context: RenderContext) -> MTLTexture?
    func requiredTexturePasses() -> Int
}

// MARK: - Extended Layer Protocol

protocol ExtendedLayer: Layer, EffectableLayer, MaskableLayer {
    // Combines all advanced layer features
}