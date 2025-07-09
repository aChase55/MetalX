import SwiftUI
import MetalKit
import Combine
import simd

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
        
        // Animation
        var displayLink: CADisplayLink?
        var startTime: CFTimeInterval = 0
        
        // Alignment
        let alignmentEngine = AlignmentEngine()
        let guideRenderer = GuideRenderer()
        var guideLayer: CALayer?
        var activeGuides: [AlignmentGuide] = []
        
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
                    self?.updateSelectionAnimation()
                }
                .store(in: &cancellables)
        }
        
        func updateSelectionAnimation() {
            if canvas.selectedLayer != nil {
                // Start animation if not running
                if displayLink == nil {
                    startTime = CACurrentMediaTime()
                    displayLink = CADisplayLink(target: self, selector: #selector(animationTick))
                    displayLink?.add(to: .main, forMode: .common)
                }
            } else {
                // Stop animation
                displayLink?.invalidate()
                displayLink = nil
            }
        }
        
        @objc func animationTick() {
            setNeedsDisplay()
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
            
            // Hit test layers from top to bottom
            for layer in canvas.layers.reversed() {
                let hit = layer.hitTest(point: location)
                if hit {
                    canvas.selectLayer(layer)
                    return
                }
            }
            
            // No layer hit, deselect
            canvas.selectLayer(nil)
        }
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            // If no layer is selected, try to select one under the touch point
            if canvas.selectedLayer == nil && gesture.state == .began {
                let location = gesture.location(in: gesture.view)
                for layer in canvas.layers.reversed() {
                    if layer.hitTest(point: location) {
                        canvas.selectLayer(layer)
                        break
                    }
                }
            }
            
            guard let selectedLayer = canvas.selectedLayer else { 
                return 
            }
            
            switch gesture.state {
            case .began:
                panStartLocation = selectedLayer.transform.position
                print("Pan gesture started - initial position: \(panStartLocation)")
            case .changed:
                let translation = gesture.translation(in: gesture.view)
                var newPosition = CGPoint(
                    x: panStartLocation.x + translation.x,
                    y: panStartLocation.y + translation.y
                )
                
                // Find alignment guides
                activeGuides = alignmentEngine.findAlignmentGuides(
                    for: selectedLayer,
                    in: canvas.layers,
                    canvasSize: metalView?.bounds.size ?? CGSize(width: 1024, height: 1024)
                )
                
                // Snap to guides
                newPosition = alignmentEngine.snapPosition(newPosition, for: selectedLayer, guides: activeGuides)
                
                selectedLayer.transform.position = newPosition
                
                // Update guide display
                updateGuideDisplay()
                
                canvas.setNeedsDisplay()
                setNeedsDisplay()
            case .ended, .cancelled:
                print("Pan gesture ended - final position: \(selectedLayer.transform.position)")
                // Hide guides when done
                activeGuides = []
                updateGuideDisplay()
            default:
                break
            }
        }
        
        func updateGuideDisplay() {
            guideLayer?.removeFromSuperlayer()
            
            if !activeGuides.isEmpty, let metalView = metalView {
                guideLayer = guideRenderer.renderGuides(activeGuides, in: metalView)
                metalView.layer.addSublayer(guideLayer!)
            }
        }
        
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let selectedLayer = canvas.selectedLayer else { return }
            
            switch gesture.state {
            case .began:
                pinchStartScale = selectedLayer.transform.scale
                print("Pinch gesture started - initial scale: \(pinchStartScale)")
            case .changed:
                selectedLayer.transform.scale = pinchStartScale * gesture.scale
                canvas.setNeedsDisplay()
                setNeedsDisplay()
            case .ended, .cancelled:
                print("Pinch gesture ended - final scale: \(selectedLayer.transform.scale)")
            default:
                break
            }
        }
        
        @objc func handleRotation(_ gesture: UIRotationGestureRecognizer) {
            guard let selectedLayer = canvas.selectedLayer else { return }
            
            switch gesture.state {
            case .began:
                rotationStartAngle = selectedLayer.transform.rotation
                print("Rotation gesture started - initial angle: \(rotationStartAngle)")
            case .changed:
                // Use positive rotation for correct direction
                selectedLayer.transform.rotation = rotationStartAngle + CGFloat(gesture.rotation)
                canvas.setNeedsDisplay()
                setNeedsDisplay()
            case .ended, .cancelled:
                print("Rotation gesture ended - final angle: \(selectedLayer.transform.rotation)")
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
            
            // Render each layer
            for layer in canvas.layers {
                if layer.isVisible {
                    renderLayer(layer, encoder: encoder)
                }
            }
            
            encoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
            
            // Reset the canvas needs display flag
            canvas.needsDisplay = false
        }
        
        func renderLayer(_ layer: any Layer, encoder: MTLRenderCommandEncoder) {
            var texture: MTLTexture?
            
            // Get texture from different layer types
            if let imageLayer = layer as? ImageLayer {
                texture = imageLayer.texture
            } else if let textLayer = layer as? TextLayer {
                texture = textLayer.texture
            } else if let shapeLayer = layer as? VectorShapeLayer {
                // Shape layers render themselves - just get their texture
                // The shape layer handles its own render context internally
                print("\nCanvasView: Rendering shape layer '\(shapeLayer.name)'")
                print("  Layer bounds: \(shapeLayer.bounds)")
                print("  Layer transform: pos=\(shapeLayer.transform.position), scale=\(shapeLayer.transform.scale)")
                
                if let metalDevice = try? MetalDevice(preferredDevice: device) {
                    let context = RenderContext(device: metalDevice)
                    texture = shapeLayer.render(context: context)
                    
                    if let texture = texture {
                        print("  Got texture: \(texture.width)x\(texture.height)")
                    } else {
                        print("  No texture returned!")
                    }
                }
            }
            
            if let texture = texture {
                
                // Calculate transform matrix
                let transform = calculateTransformMatrix(for: layer, canvasSize: metalView?.bounds.size ?? CGSize(width: 1024, height: 1024))
                
                // Render the layer first
                quadRenderer?.render(encoder: encoder, texture: texture, transform: transform)
                
                // Draw selection border ON TOP of the layer if this is the selected layer
                if layer === canvas.selectedLayer {
                    let time = Float(CACurrentMediaTime() - startTime)
                    
                    // Use exact same transform as the layer (no scaling)
                    quadRenderer?.renderSelection(
                        encoder: encoder,
                        transform: transform,
                        viewportSize: metalView?.bounds.size ?? CGSize(width: 1024, height: 1024),
                        time: time
                    )
                }
            } else {
                // Skipping layer - no texture available
            }
        }
        
        func calculateTransformMatrix(for layer: any Layer, canvasSize: CGSize) -> simd_float4x4 {
            // Convert from screen coordinates to NDC (-1 to 1)
            let transform = layer.transform
            
            // Get layer size
            let layerSize = layer.bounds.size
            
            // Scale to convert from pixel coordinates to NDC
            let pixelToNDC = simd_float2(2.0 / Float(canvasSize.width), -2.0 / Float(canvasSize.height))
            
            // Calculate position in NDC space
            let centerX = Float(transform.position.x)
            let centerY = Float(transform.position.y)
            
            // Layer dimensions in pixels
            let halfWidth = Float(layerSize.width * transform.scale) * 0.5
            let halfHeight = Float(layerSize.height * transform.scale) * 0.5
            
            // Create transform matrix: Translation * Rotation * Scale
            var matrix = matrix_identity_float4x4
            
            // Apply rotation
            let angle = Float(transform.rotation)
            let cos_r = cos(angle)
            let sin_r = sin(angle)
            
            // Build the complete transform
            // Note: We build this carefully to avoid skewing
            matrix.columns.0.x = cos_r * halfWidth * pixelToNDC.x
            matrix.columns.0.y = sin_r * halfWidth * pixelToNDC.y
            
            matrix.columns.1.x = -sin_r * halfHeight * pixelToNDC.x
            matrix.columns.1.y = cos_r * halfHeight * pixelToNDC.y
            
            // Translation (convert from screen center to NDC)
            matrix.columns.3.x = (centerX - Float(canvasSize.width) * 0.5) * pixelToNDC.x
            matrix.columns.3.y = (centerY - Float(canvasSize.height) * 0.5) * pixelToNDC.y
            
            return matrix
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