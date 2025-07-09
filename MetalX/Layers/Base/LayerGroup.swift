import Foundation
import Metal
import CoreGraphics

// Layer group implementation for hierarchical layer management
class LayerGroup: BaseLayer, GroupLayer {
    var children: [Layer] = []
    var clipsToChildren: Bool = false
    var renderAsGroup: Bool = true
    
    // Cached group texture for optimization
    private var cachedGroupTexture: MTLTexture?
    private var isDirty: Bool = true
    
    override init() {
        super.init()
        self.name = "Group"
    }
    
    // MARK: - Group Management
    
    func addChild(_ layer: Layer) {
        children.append(layer)
        invalidateCache()
        updateBounds()
    }
    
    func removeChild(_ layer: Layer) {
        children.removeAll { $0.id == layer.id }
        invalidateCache()
        updateBounds()
    }
    
    func reorderChild(_ layer: Layer, to index: Int) {
        guard let currentIndex = children.firstIndex(where: { $0.id == layer.id }) else { return }
        guard index >= 0 && index < children.count else { return }
        
        children.remove(at: currentIndex)
        children.insert(layer, at: index)
        invalidateCache()
    }
    
    // MARK: - Bounds Calculation
    
    private func updateBounds() {
        guard !children.isEmpty else {
            bounds = .zero
            return
        }
        
        // Calculate combined bounds of all children
        var combinedBounds = CGRect.null
        
        for child in children {
            let childBounds = child.getBounds(includeEffects: true)
            combinedBounds = combinedBounds.union(childBounds)
        }
        
        bounds = combinedBounds.isNull ? .zero : combinedBounds
    }
    
    // MARK: - Rendering
    
    override func render(context: RenderContext) -> MTLTexture? {
        guard !children.isEmpty else { return nil }
        
        if renderAsGroup && !isDirty, let cached = cachedGroupTexture {
            return cached
        }
        
        // Render children to texture if renderAsGroup is true
        if renderAsGroup {
            return renderToGroupTexture(context: context)
        } else {
            // Direct rendering without caching
            return renderChildrenDirectly(context: context)
        }
    }
    
    private func renderToGroupTexture(context: RenderContext) -> MTLTexture? {
        // TODO: Implement group rendering to texture
        // This would create a texture, render all children to it,
        // and cache the result for performance
        isDirty = false
        return nil
    }
    
    private func renderChildrenDirectly(context: RenderContext) -> MTLTexture? {
        // TODO: Implement direct child rendering
        // This would composite children without intermediate texture
        return nil
    }
    
    // MARK: - Cache Management
    
    private func invalidateCache() {
        isDirty = true
        cachedGroupTexture = nil
    }
    
    // MARK: - Hit Testing
    
    override func hitTest(point: CGPoint) -> Bool {
        // First check if point is within group bounds
        guard super.hitTest(point: point) else { return false }
        
        // Then check children
        for child in children.reversed() {
            if child.hitTest(point: point) {
                return true
            }
        }
        
        return false
    }
    
    // Find which child was hit
    func hitTestChild(point: CGPoint) -> Layer? {
        guard hitTest(point: point) else { return nil }
        
        for child in children.reversed() {
            if child.hitTest(point: point) {
                // If child is a group, recurse
                if let childGroup = child as? LayerGroup {
                    if let hit = childGroup.hitTestChild(point: point) {
                        return hit
                    }
                }
                return child
            }
        }
        
        return nil
    }
}