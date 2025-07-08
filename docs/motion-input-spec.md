# Motion and Input System Specification

## Overview
A comprehensive system for handling device motion, gesture input, and motion-responsive effects, enabling intuitive interaction and dynamic visual responses.

## Device Motion Integration

### 1. Motion Manager

```swift
class MotionManager {
    private let motionManager = CMMotionManager()
    private let queue = OperationQueue()
    
    // Motion data streams
    struct MotionData {
        var attitude: CMAttitude
        var rotationRate: CMRotationRate
        var gravity: CMAcceleration
        var userAcceleration: CMAcceleration
        var magneticField: CMCalibratedMagneticField
    }
    
    // Motion tracking configuration
    struct MotionConfig {
        var updateInterval: TimeInterval = 1.0/60.0
        var referenceFrame: CMAttitudeReferenceFrame = .xArbitraryZVertical
        var smoothingFactor: Float = 0.8
        var noiseThreshold: Float = 0.01
    }
    
    // Start motion updates
    func startMotionUpdates(handler: @escaping (MotionData) -> Void) {
        guard motionManager.isDeviceMotionAvailable else { return }
        
        motionManager.deviceMotionUpdateInterval = config.updateInterval
        motionManager.startDeviceMotionUpdates(
            using: config.referenceFrame,
            to: queue
        ) { [weak self] motion, error in
            guard let motion = motion else { return }
            
            let data = self?.processMotionData(motion)
            DispatchQueue.main.async {
                handler(data)
            }
        }
    }
}
```

### 2. Motion-Responsive Effects

```swift
class MotionResponsiveEffects {
    // Parallax effect
    class ParallaxEffect {
        var layers: [ParallaxLayer] = []
        var sensitivity: Float = 1.0
        var maxOffset: CGSize = CGSize(width: 50, height: 50)
        
        struct ParallaxLayer {
            var content: MTLTexture
            var depth: Float // 0 = background, 1 = foreground
            var scale: Float = 1.0
            var rotationSensitivity: Float = 0.0
        }
        
        func update(motion: MotionData) {
            for (index, layer) in layers.enumerated() {
                let offset = calculateOffset(
                    motion: motion,
                    depth: layer.depth
                )
                
                // Smooth interpolation
                layer.currentOffset = mix(
                    layer.currentOffset,
                    offset,
                    smoothingFactor
                )
            }
        }
    }
    
    // Tilt-shift effect
    class TiltShiftEffect {
        var focusAngle: Float = 0.0
        var blurGradient: GradientRange
        var motionInfluence: Float = 0.5
        
        func updateFocus(motion: MotionData) {
            let tiltAngle = atan2(motion.gravity.x, motion.gravity.y)
            focusAngle = mix(focusAngle, tiltAngle, motionInfluence)
            
            // Update shader parameters
            shaderParams.focusAngle = focusAngle
            shaderParams.blurAmount = calculateBlur(angle: focusAngle)
        }
    }
    
    // Gyroscope-driven particles
    class GyroParticles {
        var particleSystem: ParticleSystem
        var responseStrength: Float = 1.0
        var lagFactor: Float = 0.1
        
        func update(motion: MotionData) {
            // Convert rotation to force
            let force = SIMD3<Float>(
                Float(motion.rotationRate.x) * responseStrength,
                Float(motion.rotationRate.y) * responseStrength,
                Float(motion.rotationRate.z) * responseStrength
            )
            
            particleSystem.addForce(force)
            
            // Tilt gravity
            particleSystem.gravity = SIMD3<Float>(
                Float(motion.gravity.x) * 9.8,
                Float(motion.gravity.y) * 9.8,
                Float(motion.gravity.z) * 9.8
            )
        }
    }
}
```

### 3. Gesture Recognition System

