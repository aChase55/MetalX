import SwiftUI
import MetalKit
import Combine

// Canvas view that uses the Canvas model
struct CanvasView: UIViewRepresentable {
    @ObservedObject var canvas: Canvas
    
    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.delegate = context.coordinator
        mtkView.clearColor = MTLClearColor(
            red: Double(canvas.backgroundColor.components?[0] ?? 0.1),
            green: Double(canvas.backgroundColor.components?[1] ?? 0.1),
            blue: Double(canvas.backgroundColor.components?[2] ?? 0.1),
            alpha: Double(canvas.backgroundColor.components?[3] ?? 1.0)
        )
        
        // Disable automatic rendering - only render when needed
        mtkView.isPaused = true
        mtkView.enableSetNeedsDisplay = true
        
        // Store reference to view for manual rendering
        context.coordinator.metalView = mtkView
        
        // Add gesture recognizers
        context.coordinator.setupGestures(for: mtkView)
        
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        // Canvas will notify of changes through Combine
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(canvas: canvas)
    }
    
    class Coordinator: NSObject, MTKViewDelegate {
        let canvas: Canvas
        var device: MTLDevice?
        var commandQueue: MTLCommandQueue?
        var quadRenderer: QuadRenderer?
        weak var metalView: MTKView?
        
        // Gesture state
        var panStartLocation: CGPoint = .zero
        var pinchStartScale: CGFloat = 1.0
        var rotationStartAngle: CGFloat = 0
        
        // Combine subscriptions
        private var cancellables = Set<AnyCancellable>()
        
        init(canvas: Canvas) {
            self.canvas = canvas
            super.init()
            setupMetal()
            observeCanvas()
        }
        
        func setupMetal() {
            device = MTLCreateSystemDefaultDevice()
            commandQueue = device?.makeCommandQueue()
            if let device = device {
                quadRenderer = QuadRenderer(device: device)
            }
        }
        
        func observeCanvas() {
            // Observe canvas changes
            canvas.$layers
                .sink { [weak self] _ in
                    self?.setNeedsDisplay()
                }
                .store(in: &cancellables)
            
            canvas.$selectedLayer
                .sink { [weak self] _ in
                    self?.setNeedsDisplay()
                }
                .store(in: &cancellables)
        }
        
        func setNeedsDisplay() {
            metalView?.setNeedsDisplay()
        }
        
        func setupGestures(for view: UIView) {
            // Pan gesture
            let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            view.addGestureRecognizer(panGesture)
            
            // Pinch gesture
            let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            view.addGestureRecognizer(pinchGesture)
            
            // Rotation gesture
            let rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
            view.addGestureRecognizer(rotationGesture)
            
            // Tap gesture for selection
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            view.addGestureRecognizer(tapGesture)
            
            // Enable simultaneous gestures
            panGesture.delegate = self
            pinchGesture.delegate = self
            rotationGesture.delegate = self
            tapGesture.delegate = self
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            print("Tap at location: \(location)")
            
            // Hit test layers from top to bottom
            for layer in canvas.layers.reversed() {
                let hit = layer.hitTest(point: location)
                print("Testing layer \(layer.name): hit = \(hit), bounds = \(layer.bounds)")
                if hit {
                    print("Selected layer: \(layer.name)")
                    canvas.selectLayer(layer)
                    return
                }
            }
            
            // No layer hit, deselect
            print("No layer hit, deselecting")
            canvas.selectLayer(nil)
        }
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let selectedLayer = canvas.selectedLayer else { 
                print("Pan: No selected layer")
                return 
            }
            
            switch gesture.state {
            case .began:
                panStartLocation = selectedLayer.transform.position
                print("Pan began - start position: \(panStartLocation)")
            case .changed:
                let translation = gesture.translation(in: gesture.view)
                selectedLayer.transform.position = CGPoint(
                    x: panStartLocation.x + translation.x,
                    y: panStartLocation.y + translation.y
                )
                print("Pan changed - new position: \(selectedLayer.transform.position)")
                canvas.setNeedsDisplay()
                setNeedsDisplay()
            default:
                break
            }
        }
        
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let selectedLayer = canvas.selectedLayer else { return }
            
            switch gesture.state {
            case .began:
                pinchStartScale = selectedLayer.transform.scale
            case .changed:
                selectedLayer.transform.scale = pinchStartScale * gesture.scale
                canvas.setNeedsDisplay()
                setNeedsDisplay()
            default:
                break
            }
        }
        
        @objc func handleRotation(_ gesture: UIRotationGestureRecognizer) {
            guard let selectedLayer = canvas.selectedLayer else { return }
            
            switch gesture.state {
            case .began:
                rotationStartAngle = selectedLayer.transform.rotation
            case .changed:
                selectedLayer.transform.rotation = rotationStartAngle + CGFloat(gesture.rotation)
                canvas.setNeedsDisplay()
                setNeedsDisplay()
            default:
                break
            }
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            canvas.size = size
        }
        
        func draw(in view: MTKView) {
            // Only render if canvas needs display
            guard canvas.needsDisplay else { return }
            
            guard let drawable = view.currentDrawable,
                  let descriptor = view.currentRenderPassDescriptor else { return }
            
            guard let commandBuffer = commandQueue?.makeCommandBuffer() else { return }
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
            
            // Debug: log rendering
            print("Canvas rendering with \(canvas.layers.count) layers")
            
            // Render each layer
            for layer in canvas.layers {
                if layer.visible {
                    renderLayer(layer, encoder: encoder)
                }
            }
            
            encoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
            
            // Reset the canvas needs display flag
            canvas.needsDisplay = false
        }
        
        func renderLayer(_ layer: Layer, encoder: MTLRenderCommandEncoder) {
            // For now, just render image layers
            if let imageLayer = layer as? ImageLayer,
               let texture = imageLayer.texture {
                print("Rendering layer: \(layer.name) with texture: \(texture)")
                
                // Apply transform
                // TODO: Pass transform matrix to shader
                quadRenderer?.render(encoder: encoder, texture: texture)
                
                // Draw selection border if this is the selected layer
                if layer === canvas.selectedLayer {
                    // TODO: Draw selection border
                    print("TODO: Draw selection border for \(layer.name)")
                }
            } else {
                print("Skipping layer: \(layer.name) - no texture or not image layer")
            }
        }
    }
}

// Make coordinator conform to gesture delegate
extension CanvasView.Coordinator: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow pinch and rotation to work together
        if (gestureRecognizer is UIPinchGestureRecognizer && otherGestureRecognizer is UIRotationGestureRecognizer) ||
           (gestureRecognizer is UIRotationGestureRecognizer && otherGestureRecognizer is UIPinchGestureRecognizer) {
            return true
        }
        return false
    }
}