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
        context.coordinator.setup()
        
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
        
        // Separated rendering and gesture handling
        private var renderer: MetalXRenderer?
        private var gestureCoordinator: GestureCoordinator?
        
        // Canvas transform for pan/zoom when no selection
        private var canvasOffset: CGPoint = .zero
        private var canvasScale: CGFloat = 1.0
        var lastCanvasSize: CGSize = .zero
        
        // Selection animation
        private var displayLink: CADisplayLink?
        private var startTime: CFTimeInterval = 0
        
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
            displayLink?.invalidate()
        }
        
        func setup() {
            guard let device = metalView?.device else { return }
            
            // Initialize renderer
            renderer = MetalXRenderer(device: device)
            
            // Initialize gesture coordinator
            gestureCoordinator = GestureCoordinator(canvas: canvas)
            
            // Setup gesture callbacks
            gestureCoordinator?.onNeedsDisplay = { [weak self] in
                self?.metalView?.setNeedsDisplay()
            }
            
            gestureCoordinator?.onGuidesChanged = { [weak self] guides in
                // Handle guide display updates if needed
            }
            
            // Setup gestures
            if let metalView = metalView, let scrollView = scrollView {
                gestureCoordinator?.setupGestures(for: metalView, scrollView: scrollView)
            }
            
            // Set initial scroll view state
            selectionChanged()
        }
        
        @objc private func selectionChanged() {
            // Update gesture coordinator
            gestureCoordinator?.updateScrollViewInteraction()
            
            // Update selection animation
            updateSelectionAnimation()
            
            // Force redraw to update selection rendering
            metalView?.setNeedsDisplay()
        }
        
        @objc private func canvasNeedsDisplay() {
            canvas.needsDisplay = true
            metalView?.setNeedsDisplay()
        }
        
        private func updateSelectionAnimation() {
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
        
        @objc private func animationTick() {
            metalView?.setNeedsDisplay()
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
        
        // MARK: - MTKViewDelegate
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            renderer?.updateDrawableSize(size)
        }
        
        func draw(in view: MTKView) {
            renderer?.render(canvas: canvas, in: view, selectedLayer: canvas.selectedLayer)
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
}