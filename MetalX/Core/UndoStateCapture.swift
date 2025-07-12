import Foundation
import UIKit

// MARK: - Undo State Capture for Continuous Updates
class UndoStateCapture {
    private var isCapturing = false
    private var captureTimer: Timer?
    private weak var canvas: Canvas?
    private var actionType: UndoActionType
    
    init(canvas: Canvas, actionType: UndoActionType) {
        self.canvas = canvas
        self.actionType = actionType
    }
    
    // Begin capturing state changes (called on gesture/slider begin)
    func beginCapture() {
        guard !isCapturing else { return }
        isCapturing = true
        
        // Capture initial state immediately
        canvas?.captureState(actionName: actionType.actionName)
    }
    
    // End capturing and finalize the undo state (called on gesture/slider end)
    func endCapture() {
        guard isCapturing else { return }
        isCapturing = false
        
        // Cancel any pending timer
        captureTimer?.invalidate()
        captureTimer = nil
    }
    
    // Update during continuous changes (debounced)
    func captureUpdate() {
        guard isCapturing else { return }
        
        // Cancel previous timer
        captureTimer?.invalidate()
        
        // Set new timer to capture state after a delay
        captureTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.canvas?.captureState(actionName: self?.actionType.actionName ?? "Change")
        }
    }
}

// MARK: - Canvas Extension for Undo State Management
extension Canvas {
    // Create state capture for continuous updates
    func createStateCapture(for actionType: UndoActionType) -> UndoStateCapture {
        return UndoStateCapture(canvas: self, actionType: actionType)
    }
    
    // Capture state for discrete actions
    func captureDiscreteState(actionName: String, beforeAction: Bool = true, action: () -> Void) {
        if beforeAction {
            captureState(actionName: actionName)
        }
        action()
        if !beforeAction {
            captureState(actionName: actionName)
        }
    }
}

// MARK: - Property Change Tracking
protocol UndoablePropertyChange {
    var canvas: Canvas? { get }
    func beginPropertyChange(actionName: String)
    func endPropertyChange()
}

extension UndoablePropertyChange {
    func trackPropertyChange<T>(keyPath: ReferenceWritableKeyPath<Self, T>, 
                                newValue: T, 
                                actionName: String) {
        beginPropertyChange(actionName: actionName)
        self[keyPath: keyPath] = newValue
        endPropertyChange()
    }
}

// MARK: - Layer Undo Support
extension Layer {
    func captureTransformState(in canvas: Canvas) -> UndoStateCapture {
        return canvas.createStateCapture(for: .transformLayer)
    }
    
    func capturePropertyState(in canvas: Canvas) -> UndoStateCapture {
        return canvas.createStateCapture(for: .changeLayerProperty)
    }
}