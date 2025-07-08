# Compositing and Masking System Specification

## Overview
A sophisticated compositing system that handles complex masking operations, blend modes, and layer interactions with real-time performance.

## Core Compositing Architecture

### 1. Layer Stack System

```swift
class LayerStack {
    private var layers: [Layer] = []
    private var compositeCache: [LayerCacheKey: MTLTexture] = []
    
    // Layer types
    enum LayerType {
        case image(ImageLayer)
        case video(VideoLayer)
        case text(TextLayer)
        case shape(ShapeLayer)
        case adjustment(AdjustmentLayer)
        case effect(EffectLayer)
        case group(GroupLayer)
        case mask(MaskLayer)
    }
    
    // Compositing modes
    struct CompositingOptions {
        var blendMode: BlendMode = .normal
        var opacity: Float = 1.0
        var maskMode: MaskMode = .alpha
        var matteMode: MatteMode = .none
        var preserveTransparency: Bool = false
    }
}
```

### 2. Advanced Blend Modes

```swift
enum BlendMode {
    // Standard modes
    case normal
    case multiply
    case screen
    case overlay
    case softLight
    case hardLight
    
    // Advanced modes
    case colorDodge
    case colorBurn
    case linearDodge
    case linearBurn
    case vividLight
    case linearLight
    case pinLight
    case hardMix
    
    // Color modes
    case hue
    case saturation
    case color
    case luminosity
    
    // Special modes
    case difference
    case exclusion
    case subtract
    case divide
    
    // Custom shader
    case custom(shader: String)
}

// GPU-optimized blend implementation
fragment float4 blendFragment(VertexOut in [[stage_in]],
                             texture2d<float> base [[texture(0)]],
                             texture2d<float> blend [[texture(1)]],
                             constant BlendParams& params [[buffer(0)]]) {
    float4 baseColor = base.sample(sampler, in.uv);
    float4 blendColor = blend.sample(sampler, in.uv);
    
    // Apply blend mode
    float4 result = applyBlendMode(baseColor, blendColor, params.mode);
    
    // Apply opacity
    result = mix(baseColor, result, params.opacity * blendColor.a);
    
    return result;
}
```

### 3. Advanced Masking System

```swift
class MaskingSystem {
    // Mask types
    enum MaskType {
        case alpha          // Standard alpha mask
        case luminance      // Use luminance as alpha
        case vector         // Path-based mask
        case gradient       // Gradient mask
        case procedural     // Generated mask
        case channel        // Use specific channel
    }
    
    // Mask operations
    enum MaskOperation {
        case add
        case subtract
        case intersect
        case difference
        case feather(radius: Float)
        case expand(amount: Float)
        case contract(amount: Float)
    }
    
    // Compositing masks (inspired by Riveo)
    struct CompositingMask {
        var source: MaskSource
        var target: Layer
        var mode: CompositingMaskMode
        var invertSource: Bool
        var invertResult: Bool
    }
    
    enum CompositingMaskMode {
        case revealWith      // Reveal target with source
        case hideWith        // Hide target with source
        case intersectWith   // Show only intersection
        case excludeFrom     // Show only non-intersection
    }
}
```

### 4. Track Matte System

```swift
class TrackMatteSystem {
    enum MatteType {
        case alpha
        case alphaInverted
        case luminance
        case luminanceInverted
    }
    
    struct TrackMatte {
        var sourceLayer: Layer
        var matteLayer: Layer
        var matteType: MatteType
        var preserveSourceAlpha: Bool
    }
    
    // GPU implementation
    fragment float4 trackMatteFragment(VertexOut in [[stage_in]],
                                      texture2d<float> source [[texture(0)]],
                                      texture2d<float> matte [[texture(1)]],
                                      constant MatteParams& params [[buffer(0)]]) {
        float4 sourceColor = source.sample(sampler, in.uv);
        float4 matteColor = matte.sample(sampler, in.uv);
        
        float matteValue;
        switch (params.type) {
        case ALPHA:
            matteValue = matteColor.a;
            break;
        case LUMINANCE:
            matteValue = dot(matteColor.rgb, float3(0.299, 0.587, 0.114));
            break;
        }
        
        if (params.inverted) {
            matteValue = 1.0 - matteValue;
        }
        
        sourceColor.a *= matteValue;
        return sourceColor;
    }
}
```

### 5. Shape and Vector Masking

```swift
class VectorMaskSystem {
    // Path-based masks
    struct PathMask {
        var path: CGPath
        var fillRule: CGPathFillRule
        var feather: FeatherSettings
        var expansion: Float
    }
    
    // Shape operations
    enum ShapeOperation {
        case unite([PathMask])
        case subtract(PathMask, from: PathMask)
        case intersect([PathMask])
        case exclude([PathMask])
        case xor([PathMask])
    }
    
    // GPU rasterization
    func rasterizePath(path: CGPath,
                      size: CGSize,
                      antialiasing: AntialiasingMode) -> MTLTexture {
        // Use Metal tessellation for smooth curves
        // Apply signed distance fields for perfect antialiasing
    }
}
```

### 6. Selection Tools

