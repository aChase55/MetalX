# Layer System and Management Specification

## Overview
Comprehensive layer system for managing, selecting, transforming, and compositing multiple images, videos, text, and effects with professional-grade controls.

## Core Layer Architecture

### 1. Layer Hierarchy System

```swift
// Base layer protocol
protocol Layer: AnyObject {
    var id: UUID { get }
    var name: String { get set }
    var type: LayerType { get }
    var visible: Bool { get set }
    var locked: Bool { get set }
    var opacity: Float { get set }
    var blendMode: BlendMode { get set }
    var transform: Transform3D { get set }
    var bounds: CGRect { get }
    var parent: Layer? { get set }
    var children: [Layer] { get set }
    var zIndex: Int { get set }
    
    // Rendering
    func render(context: RenderContext) -> MTLTexture?
    func getBounds(includeEffects: Bool) -> CGRect
    func hitTest(point: CGPoint) -> Bool
}

// Layer types
enum LayerType {
    case image(ImageLayer)
    case video(VideoLayer)
    case text(TextLayer)
    case shape(ShapeLayer)
    case adjustment(AdjustmentLayer)
    case group(GroupLayer)
    case smart(SmartLayer)
    case fill(FillLayer)
    case gradient(GradientLayer)
    case pattern(PatternLayer)
    case camera(CameraLayer)
    case light(LightLayer)
}
```

### 2. Layer Stack Management

```swift
class LayerStack {
    private var layers: [Layer] = []
    private var selectedLayers: Set<UUID> = []
    private var activeLayer: Layer?
    
    // Layer operations
    func addLayer(_ layer: Layer, 
                  at index: Int? = nil,
                  autoSelect: Bool = true) {
        // Insert at index or top
        let insertIndex = index ?? layers.count
        layers.insert(layer, at: insertIndex)
        
        // Update z-indices
        updateZIndices()
        
        // Auto-select new layer
        if autoSelect {
            selectLayer(layer)
        }
        
        // Notify observers
        notifyLayerAdded(layer, at: insertIndex)
    }
    
    func removeLayer(_ layer: Layer) {
        guard let index = layers.firstIndex(where: { $0.id == layer.id }) else { return }
        
        // Remove from selection
        selectedLayers.remove(layer.id)
        
        // Remove from stack
        layers.remove(at: index)
        
        // Update z-indices
        updateZIndices()
        
        // Notify observers
        notifyLayerRemoved(layer, from: index)
    }
    
    // Reordering
    func moveLayer(_ layer: Layer, to newIndex: Int) {
        guard let currentIndex = layers.firstIndex(where: { $0.id == layer.id }) else { return }
        
        // Remove and reinsert
        layers.remove(at: currentIndex)
        layers.insert(layer, at: newIndex)
        
        // Update z-indices
        updateZIndices()
        
        // Notify observers
        notifyLayerMoved(layer, from: currentIndex, to: newIndex)
    }
    
    // Bulk operations
    func moveLayers(_ layerIDs: [UUID], by offset: Int) {
        // Move multiple layers while maintaining relative order
        let layersToMove = layers.filter { layerIDs.contains($0.id) }
        let sortedByIndex = layersToMove.sorted { 
            layers.firstIndex(of: $0)! < layers.firstIndex(of: $1)!
        }
        
        // Calculate new positions
        for layer in sortedByIndex {
            if let currentIndex = layers.firstIndex(of: layer) {
                let newIndex = max(0, min(layers.count - 1, currentIndex + offset))
                moveLayer(layer, to: newIndex)
            }
        }
    }
}
```

### 3. Layer Selection System