```swift
class GestureSystem {
    // Enhanced gesture recognizers
    class EnhancedPanGesture: UIPanGestureRecognizer {
        var velocity: CGPoint { get }
        var acceleration: CGPoint { get }
        var predictedEndpoint: CGPoint { get }
        
        // Gesture curves
        func velocityCurve() -> AnimationCurve
        func pressureCurve() -> AnimationCurve // For 3D Touch/Force Touch
    }
    
    // Multi-touch gestures
    class MultiTouchGesture {
        var touches: [UITouch] = []
        var center: CGPoint { get }
        var spread: Float { get }
        var angle: Float { get }
        
        // Complex gestures
        enum GestureType {
            case pinchRotate(scale: Float, rotation: Float)
            case threeFingersSwipe(direction: Direction)
            case fourFingersExpand
            case fiveFingersScrunch
        }
    }
    
    // Gesture combinations
    class GestureCombiner {
        func combine(_ gestures: [UIGestureRecognizer]) -> CombinedGesture
        func sequence(_ gestures: [UIGestureRecognizer], 
                     timeWindow: TimeInterval) -> GestureSequence
    }
}
```

### 4. Scrubbing and Timeline Control

```swift
class ScrubController {
    // Precision scrubbing (inspired by Riveo)
    struct ScrubState {
        var position: Float
        var velocity: Float
        var isDragging: Bool
        var detents: [Float] = [] // Snap points
        var hapticFeedback: Bool = true
    }
    
    // Scrub modes
    enum ScrubMode {
        case linear
        case logarithmic // Fine control at slow speeds
        case magnetic(snapStrength: Float) // Snap to keyframes
        case jog(wheelSensitivity: Float) // Jog wheel style
    }
    
    // Advanced scrubbing
    func handleScrub(gesture: UIPanGestureRecognizer) {
        let velocity = gesture.velocity(in: view)
        let acceleration = calculateAcceleration(from: velocityHistory)
        
        // Adaptive sensitivity
        let sensitivity = calculateSensitivity(
            velocity: velocity,
            acceleration: acceleration
        )
        
        // Update position with inertia
        scrubState.position += delta * sensitivity
        
        // Magnetic snapping
        if let nearestDetent = findNearestDetent(scrubState.position) {
            if shouldSnap(to: nearestDetent, velocity: velocity) {
                animateSnap(to: nearestDetent)
                provideHapticFeedback(.light)
            }
        }
        
        // Update preview
        updatePreview(at: scrubState.position)
    }
}
```

### 5. Haptic Feedback System

```swift
class HapticSystem {
    private let impactGenerator = UIImpactFeedbackGenerator()
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let notificationGenerator = UINotificationFeedbackGenerator()
    
    // Custom haptic patterns
    struct HapticPattern {
        var events: [HapticEvent]
        var delay: TimeInterval
        
        struct HapticEvent {
            var intensity: Float
            var sharpness: Float
            var duration: TimeInterval
        }
    }
    
    // Context-aware haptics
    func provideContextualFeedback(for action: UserAction) {
        switch action {
        case .effectApplied:
            impactGenerator.impactOccurred(intensity: 0.7)
        case .keyframeReached:
            selectionGenerator.selectionChanged()
        case .exportComplete:
            notificationGenerator.notificationOccurred(.success)
        case .gestureRecognized(let type):
            playCustomPattern(for: type)
        }
    }
    
    // Haptic curves synchronized with animations
    func syncHapticsWithAnimation(_ animation: CAAnimation) {
        // Generate haptic events based on animation curve
        let hapticCurve = animation.timingFunction.hapticCurve()
        playHapticCurve(hapticCurve, duration: animation.duration)
    }
}
```

### 6. Pressure-Sensitive Input

```swift
class PressureInput {
    // 3D Touch / Force Touch support
    struct PressureData {
        var force: Float
        var maximumPossibleForce: Float
        var normalizedForce: Float { force / maximumPossibleForce }
    }
    
    // Pressure-based tools
    class PressureBrush {
        var baseSi7ze: Float = 10.0
        var pressureMultiplier: Float = 2.0
        var opacityCurve: AnimationCurve
        
        func calculateBrushAttributes(pressure: PressureData) -> BrushAttributes {
            return BrushAttributes(
                size: baseSize * (1 + pressure.normalizedForce * pressureMultiplier),
                opacity: opacityCurve.evaluate(at: pressure.normalizedForce),
                flow: calculateFlow(pressure: pressure),
                softness: calculateSoftness(pressure: pressure)
            )
        }
    }
    
    // Pressure gestures
    class PressureGesture {
        enum PressureLevel {
            case light(threshold: Float = 0.2)
            case medium(threshold: Float = 0.5)
            case firm(threshold: Float = 0.8)
            case pop // When pressure exceeds maximum
        }
        
        var onPressureChange: ((PressureLevel) -> Void)?
        var onPop: (() -> Void)?
    }
}
```