```swift
class SelectionTools {
    // Selection methods
    enum SelectionMethod {
        case colorRange(color: UIColor, tolerance: Float, smoothness: Float)
        case luminanceRange(range: ClosedRange<Float>)
        case focusArea(point: CGPoint, range: Float)
        case edges(sensitivity: Float, contrast: Float)
        case subject(aiModel: SubjectDetectionModel)
        case sky(aiModel: SkyDetectionModel)
        case hair(refinement: HairRefinementSettings)
    }
    
    // Selection refinement
    struct SelectionRefinement {
        var smoothRadius: Float
        var featherRadius: Float
        var contractExpand: Float
        var shiftEdge: Float
        var decontaminate: DecontaminationSettings?
    }
    
    // Magic wand tool
    func magicWand(at point: CGPoint,
                   tolerance: Float,
                   contiguous: Bool) -> Selection {
        // Flood fill algorithm on GPU
        // Support non-contiguous selection
    }
}
```

### 7. Layer Effects System

```swift
class LayerEffects {
    // Effect types
    struct DropShadow {
        var color: UIColor
        var opacity: Float
        var angle: Float
        var distance: Float
        var spread: Float
        var size: Float
        var noise: Float
        var knockout: Bool
    }
    
    struct InnerShadow {
        var color: UIColor
        var opacity: Float
        var angle: Float
        var distance: Float
        var choke: Float
        var size: Float
    }
    
    struct OuterGlow {
        var color: UIColor
        var opacity: Float
        var noise: Float
        var technique: GlowTechnique
        var spread: Float
        var size: Float
        var range: Float
        var jitter: Float
    }
    
    struct Stroke {
        var size: Float
        var position: StrokePosition
        var fillType: StrokeFillType
        var opacity: Float
    }
    
    // Layer styles
    class LayerStyle {
        var effects: [LayerEffect] = []
        var blendingOptions: BlendingOptions
        var enabled: Bool = true
        
        // Copy/paste styles
        func copy() -> LayerStyle
        func paste(from style: LayerStyle)
    }
}
```

### 8. Smart Object System

```swift
class SmartObjectSystem {
    // Smart object that maintains original data
    class SmartObject {
        private var sourceData: Data
        private var sourceType: SourceType
        private var currentTransform: CGAffineTransform
        private var appliedFilters: [Filter]
        
        // Non-destructive editing
        func updateTransform(_ transform: CGAffineTransform)
        func applyFilter(_ filter: Filter)
        func reset()
        
        // Re-render at any quality
        func render(at size: CGSize,
                   quality: RenderQuality) -> MTLTexture
    }
    
    // Smart filters
    struct SmartFilter {
        var filter: Filter
        var mask: Mask?
        var blendMode: BlendMode
        var opacity: Float
        var enabled: Bool
    }
}
```

### 9. Channel Operations

```swift
class ChannelOperations {
    // Channel manipulation
    enum Channel {
        case red
        case green  
        case blue
        case alpha
        case luminance
        case custom(index: Int)
    }
    
    // Channel operations
    func extractChannel(_ channel: Channel,
                       from texture: MTLTexture) -> MTLTexture
    
    func replaceChannel(_ channel: Channel,
                       in texture: MTLTexture,
                       with source: MTLTexture) -> MTLTexture
    
    func channelMixer(input: MTLTexture,
                     matrix: ChannelMixMatrix) -> MTLTexture
    
    // Advanced channel ops
    struct ChannelCalculation {
        var source1: (texture: MTLTexture, channel: Channel)
        var source2: (texture: MTLTexture, channel: Channel)?
        var operation: ChannelOperation
        var scale: Float
        var offset: Float
    }
}
```

### 10. Clipping and Grouping

```swift
class ClippingSystem {
    // Clipping masks
    struct ClippingMask {
        var clipLayer: Layer
        var targetLayers: [Layer]
        var clipToAlpha: Bool
        var preserveTransparency: Bool
    }
    
    // Layer groups
    class LayerGroup {
        var layers: [Layer]
        var passThrough: Bool // Blend with layers below
        var isolate: Bool // Isolate blending
        var knockout: KnockoutMode
        
        // Group-level effects
        var opacity: Float
        var blendMode: BlendMode
        var masks: [Mask]
    }
    
    // Knockout modes
    enum KnockoutMode {
        case none
        case shallow // Knockout to group
        case deep   // Knockout to background
    }
}
```

## Performance Optimizations

### Compositing Cache
```swift
class CompositingCache {
    // Cache intermediate results
    private var cache: [CacheKey: CacheEntry] = [:]
    
    struct CacheKey: Hashable {
        let layerHashes: [Int]
        let blendModes: [BlendMode]
        let opacities: [Float]
        let size: CGSize
    }
    
    // Invalidation tracking
    func invalidate(layer: Layer) {
        // Invalidate all cache entries containing this layer
        // Mark dependent layers for re-composition
    }
}
```

### GPU Batch Compositing
```swift
class BatchCompositor {
    // Compose multiple operations in single pass
    func batchComposite(operations: [CompositeOp]) -> MTLTexture {
        // Sort by blend mode to minimize state changes
        // Group compatible operations
        // Use indirect command buffers for efficiency
    }
}
```

## Integration Points

### With Main Engine
```swift
extension RenderEngine {
    func compositeLayer(_ layers: [Layer],
                       background: MTLTexture?) -> MTLTexture
    
    func createMask(using selection: Selection) -> Mask
    
    func applyLayerStyle(_ style: LayerStyle,
                        to layer: Layer)
}
```