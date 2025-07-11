import Foundation
import CoreGraphics
import Metal
import simd

// Drop shadow configuration
struct DropShadow {
    var isEnabled: Bool = false
    var offset: CGSize = CGSize(width: 2, height: 2)
    var blur: CGFloat = 4.0
    var color: CGColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0.5)
    var opacity: Float = 1.0
    var scale: CGFloat = 1.0  // Scale the shadow size while keeping it centered
}

// Layer-specific transform structure
struct LayerTransform {
    var position: CGPoint = .zero
    var scale: CGFloat = 1.0
    var rotation: CGFloat = 0.0
    var flipHorizontal: Bool = false
    var flipVertical: Bool = false
    
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
        
        // Apply scale with flips
        let scaleX = Float(scale) * (flipHorizontal ? -1.0 : 1.0)
        let scaleY = Float(scale) * (flipVertical ? -1.0 : 1.0)
        let scaleMatrix = float4x4(
            SIMD4<Float>(scaleX, 0, 0, 0),
            SIMD4<Float>(0, scaleY, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
        
        return result * rotMatrix * scaleMatrix
    }
}

// Base layer protocol
protocol Layer: AnyObject, Identifiable {
    var id: UUID { get set }
    var name: String { get set }
    var isVisible: Bool { get set }
    var isLocked: Bool { get set }
    var opacity: Float { get set }
    var blendMode: BlendMode { get set }
    var transform: LayerTransform { get set }
    var bounds: CGRect { get }
    var zIndex: Int { get set }
    var dropShadow: DropShadow { get set }
    var effectStack: EffectStack { get set }
    
    // Rendering
    func render(context: RenderContext) -> MTLTexture?
    func getBounds(includeEffects: Bool) -> CGRect
    func hitTest(point: CGPoint) -> Bool
}

// Base implementation
class BaseLayer: Layer {
    var id = UUID()
    var name: String = "Layer"
    var isVisible: Bool = true
    var isLocked: Bool = false
    var opacity: Float = 1.0
    var blendMode: BlendMode = .normal
    var transform = LayerTransform()
    var bounds: CGRect = .zero
    var zIndex: Int = 0
    var dropShadow = DropShadow()
    lazy var effectStack: EffectStack = {
        let stack = EffectStack()
        stack.onUpdate = { [weak self] in
            // Notify canvas of changes
            NotificationCenter.default.post(name: NSNotification.Name("CanvasNeedsDisplay"), object: nil)
        }
        return stack
    }()
    
    func render(context: RenderContext) -> MTLTexture? {
        // Override in subclasses
        return nil
    }
    
    func getBounds(includeEffects: Bool) -> CGRect {
        // Apply transform to bounds
        let scaledWidth = bounds.width * transform.scale
        let scaledHeight = bounds.height * transform.scale
        
        // Position is the center of the layer
        var transformedBounds = CGRect(
            x: transform.position.x - scaledWidth / 2,
            y: transform.position.y - scaledHeight / 2,
            width: scaledWidth,
            height: scaledHeight
        )
        
        // Include drop shadow in bounds if enabled and requested
        if includeEffects && dropShadow.isEnabled {
            let shadowOffsetX = abs(dropShadow.offset.width)
            let shadowOffsetY = abs(dropShadow.offset.height)
            let shadowBlur = dropShadow.blur
            
            // Expand bounds to include shadow
            let expansion = shadowBlur + max(shadowOffsetX, shadowOffsetY)
            transformedBounds = transformedBounds.insetBy(dx: -expansion, dy: -expansion)
        }
        
        return transformedBounds
    }
    
    func hitTest(point: CGPoint) -> Bool {
        // Get bounds with transform applied
        let transformedBounds = getBounds(includeEffects: false)
        return transformedBounds.contains(point)
    }
}