```swift
class LayerSelectionManager {
    private var selectedLayers: OrderedSet<Layer> = []
    private var primarySelection: Layer?
    
    // Selection modes
    enum SelectionMode {
        case replace
        case add
        case subtract
        case toggle
    }
    
    // Selection methods
    func selectLayer(_ layer: Layer, mode: SelectionMode = .replace) {
        switch mode {
        case .replace:
            clearSelection()
            selectedLayers.insert(layer)
            primarySelection = layer
            
        case .add:
            selectedLayers.insert(layer)
            if primarySelection == nil {
                primarySelection = layer
            }
            
        case .subtract:
            selectedLayers.remove(layer)
            if primarySelection == layer {
                primarySelection = selectedLayers.first
            }
            
        case .toggle:
            if selectedLayers.contains(layer) {
                selectLayer(layer, mode: .subtract)
            } else {
                selectLayer(layer, mode: .add)
            }
        }
        
        notifySelectionChanged()
    }
    
    // Range selection
    func selectRange(from startLayer: Layer, to endLayer: Layer) {
        guard let startIndex = layerStack.index(of: startLayer),
              let endIndex = layerStack.index(of: endLayer) else { return }
        
        let range = min(startIndex, endIndex)...max(startIndex, endIndex)
        
        clearSelection()
        for index in range {
            selectedLayers.insert(layerStack[index])
        }
        
        primarySelection = startLayer
        notifySelectionChanged()
    }
    
    // Selection by criteria
    func selectLayers(matching criteria: SelectionCriteria) {
        let matching = layerStack.filter { layer in
            criteria.matches(layer)
        }
        
        clearSelection()
        selectedLayers = OrderedSet(matching)
        primarySelection = matching.first
        notifySelectionChanged()
    }
    
    // Auto-select
    func autoSelect(at point: CGPoint, 
                   tolerance: CGFloat = 0,
                   throughGroups: Bool = false) -> Layer? {
        // Hit test from top to bottom
        for layer in layerStack.reversed() {
            if layer.locked || !layer.visible { continue }
            
            if throughGroups || !(layer is GroupLayer) {
                if layer.hitTest(point: point, tolerance: tolerance) {
                    selectLayer(layer)
                    return layer
                }
            }
        }
        
        return nil
    }
}
```

### 4. Layer Transform System

```swift
class LayerTransformController {
    // Transform handle types
    enum HandleType {
        case topLeft, topCenter, topRight
        case middleLeft, middleRight
        case bottomLeft, bottomCenter, bottomRight
        case rotation
        case skewHorizontal, skewVertical
        case perspective(corner: Int)
    }
    
    // Interactive transform
    class InteractiveTransform {
        private var originalTransform: Transform3D
        private var transformInProgress: Transform3D
        private var pivot: CGPoint
        
        func beginTransform(layer: Layer, handle: HandleType, startPoint: CGPoint) {
            originalTransform = layer.transform
            transformInProgress = originalTransform
            
            // Calculate pivot based on handle
            pivot = calculatePivot(for: handle, bounds: layer.bounds)
        }
        
        func updateTransform(currentPoint: CGPoint, 
                           modifiers: TransformModifiers) {
            switch currentHandle {
            case .topLeft, .topRight, .bottomLeft, .bottomRight:
                updateScale(currentPoint: currentPoint, 
                          constrainProportions: modifiers.shiftPressed)
                
            case .rotation:
                updateRotation(currentPoint: currentPoint,
                             snapAngles: modifiers.shiftPressed)
                
            case .skewHorizontal, .skewVertical:
                updateSkew(currentPoint: currentPoint)
                
            case .perspective(let corner):
                updatePerspective(corner: corner, point: currentPoint)
            }
            
            // Apply transform
            layer.transform = transformInProgress
        }
        
        // Smart guides and snapping
        func updateWithSnapping(currentPoint: CGPoint) -> CGPoint {
            var snappedPoint = currentPoint
            
            // Check alignment with other layers
            let snapTargets = findSnapTargets(for: layer)
            
            for target in snapTargets {
                // Edge snapping
                if let edgeSnap = checkEdgeSnapping(layer, target, currentPoint) {
                    snappedPoint = edgeSnap.snappedPoint
                    showSnapGuide(edgeSnap.guide)
                }
                
                // Center snapping
                if let centerSnap = checkCenterSnapping(layer, target, currentPoint) {
                    snappedPoint = centerSnap.snappedPoint
                    showSnapGuide(centerSnap.guide)
                }
            }
            
            return snappedPoint
        }
    }
}
```

