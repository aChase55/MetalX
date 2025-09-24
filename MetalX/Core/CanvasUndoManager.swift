import Foundation
import UIKit

// MARK: - Canvas State for Undo/Redo
struct CanvasState: Codable {
    let layers: [LayerData]
    let canvasEffects: [EffectData]?
    let backgroundColor: CodableColor
    let canvasSize: CGSize
}

// MARK: - Undo Manager Extension
extension Canvas {
    
    // Capture current state for undo
    func captureState(actionName: String) {
        // Create snapshot of current state
        guard let currentState = createCurrentState() else { return }
        
        // Store the current state before making changes
        let previousState = currentStateData ?? currentState
        
        // Register undo operation
        undoManager.registerUndo(withTarget: self) { canvas in
            // Capture state that will be restored for redo
            let stateToRestore = canvas.createCurrentState()
            
            // Restore to previous state
            canvas.restoreState(from: previousState)
            
            // Register redo operation
            if let redoState = stateToRestore {
                canvas.undoManager.registerUndo(withTarget: canvas) { redoCanvas in
                    redoCanvas.restoreState(from: redoState)
                }
            }
        }
        
        undoManager.setActionName(actionName)
        currentStateData = currentState
        
        // Post notification for UI updates
        NotificationCenter.default.post(name: .canvasUndoStateChanged, object: self)
    }
    
    // Create current state snapshot
    private func createCurrentState() -> CanvasState? {
        let layerDataArray = layers.compactMap { layer -> LayerData? in
            return layer.toLayerData()
        }
        
        // TODO: Implement effect serialization when needed
        let effectDataArray: [EffectData]? = nil
        
        return CanvasState(
            layers: layerDataArray,
            canvasEffects: effectDataArray,
            backgroundColor: CodableColor(cgColor: backgroundColor),
            canvasSize: size
        )
    }
    
    // Restore state from snapshot
    private func restoreState(from state: CanvasState) {
        // Clear current state
        clearLayersWithoutUndo()
        effectStack.effects.removeAll()
        
        // Restore canvas properties
        size = state.canvasSize
        backgroundColor = state.backgroundColor.cgColor
        
        // Restore layers
        for layerData in state.layers {
            if let layer = LayerFactory.createLayer(from: layerData) {
                addLayerWithoutUndo(layer)
            }
        }
        
        // Restore effects
        if let effects = state.canvasEffects {
            for effectData in effects {
                if let effect = LayerFactory.createEffect(from: effectData) {
                    effectStack.addEffect(effect)
                }
            }
        }
        
        // Force display update
        setNeedsDisplay()
        
        // Notify about state change
        NotificationCenter.default.post(name: .canvasStateRestored, object: self)
    }
    
    // Store current state for comparison
    private var currentStateData: CanvasState? {
        get {
            objc_getAssociatedObject(self, &AssociatedKeys.currentStateData) as? CanvasState
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.currentStateData, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}

// Associated object keys
private struct AssociatedKeys {
    static var currentStateData = "currentStateData"
}

// MARK: - Notifications
extension Notification.Name {
    static let canvasUndoStateChanged = Notification.Name("canvasUndoStateChanged")
    static let canvasStateRestored = Notification.Name("canvasStateRestored")
}

// MARK: - Undo Action Types
enum UndoActionType {
    case addLayer
    case deleteLayer
    case moveLayer
    case transformLayer
    case changeLayerProperty
    case addEffect
    case removeEffect
    case changeEffectProperty
    case changeCanvasProperty
    
    var actionName: String {
        switch self {
        case .addLayer: return "Add Layer"
        case .deleteLayer: return "Delete Layer"
        case .moveLayer: return "Move Layer"
        case .transformLayer: return "Transform Layer"
        case .changeLayerProperty: return "Change Layer Property"
        case .addEffect: return "Add Effect"
        case .removeEffect: return "Remove Effect"
        case .changeEffectProperty: return "Change Effect"
        case .changeCanvasProperty: return "Change Canvas"
        }
    }
}
