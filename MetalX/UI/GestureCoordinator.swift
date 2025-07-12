import UIKit
import Foundation
import MetalKit

/// Handles all gesture recognition and interaction for the canvas
class GestureCoordinator: NSObject {
    // MARK: - Properties
    
    weak var canvas: Canvas?
    weak var metalView: MTKView?
    weak var scrollView: UIScrollView?
    
    // Gesture state
    private var panStartLocation: CGPoint = .zero
    private var pinchStartScale: CGFloat = 1.0
    private var rotationStartAngle: CGFloat = 0.0
    
    // Undo state capture
    private var undoStateCapture: UndoStateCapture?
    
    // Alignment guides
    private let alignmentEngine = AlignmentEngine()
    private let guideRenderer = GuideRenderer()
    private var activeGuides: [AlignmentGuide] = []
    private weak var guideLayer: CALayer?
    
    // Callbacks
    var onNeedsDisplay: (() -> Void)?
    var onGuidesChanged: (([AlignmentGuide]) -> Void)?
    
    // MARK: - Initialization
    
    init(canvas: Canvas) {
        self.canvas = canvas
        super.init()
    }
    
    // MARK: - Setup
    
    func setupGestures(for view: UIView, scrollView: UIScrollView?) {
        self.metalView = view as? MTKView
        self.scrollView = scrollView
        
        // Layer manipulation gestures
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        view.addGestureRecognizer(panGesture)
        
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        view.addGestureRecognizer(pinchGesture)
        
        let rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
        view.addGestureRecognizer(rotationGesture)
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        view.addGestureRecognizer(tapGesture)
        
        // Enable simultaneous gestures
        panGesture.delegate = self
        pinchGesture.delegate = self
        rotationGesture.delegate = self
        tapGesture.delegate = self
    }
    
    // MARK: - Gesture Handlers
    
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let metalView = metalView,
              let canvas = canvas else { return }
        
        let location = gesture.location(in: metalView)
        
        // Hit test layers from top to bottom, skipping shadow layers
        for layer in canvas.layers.reversed() {
            // Skip shadow layers - they're not interactive
            if layer is ShadowLayer {
                continue
            }
            
            if layer.hitTest(point: location) {
                canvas.selectLayer(layer)
                canvas.needsDisplay = true
                onNeedsDisplay?()
                return
            }
        }
        
