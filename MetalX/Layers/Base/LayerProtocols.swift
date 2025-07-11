import Foundation
import Metal
import CoreGraphics

// MARK: - Effect Support

protocol EffectableLayer: Layer {
    var effectStack: EffectStack { get set }
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
    var mask: (any Layer)? { get set }
    var maskMode: MaskMode { get set }
}

// MARK: - Group Support

protocol GroupLayer: AnyObject, Layer {
    var children: [any Layer] { get set }
    var clipsToChildren: Bool { get set }
    var renderAsGroup: Bool { get set }
    
    func addChild(_ layer: any Layer)
    func removeChild(_ layer: any Layer)
    func reorderChild(_ layer: any Layer, to index: Int)
}

// MARK: - Extended Layer Protocol

protocol ExtendedLayer: Layer, EffectableLayer, MaskableLayer {
    // Combines all advanced layer features
}