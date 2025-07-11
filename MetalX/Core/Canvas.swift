import Foundation
import CoreGraphics
import Combine

// Canvas model that manages layers and notifies of changes
class Canvas: ObservableObject {
    @Published private(set) var layers: [any Layer] = []
    @Published var selectedLayer: (any Layer)?
    
    // Canvas properties
    var size: CGSize = CGSize(width: 1024, height: 1024)
    var backgroundColor: CGColor = CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
    lazy var effectStack: EffectStack = {
        let stack = EffectStack()
        stack.onUpdate = { [weak self] in
            self?.needsDisplay = true
        }
        return stack
    }()
    
    // Change tracking
    private var isDirty = true // Start with true to ensure initial render
    var needsDisplay: Bool {
        get { isDirty }
        set { isDirty = newValue }
    }
    
    // Layer management
    func addLayer(_ layer: any Layer, at index: Int? = nil) {
        var insertIndex = index ?? layers.count
        
        // If layer has shadow enabled, insert shadow layer first
        if layer.dropShadow.isEnabled {
            let shadowLayer = ShadowLayer(sourceLayer: layer)
            shadowLayer.shadowOffset = layer.dropShadow.offset
            shadowLayer.shadowBlur = layer.dropShadow.blur
            shadowLayer.shadowColor = layer.dropShadow.color
            shadowLayer.opacity = layer.dropShadow.opacity
            shadowLayer.updateFromSource()
            layers.insert(shadowLayer, at: insertIndex)
            insertIndex += 1 // Increment index so the layer goes after the shadow
        }
        
        layers.insert(layer, at: insertIndex)
        updateZIndices()
        needsDisplay = true
    }
    
    func removeLayer(_ layer: any Layer) {
        guard let index = layers.firstIndex(where: { $0.id == layer.id }) else { return }
        layers.remove(at: index)
        if selectedLayer?.id == layer.id {
            selectedLayer = nil
        }
        updateZIndices()
        needsDisplay = true
    }
    
    func moveLayer(_ layer: any Layer, to newIndex: Int) {
        guard let currentIndex = layers.firstIndex(where: { $0.id == layer.id }) else { return }
        guard currentIndex != newIndex else { return }
        
        layers.remove(at: currentIndex)
        layers.insert(layer, at: newIndex)
        updateZIndices()
        needsDisplay = true
    }
    
    func selectLayer(_ layer: (any Layer)?) {
        selectedLayer = layer
        needsDisplay = true
        
        // Post notification for selection change
        NotificationCenter.default.post(
            name: NSNotification.Name("CanvasSelectionChanged"),
            object: self
        )
    }
    
    // Reorder layers
    func bringToFront(_ layer: any Layer) {
        moveLayer(layer, to: layers.count - 1)
    }
    
    func sendToBack(_ layer: any Layer) {
        moveLayer(layer, to: 0)
    }
    
    func bringForward(_ layer: any Layer) {
        guard let index = layers.firstIndex(where: { $0.id == layer.id }) else { return }
        if index < layers.count - 1 {
            moveLayer(layer, to: index + 1)
        }
    }
    
    func sendBackward(_ layer: any Layer) {
        guard let index = layers.firstIndex(where: { $0.id == layer.id }) else { return }
        if index > 0 {
            moveLayer(layer, to: index - 1)
        }
    }
    
    // Move layer up/down
    func moveLayerUp(_ layer: any Layer) {
        guard let index = layers.firstIndex(where: { $0.id == layer.id }) else { return }
        
        // Skip shadow layers when finding the next position
        var targetIndex = index + 1
        while targetIndex < layers.count && layers[targetIndex] is ShadowLayer {
            targetIndex += 1
        }
        
        if targetIndex < layers.count {
            moveLayer(layer, to: targetIndex)
        }
    }
    
    func moveLayerDown(_ layer: any Layer) {
        guard let index = layers.firstIndex(where: { $0.id == layer.id }) else { return }
        
        // Skip shadow layers when finding the previous position
        var targetIndex = index - 1
        while targetIndex >= 0 && layers[targetIndex] is ShadowLayer {
            targetIndex -= 1
        }
        
        if targetIndex >= 0 {
            moveLayer(layer, to: targetIndex)
        }
    }
    
    func canMoveLayerUp(_ layer: any Layer) -> Bool {
        guard let index = layers.firstIndex(where: { $0.id == layer.id }) else { return false }
        
        // Check if there's a non-shadow layer above this one
        for i in (index + 1)..<layers.count {
            if !(layers[i] is ShadowLayer) {
                return true
            }
        }
        return false
    }
    
    func canMoveLayerDown(_ layer: any Layer) -> Bool {
        guard let index = layers.firstIndex(where: { $0.id == layer.id }) else { return false }
        
        // Check if there's a non-shadow layer below this one
        for i in (0..<index).reversed() {
            if !(layers[i] is ShadowLayer) {
                return true
            }
        }
        return false
    }
    
    // Clear canvas
    func clear() {
        layers.removeAll()
        selectedLayer = nil
        needsDisplay = true
    }
    
    // Load layers and rebuild shadows
    func loadLayers(_ newLayers: [any Layer]) {
        layers.removeAll()
        selectedLayer = nil
        
        // Add layers in order, which will create shadows as needed
        for layer in newLayers {
            addLayer(layer)
        }
        
        needsDisplay = true
    }
    
    // Private helpers
    private func updateZIndices() {
        for (index, layer) in layers.enumerated() {
            layer.zIndex = index
        }
    }
    
    // Mark canvas as needing redraw
    func setNeedsDisplay() {
        // Update shadow positions before redrawing
        for layer in layers {
            if let shadowLayer = layer as? ShadowLayer {
                shadowLayer.updateFromSource()
            }
        }
        
        needsDisplay = true
        NotificationCenter.default.post(
            name: NSNotification.Name("CanvasNeedsDisplay"),
            object: self
        )
    }
    
    // Update shadow layer when properties change
    func updateShadowForLayer(_ layer: any Layer) {
        // Find the shadow layer for this source layer
        if let shadowLayer = layers.first(where: { ($0 as? ShadowLayer)?.sourceLayer === layer }) as? ShadowLayer {
            if layer.dropShadow.isEnabled {
                // Update shadow properties
                shadowLayer.shadowOffset = layer.dropShadow.offset
                shadowLayer.shadowBlur = layer.dropShadow.blur
                shadowLayer.shadowColor = layer.dropShadow.color
                shadowLayer.opacity = layer.dropShadow.opacity
                shadowLayer.updateFromSource()
            } else {
                // Remove shadow layer if disabled
                removeLayer(shadowLayer)
            }
        } else if layer.dropShadow.isEnabled {
            // Add shadow layer if it doesn't exist
            if let index = layers.firstIndex(where: { $0.id == layer.id }) {
                let shadowLayer = ShadowLayer(sourceLayer: layer)
                shadowLayer.shadowOffset = layer.dropShadow.offset
                shadowLayer.shadowBlur = layer.dropShadow.blur
                shadowLayer.shadowColor = layer.dropShadow.color
                shadowLayer.opacity = layer.dropShadow.opacity
                shadowLayer.updateFromSource()
                layers.insert(shadowLayer, at: index)
                updateZIndices()
            }
        }
        setNeedsDisplay()
    }
}

// Layer change observer
extension Canvas {
    func observeLayer(_ layer: any Layer) {
        // In a full implementation, we would observe property changes
        // For now, we rely on manual setNeedsDisplay calls
    }
}