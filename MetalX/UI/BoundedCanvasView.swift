import SwiftUI
import MetalKit

struct BoundedCanvasView: UIViewRepresentable {
    @ObservedObject var canvas: Canvas
    
    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = UIColor.systemGray6
        
        // Create scroll view for pan/zoom
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 0.05
        scrollView.maximumZoomScale = 5.0
        scrollView.bouncesZoom = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = UIColor.systemGray6
        containerView.addSubview(scrollView)
        
        // Create canvas container view
        let canvasContainer = UIView()
        canvasContainer.backgroundColor = .white
        canvasContainer.layer.shadowColor = UIColor.black.cgColor
        canvasContainer.layer.shadowOpacity = 0.1
        canvasContainer.layer.shadowOffset = CGSize(width: 0, height: 2)
        canvasContainer.layer.shadowRadius = 10
        scrollView.addSubview(canvasContainer)
        
        // Create Metal view for rendering
        let metalView = MTKView()
        metalView.device = MTLCreateSystemDefaultDevice()
        metalView.delegate = context.coordinator
        metalView.enableSetNeedsDisplay = true
        metalView.isPaused = true
        metalView.clearColor = MTLClearColor(red: 1, green: 1, blue: 1, alpha: 1)
        metalView.translatesAutoresizingMaskIntoConstraints = false
        canvasContainer.addSubview(metalView)
        