        // No layer hit, deselect
        canvas.selectLayer(nil)
        canvas.needsDisplay = true
        onNeedsDisplay?()
    }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let canvas = canvas,
              let metalView = metalView else { return }
        
        // If no layer is selected and gesture begins, try to select one
        if canvas.selectedLayer == nil && gesture.state == .began {
            let location = gesture.location(in: metalView)
            for layer in canvas.layers.reversed() {
                // Skip shadow layers - they're not interactive
                if layer is ShadowLayer {
                    continue
                }
                
                if layer.hitTest(point: location) {
                    canvas.selectLayer(layer)
                    break
                }
            }
        }
        
        guard let selectedLayer = canvas.selectedLayer else {
            // Let scroll view handle panning when no selection
            return
        }
        
        switch gesture.state {
        case .began:
            panStartLocation = selectedLayer.transform.position
            // Prevent scroll view from interfering
            scrollView?.isScrollEnabled = false
            
            // Begin undo capture
            undoStateCapture = canvas.createStateCapture(for: .transformLayer)
            undoStateCapture?.beginCapture()
            
        case .changed:
            let translation = gesture.translation(in: metalView)
            
            // Calculate new position
            var newPosition = CGPoint(
                x: panStartLocation.x + translation.x,
                y: panStartLocation.y + translation.y
            )
            
            // Find alignment guides
            activeGuides = alignmentEngine.findAlignmentGuides(
                for: selectedLayer,
                in: canvas.layers,
                canvasSize: metalView.bounds.size
            )
            
            // Snap to guides
            newPosition = alignmentEngine.snapPosition(newPosition, for: selectedLayer, guides: activeGuides)
            
            // Apply the snapped position
            selectedLayer.transform.position = newPosition
            
            // Update guide display
            updateGuideDisplay()
            onGuidesChanged?(activeGuides)
            
            canvas.setNeedsDisplay()
            onNeedsDisplay?()
            
        case .ended, .cancelled:
            // Hide guides when done
            activeGuides = []
            updateGuideDisplay()
            onGuidesChanged?([])
            
            // Re-enable scroll view after gesture
            scrollView?.isScrollEnabled = (canvas.selectedLayer == nil)
            
            // End undo capture
            undoStateCapture?.endCapture()
            undoStateCapture = nil
            
        default:
            break
        }
    }
    
    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let canvas = canvas,
              let selectedLayer = canvas.selectedLayer else { return }
        
        switch gesture.state {
        case .began:
            pinchStartScale = selectedLayer.transform.scale
            // Disable scroll view zoom
            scrollView?.pinchGestureRecognizer?.isEnabled = false
            
            // Begin undo capture
            undoStateCapture = canvas.createStateCapture(for: .transformLayer)
            undoStateCapture?.beginCapture()
            
        case .changed:
            selectedLayer.transform.scale = pinchStartScale * gesture.scale
            canvas.setNeedsDisplay()
            onNeedsDisplay?()
            
        case .ended, .cancelled:
            // Re-enable scroll view zoom if no selection
            scrollView?.pinchGestureRecognizer?.isEnabled = (canvas.selectedLayer == nil)
            
            // End undo capture
            undoStateCapture?.endCapture()
            undoStateCapture = nil
            
        default:
            break
        }
    }
    
    @objc private func handleRotation(_ gesture: UIRotationGestureRecognizer) {
        guard let canvas = canvas,
              let selectedLayer = canvas.selectedLayer else { return }
        
        switch gesture.state {
        case .began:
            rotationStartAngle = selectedLayer.transform.rotation
            
            // Begin undo capture
            undoStateCapture = canvas.createStateCapture(for: .transformLayer)
            undoStateCapture?.beginCapture()
            
        case .changed:
            selectedLayer.transform.rotation = rotationStartAngle + gesture.rotation
            canvas.setNeedsDisplay()
            onNeedsDisplay?()
            
        case .ended, .cancelled:
            // End undo capture
            undoStateCapture?.endCapture()
            undoStateCapture = nil
            
        default:
            break
        }
    }
    
    // MARK: - Helper Methods
    
    private func updateGuideDisplay() {
        // Remove existing guide layer
        guideLayer?.removeFromSuperlayer()
        
        guard !activeGuides.isEmpty, let metalView = metalView else {
            return
        }
        
        // Create new guide layer
        let newGuideLayer = guideRenderer.renderGuides(activeGuides, in: metalView)
        metalView.layer.addSublayer(newGuideLayer)
        guideLayer = newGuideLayer
    }
    
    func updateScrollViewInteraction() {
        guard let canvas = canvas else { return }
        
        // Update scroll view interaction based on selection
        scrollView?.isScrollEnabled = (canvas.selectedLayer == nil)
        scrollView?.pinchGestureRecognizer?.isEnabled = (canvas.selectedLayer == nil)
    }
}

// MARK: - UIGestureRecognizerDelegate

extension GestureCoordinator: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow pinch and rotation together on layers
        if (gestureRecognizer is UIPinchGestureRecognizer && otherGestureRecognizer is UIRotationGestureRecognizer) ||
           (gestureRecognizer is UIRotationGestureRecognizer && otherGestureRecognizer is UIPinchGestureRecognizer) {
            return true
        }
        
        guard let canvas = canvas else { return false }
        
        // When no layer is selected, allow scroll view gestures to work simultaneously
        if canvas.selectedLayer == nil {
            // Let our gestures work with scroll view gestures
            if otherGestureRecognizer.view is UIScrollView {
                return true
            }
            // Let scroll view gestures work with our gestures
            if gestureRecognizer.view is UIScrollView {
                return true
            }
        }
        
        return false
    }
    
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let canvas = canvas,
              let metalView = metalView else { return true }
        
        // For our gestures on the metal view
        if gestureRecognizer.view == metalView {
            // Pan gesture should only begin if we have a selected layer or will select one
            if gestureRecognizer is UIPanGestureRecognizer {
                if canvas.selectedLayer == nil {
                    // Check if we'll hit a layer with tap location
                    let location = gestureRecognizer.location(in: metalView)
                    for layer in canvas.layers.reversed() {
                        // Skip shadow layers - they're not interactive
                        if layer is ShadowLayer {
                            continue
                        }
                        
                        if layer.hitTest(point: location) {
                            return true // Will select this layer
                        }
                    }
                    return false // No layer to select, let scroll view handle it
                }
            }
            
            // Pinch and rotation only work with selected layer
            if gestureRecognizer is UIPinchGestureRecognizer || gestureRecognizer is UIRotationGestureRecognizer {
                return canvas.selectedLayer != nil
            }
        }
        
        return true
    }
}