### 5. Image Layer Implementation

```swift
class ImageLayer: Layer {
    var image: UIImage
    var contentMode: ContentMode = .scaleAspectFit
    var cropRect: CGRect?
    
    // Image adjustments
    var adjustments = ImageAdjustments()
    
    struct ImageAdjustments {
        var brightness: Float = 0
        var contrast: Float = 0
        var saturation: Float = 0
        var hue: Float = 0
        var temperature: Float = 0
        var tint: Float = 0
        var exposure: Float = 0
        var gamma: Float = 1.0
        var highlights: Float = 0
        var shadows: Float = 0
        var sharpness: Float = 0
    }
    
    // Smart image features
    func autoEnhance() {
        let analysis = analyzeImage(image)
        
        adjustments = ImageAdjustments(
            brightness: analysis.suggestedBrightness,
            contrast: analysis.suggestedContrast,
            saturation: analysis.suggestedSaturation,
            exposure: analysis.suggestedExposure
        )
    }
    
    // Content-aware scaling
    func contentAwareScale(to size: CGSize) {
        let saliencyMap = generateSaliencyMap(for: image)
        let scaledImage = seamCarving(
            image: image,
            targetSize: size,
            saliencyMap: saliencyMap
        )
        self.image = scaledImage
    }
}
```

### 6. Layer Effects and Styles

```swift
class LayerStyle {
    // Drop shadow
    var dropShadow: DropShadowEffect?
    
    struct DropShadowEffect {
        var color: UIColor = .black
        var opacity: Float = 0.75
        var angle: Float = 120 // degrees
        var distance: Float = 5
        var spread: Float = 0
        var size: Float = 5
        var contour: Curve = .linear
        var antialiased: Bool = true
        var noise: Float = 0
        var knockOut: Bool = false
        var blendMode: BlendMode = .multiply
    }
    
    // Inner shadow
    var innerShadow: InnerShadowEffect?
    
    // Outer glow
    var outerGlow: GlowEffect?
    
    struct GlowEffect {
        var color: UIColor = .white
        var opacity: Float = 0.75
        var technique: GlowTechnique = .softer
        var spread: Float = 0
        var size: Float = 5
        var contour: Curve = .linear
        var antialiased: Bool = true
        var range: Float = 0.5
        var jitter: Float = 0
        var blendMode: BlendMode = .screen
    }
    
    // Stroke
    var stroke: StrokeEffect?
    
    struct StrokeEffect {
        var size: Float = 3
        var position: StrokePosition = .outside
        var blendMode: BlendMode = .normal
        var opacity: Float = 1.0
        var fillType: StrokeFillType
        
        enum StrokePosition {
            case inside, center, outside
        }
        
        enum StrokeFillType {
            case color(UIColor)
            case gradient(Gradient)
            case pattern(Pattern)
        }
    }
    
    // Advanced blending options
    var blendingOptions = BlendingOptions()
    
    struct BlendingOptions {
        var blendInteriorEffects: Bool = false
        var blendClippedLayers: Bool = true
        var transparencyShapesLayer: Bool = true
        var layerMaskHidesEffects: Bool = false
        var vectorMaskHidesEffects: Bool = false
        
        // Blend if sliders
        var blendIf: BlendIfSettings?
        
        struct BlendIfSettings {
            var channel: Channel = .gray
            var thisLayer: Range<Float> = 0...255
            var underlyingLayer: Range<Float> = 0...255
            var smooth: Bool = true
        }
    }
}
```

### 7. Multi-Layer Operations