        // Store references
        context.coordinator.scrollView = scrollView
        context.coordinator.canvasContainer = canvasContainer
        context.coordinator.metalView = metalView
        context.coordinator.setupQuadRenderer()
        context.coordinator.setupGestures(for: metalView)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            
            metalView.topAnchor.constraint(equalTo: canvasContainer.topAnchor),
            metalView.leadingAnchor.constraint(equalTo: canvasContainer.leadingAnchor),
            metalView.trailingAnchor.constraint(equalTo: canvasContainer.trailingAnchor),
            metalView.bottomAnchor.constraint(equalTo: canvasContainer.bottomAnchor)
        ])
        
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Only update canvas size if it actually changed
        if context.coordinator.lastCanvasSize != canvas.size {
            context.coordinator.lastCanvasSize = canvas.size
            DispatchQueue.main.async {
                context.coordinator.updateCanvasSize()
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(canvas: canvas)
    }
    
    class Coordinator: NSObject, MTKViewDelegate, UIScrollViewDelegate {
        let canvas: Canvas
        weak var scrollView: UIScrollView?
        weak var canvasContainer: UIView?
        weak var metalView: MTKView?
        
        private var commandQueue: MTLCommandQueue?
        private var quadRenderer: QuadRenderer?
        
        // Gesture handling
        private var panStartLocation: CGPoint = .zero
        private var pinchStartScale: CGFloat = 1.0
        private var rotationStartAngle: CGFloat = 0.0
        
        // Canvas transform for pan/zoom when no selection
        private var canvasOffset: CGPoint = .zero
        private var canvasScale: CGFloat = 1.0
        var lastCanvasSize: CGSize = .zero
        
        // Alignment guides
        private var alignmentEngine = AlignmentEngine()
        private var guideRenderer = GuideRenderer()
        private var activeGuides: [AlignmentGuide] = []
        private weak var guideLayer: CALayer?
        
        init(canvas: Canvas) {
            self.canvas = canvas
            super.init()
            
            // Observe selection changes
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(selectionChanged),
                name: NSNotification.Name("CanvasSelectionChanged"),
                object: nil
            )
            
            // Observe canvas needs display
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(canvasNeedsDisplay),
                name: NSNotification.Name("CanvasNeedsDisplay"),
                object: nil
            )
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
        
        @objc private func selectionChanged() {
            // Update scroll view interaction based on selection
            scrollView?.isScrollEnabled = (canvas.selectedLayer == nil)
            scrollView?.pinchGestureRecognizer?.isEnabled = (canvas.selectedLayer == nil)
            
            // Force redraw to update selection rendering
            metalView?.setNeedsDisplay()
        }
        
        @objc private func canvasNeedsDisplay() {
            canvas.needsDisplay = true
            metalView?.setNeedsDisplay()
        }
        
        func setupQuadRenderer() {
            guard let device = metalView?.device else { return }
            quadRenderer = QuadRenderer(device: device)
            commandQueue = device.makeCommandQueue()
            
            // Set initial scroll view state
            selectionChanged()
        }
        
        func updateCanvasSize() {
            guard let scrollView = scrollView,
                  let canvasContainer = canvasContainer else { return }
            
            // Set canvas container size based on canvas dimensions
            let canvasSize = canvas.size
            canvasContainer.frame = CGRect(origin: .zero, size: canvasSize)
            
            // Update scroll view content size
            scrollView.contentSize = canvasSize
            
            // Only center canvas on initial load
            if !hasInitializedCanvas && scrollView.bounds.size.width > 0 {
                hasInitializedCanvas = true
                DispatchQueue.main.async { [weak self] in
                    self?.centerCanvas()
                }
            }
            
            metalView?.setNeedsDisplay()
        }
        
        private var hasInitializedCanvas = false
        
        func centerCanvas() {
            guard let scrollView = scrollView,
                  scrollView.bounds.size.width > 0,
                  scrollView.bounds.size.height > 0 else { return }
            
            let canvasSize = canvas.size
            let scrollViewSize = scrollView.bounds.size
            
            // Ensure canvas has valid size
            guard canvasSize.width > 0 && canvasSize.height > 0 else { return }
            
            // Add padding around canvas
            let padding: CGFloat = 40
            let paddedCanvasWidth = canvasSize.width + padding * 2
            let paddedCanvasHeight = canvasSize.height + padding * 2
            
            // Calculate zoom to fit entire canvas with padding
            let scaleX = scrollViewSize.width / paddedCanvasWidth
            let scaleY = scrollViewSize.height / paddedCanvasHeight
            let scale = min(scaleX, scaleY) // Use min to ensure entire canvas fits
            
            // Apply zoom
            scrollView.zoomScale = scale
            
            // Calculate content insets to center the canvas
            let scaledWidth = canvasSize.width * scale
            let scaledHeight = canvasSize.height * scale
            let horizontalInset = max((scrollViewSize.width - scaledWidth) / 2, 0)
            let verticalInset = max((scrollViewSize.height - scaledHeight) / 2, 0)
            
            // Set content insets to center the canvas
            scrollView.contentInset = UIEdgeInsets(
                top: verticalInset,
                left: horizontalInset,
                bottom: verticalInset,
                right: horizontalInset
            )
            
            // Reset content offset to show centered canvas
            scrollView.contentOffset = CGPoint(x: -horizontalInset, y: -verticalInset)
        }
        
        // MARK: - UIScrollViewDelegate
        
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return canvasContainer
        }
        
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            // Keep canvas centered while zooming
            guard let canvasContainer = canvasContainer else { return }
            
            let scrollViewSize = scrollView.bounds.size
            let scaledWidth = canvasContainer.frame.width * scrollView.zoomScale
            let scaledHeight = canvasContainer.frame.height * scrollView.zoomScale
            
            let horizontalInset = max((scrollViewSize.width - scaledWidth) / 2, 0)
            let verticalInset = max((scrollViewSize.height - scaledHeight) / 2, 0)
            
            scrollView.contentInset = UIEdgeInsets(
                top: verticalInset,
                left: horizontalInset,
                bottom: verticalInset,
                right: horizontalInset
            )
            
            // Update layer rendering scale if needed
            metalView?.setNeedsDisplay()
        }
        
        // MARK: - Gesture Handling
        
        func setupGestures(for view: UIView) {
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
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let metalView = metalView else { return }
            let location = gesture.location(in: metalView)
            
            // Hit test layers - location is already in canvas coordinates since metalView is scaled
            for layer in canvas.layers.reversed() {
                if layer.hitTest(point: location) {
                    canvas.selectLayer(layer)
                    // Just update display, don't trigger layout
                    canvas.needsDisplay = true
                    return
                }
            }
            
            // No layer hit, deselect
            canvas.selectLayer(nil)
            canvas.needsDisplay = true
        }
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard canvas.selectedLayer != nil else { 
                // Let scroll view handle panning when no selection
                return 
            }
            
            if let selectedLayer = canvas.selectedLayer {
                // Move selected layer
                switch gesture.state {
                case .began:
                    panStartLocation = selectedLayer.transform.position
                    // Prevent scroll view from interfering
                    scrollView?.isScrollEnabled = false
                case .changed:
                    // Get the translation in the metalView's coordinate system (which is inside the scroll view)
                    guard let metalView = metalView else { return }
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
                    
                    canvas.setNeedsDisplay()
                    metalView.setNeedsDisplay()
                case .ended, .cancelled:
                    // Hide guides when done
                    activeGuides = []
                    updateGuideDisplay()
                    
                    // Re-enable scroll view after gesture
                    scrollView?.isScrollEnabled = (canvas.selectedLayer == nil)
                default:
                    break
                }
            }
        }
        
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let selectedLayer = canvas.selectedLayer else { return }
            
            switch gesture.state {
            case .began:
                pinchStartScale = selectedLayer.transform.scale
                // Disable scroll view zoom
                scrollView?.pinchGestureRecognizer?.isEnabled = false
            case .changed:
                selectedLayer.transform.scale = pinchStartScale * gesture.scale
                canvas.setNeedsDisplay()
                metalView?.setNeedsDisplay()
            case .ended, .cancelled:
                // Re-enable scroll view zoom if no selection
                scrollView?.pinchGestureRecognizer?.isEnabled = (canvas.selectedLayer == nil)
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
                selectedLayer.transform.rotation = rotationStartAngle + gesture.rotation
                canvas.setNeedsDisplay()
                metalView?.setNeedsDisplay()
            default:
                break
            }
        }
        
        private func convertToCanvasCoordinates(_ viewPoint: CGPoint) -> CGPoint {
            // Convert from view coordinates to canvas coordinates
            let scale = scrollView?.zoomScale ?? 1.0
            return CGPoint(
                x: viewPoint.x / scale,
                y: viewPoint.y / scale
            )
        }
        
        // MARK: - MTKViewDelegate
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // Canvas size is fixed, not dependent on view size
        }
        
        func draw(in view: MTKView) {
            guard canvas.needsDisplay else { return }
            
            guard let drawable = view.currentDrawable,
                  let descriptor = view.currentRenderPassDescriptor,
                  let commandBuffer = commandQueue?.makeCommandBuffer(),
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
            
            // Render each layer
            for layer in canvas.layers {
                if layer.isVisible {
                    renderLayer(layer, encoder: encoder)
                }
            }
            
            // Draw selection if needed
            if let selectedLayer = canvas.selectedLayer {
                renderSelection(for: selectedLayer, encoder: encoder)
            }
            
            encoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
            
            canvas.needsDisplay = false
        }
        
        private func renderLayer(_ layer: any Layer, encoder: MTLRenderCommandEncoder) {
            // Get layer texture
            var texture: MTLTexture? = nil
            
            if let imageLayer = layer as? ImageLayer {
                texture = imageLayer.texture
            } else if let textLayer = layer as? TextLayer {
                texture = textLayer.texture
            } else if let shapeLayer = layer as? VectorShapeLayer {
                if let metalDevice = try? MetalDevice(preferredDevice: metalView!.device!) {
                    let context = RenderContext(device: metalDevice)
                    texture = shapeLayer.render(context: context)
                }
            }
            
            if let texture = texture {
                let transform = calculateTransformMatrix(for: layer)
                quadRenderer?.render(encoder: encoder, texture: texture, transform: transform)
            }
        }
        
        private func renderSelection(for layer: any Layer, encoder: MTLRenderCommandEncoder) {
            let time = Float(CACurrentMediaTime())
            let transform = calculateTransformMatrix(for: layer)
            quadRenderer?.renderSelection(
                encoder: encoder,
                transform: transform,
                viewportSize: metalView?.bounds.size ?? .zero,
                time: time
            )
        }
        
        private func calculateTransformMatrix(for layer: any Layer) -> simd_float4x4 {
            // Transform from canvas space to NDC
            let canvasSize = canvas.size
            let transform = layer.transform
            let layerSize = layer.bounds.size
            
            // Scale to convert from canvas coordinates to NDC
            let pixelToNDC = simd_float2(2.0 / Float(canvasSize.width), -2.0 / Float(canvasSize.height))
            
            // Calculate position in NDC space
            let centerX = Float(transform.position.x)
            let centerY = Float(transform.position.y)
            
            // Layer dimensions in canvas space
            let halfWidth = Float(layerSize.width * transform.scale) * 0.5
            let halfHeight = Float(layerSize.height * transform.scale) * 0.5
            
            // Build transform matrix
            var matrix = matrix_identity_float4x4
            
            // Apply rotation
            let angle = Float(transform.rotation)
            let cos_r = cos(angle)
            let sin_r = sin(angle)
            
            // Scale and rotate
            matrix.columns.0.x = cos_r * halfWidth * pixelToNDC.x
            matrix.columns.0.y = sin_r * halfWidth * pixelToNDC.y
            matrix.columns.1.x = -sin_r * halfHeight * pixelToNDC.x
            matrix.columns.1.y = cos_r * halfHeight * pixelToNDC.y
            
            // Translation (convert from canvas center to NDC)
            matrix.columns.3.x = (centerX - Float(canvasSize.width) * 0.5) * pixelToNDC.x
            matrix.columns.3.y = (centerY - Float(canvasSize.height) * 0.5) * pixelToNDC.y
            
            return matrix
        }
    }
}

// MARK: - Gesture Delegate

extension BoundedCanvasView.Coordinator: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow pinch and rotation together on layers
        if (gestureRecognizer is UIPinchGestureRecognizer && otherGestureRecognizer is UIRotationGestureRecognizer) ||
           (gestureRecognizer is UIRotationGestureRecognizer && otherGestureRecognizer is UIPinchGestureRecognizer) {
            return true
        }
        
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
        // For our gestures on the metal view
        if gestureRecognizer.view == metalView {
            // Pan gesture should only begin if we have a selected layer or will select one
            if gestureRecognizer is UIPanGestureRecognizer {
                if canvas.selectedLayer == nil {
                    // Check if we'll hit a layer with tap location
                    let location = gestureRecognizer.location(in: metalView)
                    for layer in canvas.layers.reversed() {
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
    
    // MARK: - Alignment Guide Display
    
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
}