### 7. Apple Pencil Integration

```swift
class PencilInput {
    // Pencil properties
    struct PencilState {
        var position: CGPoint
        var force: Float
        var azimuth: Float
        var altitude: Float
        var barrel: Bool // Pencil 2 double-tap
        var estimatedProperties: Set<UITouch.Properties>
    }
    
    // Pencil-specific effects
    class PencilEffects {
        // Tilt shading
        func calculateTiltShading(altitude: Float, azimuth: Float) -> ShaderParams {
            let tiltAmount = 1.0 - (altitude / (.pi / 2))
            let tiltDirection = SIMD2<Float>(cos(azimuth), sin(azimuth))
            
            return ShaderParams(
                tiltAmount: tiltAmount,
                tiltDirection: tiltDirection,
                shadingIntensity: tiltAmount * 0.5
            )
        }
        
        // Pencil hovering (iOS 12.1+)
        func handleHover(at point: CGPoint, height: Float) {
            // Show preview of effect
            // Adjust UI elements
            // Prepare resources
        }
    }
}
```

### 8. Spatial Input (AR/VR Ready)

```swift
class SpatialInput {
    // 6DOF tracking
    struct SpatialTransform {
        var position: SIMD3<Float>
        var rotation: simd_quatf
        var scale: Float = 1.0
    }
    
    // Hand tracking preparation
    struct HandPose {
        var joints: [JointType: SIMD3<Float>]
        var gestures: Set<HandGesture>
        
        enum HandGesture {
            case pinch(strength: Float)
            case point(direction: SIMD3<Float>)
            case grab
            case release
            case swipe(direction: SIMD3<Float>)
        }
    }
    
    // Spatial gestures
    func recognizeSpatialGesture(handPoses: [HandPose]) -> SpatialGesture? {
        // Two-handed gestures
        // Complex spatial manipulations
        // Context-aware interactions
    }
}
```

### 9. Accessibility Input

```swift
class AccessibilityInput {
    // Voice control
    struct VoiceCommand {
        var text: String
        var intent: CommandIntent
        var parameters: [String: Any]
    }
    
    // Switch control support
    class SwitchControl {
        var scanningMode: ScanningMode
        var dwellTime: TimeInterval
        var audioFeedback: Bool
        
        func handleSwitchActivation() {
            // Navigate UI elements
            // Activate controls
            // Provide feedback
        }
    }
    
    // Head tracking (iOS 13+)
    class HeadTracking {
        func calibrate() async
        func trackHead() -> AsyncStream<HeadPose>
        func mapToPointer(headPose: HeadPose) -> CGPoint
    }
}
```

### 10. Input Prediction and Smoothing

```swift
class InputPredictor {
    // Kalman filter for smooth input
    class KalmanFilter {
        private var x: SIMD2<Float> // State
        private var P: matrix_float2x2 // Error covariance
        
        func predict(measurement: CGPoint) -> CGPoint {
            // Prediction step
            x = F * x
            P = F * P * transpose(F) + Q
            
            // Update step
            let y = measurement - H * x
            let S = H * P * transpose(H) + R
            let K = P * transpose(H) * inverse(S)
            
            x = x + K * y
            P = (I - K * H) * P
            
            return CGPoint(x: x.x, y: x.y)
        }
    }
    
    // Touch prediction for low latency
    func predictTouch(history: [TouchEvent], 
                     latency: TimeInterval) -> CGPoint {
        // Polynomial extrapolation
        // Velocity-based prediction
        // Acceleration consideration
    }
}
```

## Integration Examples

```swift
// Motion-responsive parallax
let parallax = ParallaxEffect()
motionManager.startMotionUpdates { motion in
    parallax.update(motion: motion)
    renderView.setNeedsDisplay()
}

// Pressure-sensitive drawing
let brush = PressureBrush()
renderView.addGestureRecognizer(PressureGesture { level in
    brush.updatePressure(level)
})

// Advanced scrubbing with haptics
let scrubber = ScrubController()
scrubber.onPositionChange = { position in
    timeline.seek(to: position)
    haptics.provideContextualFeedback(for: .scrub)
}
```