```swift
class MultiLayerOperations {
    // Alignment
    func alignLayers(_ layers: [Layer], 
                    alignment: Alignment,
                    relativeTo: AlignmentReference = .selection) {
        let bounds = calculateBounds(for: layers, relativeTo: relativeTo)
        
        for layer in layers {
            let layerBounds = layer.getBounds(includeEffects: true)
            var newPosition = layer.transform.position
            
            switch alignment {
            case .left:
                newPosition.x = bounds.minX + (layer.position.x - layerBounds.minX)
            case .centerHorizontal:
                newPosition.x = bounds.midX
            case .right:
                newPosition.x = bounds.maxX - (layerBounds.maxX - layer.position.x)
            case .top:
                newPosition.y = bounds.minY + (layer.position.y - layerBounds.minY)
            case .centerVertical:
                newPosition.y = bounds.midY
            case .bottom:
                newPosition.y = bounds.maxY - (layerBounds.maxY - layer.position.y)
            }
            
            layer.transform.position = newPosition
        }
    }
    
    // Distribution
    func distributeLayers(_ layers: [Layer],
                         distribution: Distribution,
                         axis: Axis) {
        guard layers.count > 2 else { return }
        
        // Sort layers by position on axis
        let sorted = layers.sorted { layer1, layer2 in
            switch axis {
            case .horizontal:
                return layer1.transform.position.x < layer2.transform.position.x
            case .vertical:
                return layer1.transform.position.y < layer2.transform.position.y
            }
        }
        
        let first = sorted.first!
        let last = sorted.last!
        
        switch distribution {
        case .equalSpacing:
            distributeEqualSpacing(sorted, from: first, to: last, axis: axis)
        case .equalDistance:
            distributeEqualDistance(sorted, from: first, to: last, axis: axis)
        }
    }
    
    // Grouping
    func groupLayers(_ layers: [Layer], name: String? = nil) -> GroupLayer {
        let group = GroupLayer()
        group.name = name ?? "Group \(groupCounter)"
        
        // Calculate group bounds
        let bounds = calculateCombinedBounds(layers)
        group.transform.position = CGPoint(x: bounds.midX, y: bounds.midY)
        
        // Reparent layers
        for layer in layers {
            // Convert to local coordinates
            layer.transform = convertToLocal(layer.transform, relativeTo: group.transform)
            layer.parent = group
            group.children.append(layer)
        }
        
        // Insert group at position of highest layer
        let highestIndex = layers.map { layerStack.index(of: $0) }.max()!
        layerStack.insertLayer(group, at: highestIndex)
        
        // Remove original layers from stack
        layers.forEach { layerStack.removeLayer($0, keepInGroup: true) }
        
        return group
    }
    
    // Merging
    func mergeLayers(_ layers: [Layer], 
                    mergeType: MergeType = .normal) -> Layer {
        // Create render context
        let bounds = calculateCombinedBounds(layers)
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        
        let mergedImage = renderer.image { context in
            // Render each layer in order
            for layer in layers.sorted(by: { $0.zIndex < $1.zIndex }) {
                if let rendered = layer.render(context: renderContext) {
                    // Apply blend mode
                    context.cgContext.setBlendMode(layer.blendMode.cgBlendMode)
                    context.cgContext.setAlpha(CGFloat(layer.opacity))
                    
                    // Draw rendered layer
                    rendered.draw(at: layer.position)
                }
            }
        }
        
        // Create new image layer
        let mergedLayer = ImageLayer(image: mergedImage)
        mergedLayer.name = "Merged Layer"
        mergedLayer.transform.position = CGPoint(x: bounds.midX, y: bounds.midY)
        
        return mergedLayer
    }
}
```

### 8. Layer Masking

