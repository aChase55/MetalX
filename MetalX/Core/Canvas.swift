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
    
    // Change tracking
    private var isDirty = true // Start with true to ensure initial render
    var needsDisplay: Bool {
        get { isDirty }
        set { isDirty = newValue }
    }
    
    // Layer management
    func addLayer(_ layer: any Layer, at index: Int? = nil) {
        let insertIndex = index ?? layers.count
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
    
    // Clear canvas
    func clear() {
        layers.removeAll()
        selectedLayer = nil
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
        needsDisplay = true
        NotificationCenter.default.post(
            name: NSNotification.Name("CanvasNeedsDisplay"),
            object: self
        )
    }
}

// Layer change observer
extension Canvas {
    func observeLayer(_ layer: any Layer) {
        // In a full implementation, we would observe property changes
        // For now, we rely on manual setNeedsDisplay calls
    }
}