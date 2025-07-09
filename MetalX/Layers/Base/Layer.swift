import Foundation
import CoreGraphics
import Metal
import simd

// Layer-specific transform structure
struct LayerTransform {
    var position: CGPoint = .zero
    var scale: CGFloat = 1.0
    var rotation: CGFloat = 0.0
    
    // Convert to matrix for Metal shader
    var matrix: float4x4 {
        var result = matrix_identity_float4x4
        
        // Apply translation
        result.columns.3.x = Float(position.x)
        result.columns.3.y = Float(position.y)
        
        // Apply rotation
        let c = cos(Float(rotation))
        let s = sin(Float(rotation))
        let rotMatrix = float4x4(
            SIMD4<Float>(c, s, 0, 0),
            SIMD4<Float>(-s, c, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
        
        // Apply scale
        let scaleMatrix = float4x4(
            SIMD4<Float>(Float(scale), 0, 0, 0),
            SIMD4<Float>(0, Float(scale), 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
        
        return result * rotMatrix * scaleMatrix
    }
}

// Base layer protocol
protocol Layer: AnyObject {
    var id: UUID { get }
    var name: String { get set }
    var visible: Bool { get set }
    var locked: Bool { get set }
    var opacity: Float { get set }
    var blendMode: BlendMode { get set }
    var transform: LayerTransform { get set }
    var bounds: CGRect { get }
    var zIndex: Int { get set }
    
    // Rendering
    func render(context: RenderContext) -> MTLTexture?
    func getBounds(includeEffects: Bool) -> CGRect
    func hitTest(point: CGPoint) -> Bool
}

// Base implementation
class BaseLayer: Layer {
    let id = UUID()
    var name: String = "Layer"
    var visible: Bool = true
    var locked: Bool = false
    var opacity: Float = 1.0
    var blendMode: BlendMode = .normal
    var transform = LayerTransform()
    var bounds: CGRect = .zero
    var zIndex: Int = 0
    
    func render(context: RenderContext) -> MTLTexture? {
        // Override in subclasses
        return nil
    }
    
    func getBounds(includeEffects: Bool) -> CGRect {
        // Apply transform to bounds
        var transformedBounds = bounds
        transformedBounds.origin.x += transform.position.x
        transformedBounds.origin.y += transform.position.y
        transformedBounds.size.width *= transform.scale
        transformedBounds.size.height *= transform.scale
        return transformedBounds
    }
    
    func hitTest(point: CGPoint) -> Bool {
        return getBounds(includeEffects: false).contains(point)
    }
}