```swift
class LayerMask {
    enum MaskType {
        case alpha          // Use alpha channel
        case vector         // Vector path
        case bitmap         // Raster image
        case gradient       // Gradient mask
        case text          // Text as mask
    }
    
    var type: MaskType
    var inverted: Bool = false
    var feather: Float = 0
    var opacity: Float = 1.0
    var linked: Bool = true // Move with layer
    
    // Apply mask during rendering
    func applyMask(to texture: MTLTexture, 
                   in commandBuffer: MTLCommandBuffer) -> MTLTexture {
        let masked = device.makeTexture(descriptor: texture.descriptor)!
        
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)!
        encoder.setRenderPipelineState(maskPipeline)
        encoder.setTexture(texture, index: 0)
        encoder.setTexture(maskTexture, index: 1)
        
        var params = MaskParameters(
            feather: feather,
            opacity: opacity,
            inverted: inverted
        )
        encoder.setBytes(&params, length: MemoryLayout<MaskParameters>.size, index: 0)
        
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        
        return masked
    }
}
```

### 9. Smart Layers

```swift
class SmartLayer: Layer {
    // Original data preservation
    private var originalContent: SmartContent
    private var appliedFilters: [SmartFilter] = []
    private var currentTransform: CGAffineTransform = .identity
    
    enum SmartContent {
        case image(UIImage)
        case raw(Data, CameraProfile)
        case vector(SVGDocument)
        case composition([Layer])
    }
    
    // Non-destructive filters
    struct SmartFilter {
        var filter: Filter
        var parameters: [String: Any]
        var mask: LayerMask?
        var opacity: Float = 1.0
        var blendMode: BlendMode = .normal
        var enabled: Bool = true
    }
    
    // Update without quality loss
    func updateTransform(_ transform: CGAffineTransform) {
        currentTransform = transform
        // Re-render from original
        invalidateCache()
    }
    
    // Edit original
    func editOriginal(completion: @escaping (SmartContent) -> SmartContent) {
        let edited = completion(originalContent)
        originalContent = edited
        invalidateCache()
    }
}
```

### 10. Layer Performance

```swift
class LayerCache {
    private var cache: [UUID: CachedLayer] = [:]
    
    struct CachedLayer {
        var texture: MTLTexture
        var bounds: CGRect
        var timestamp: Date
        var dependencies: Set<UUID>
    }
    
    // Intelligent caching
    func shouldCache(layer: Layer) -> Bool {
        // Cache if layer is complex
        if layer.effects.count > 3 { return true }
        
        // Cache if frequently accessed
        if layer.accessCount > 10 { return true }
        
        // Cache if rarely changes
        if layer.lastModified.timeIntervalSinceNow < -60 { return true }
        
        return false
    }
    
    // Render with caching
    func renderCached(layer: Layer, context: RenderContext) -> MTLTexture? {
        let cacheKey = layer.id
        
        // Check cache validity
        if let cached = cache[cacheKey],
           isCacheValid(cached, for: layer) {
            return cached.texture
        }
        
        // Render and cache
        guard let rendered = layer.render(context: context) else { return nil }
        
        if shouldCache(layer) {
            cache[cacheKey] = CachedLayer(
                texture: rendered,
                bounds: layer.bounds,
                timestamp: Date(),
                dependencies: layer.calculateDependencies()
            )
        }
        
        return rendered
    }
}
```

## Integration Examples

```swift
// Adding multiple images
let imageURLs = selectMultipleImages()
for (index, url) in imageURLs.enumerated() {
    let imageLayer = ImageLayer(image: UIImage(contentsOf: url)!)
    imageLayer.name = url.lastPathComponent
    
    // Offset each image
    imageLayer.transform.position = CGPoint(
        x: 100 + (index * 20),
        y: 100 + (index * 20)
    )
    
    layerStack.addLayer(imageLayer)
}

// Applying drop shadow to selection
for layer in selectionManager.selectedLayers {
    layer.style.dropShadow = DropShadowEffect(
        color: .black,
        opacity: 0.5,
        angle: 135,
        distance: 10,
        size: 10
    )
}

// Complex blending
let topLayer = layerStack.layers.last!
topLayer.blendMode = .overlay
topLayer.opacity = 0.7
topLayer.style.blendingOptions.blendIf = BlendIfSettings(
    channel: .gray,
    thisLayer: 50...200,
    underlyingLayer: 0...255
)
```