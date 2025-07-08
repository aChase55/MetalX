# API Design Specification

## Overview
The API provides a clean, intuitive interface for developers while hiding the complexity of the underlying Metal rendering engine. It follows Swift best practices with a focus on type safety, protocol-oriented design, and progressive disclosure.

## Core API Structure

### 1. RenderEngine API

```swift
public class RenderEngine {
    // MARK: - Initialization
    public init(configuration: EngineConfiguration = .default) throws
    
    // MARK: - Image Processing
    public func process(image: UIImage, 
                       with recipe: Recipe) async throws -> ProcessedImage
    
    public func process(imageAt url: URL,
                       with recipe: Recipe,
                       progress: ProgressHandler?) async throws -> ProcessedImage
    
    // MARK: - Video Processing  
    public func process(video: AVAsset,
                       timeline: Timeline) async throws -> ProcessedVideo
    
    public func createTimeline(from assets: [AVAsset]) -> TimelineBuilder
    
    // MARK: - Real-time Preview
    public func startPreview(source: MediaSource,
                           in view: RenderView,
                           quality: PreviewQuality = .balanced)
    
    public func updatePreview(with recipe: Recipe)
    
    // MARK: - Resource Management
    public var memoryBudget: MemoryBudget { get set }
    public func purgeCache(level: CacheLevel = .automatic)
}
```

### 2. Recipe Builder API

```swift
public struct Recipe {
    // MARK: - Creation
    public init()
    public static func from(preset: Preset) -> Recipe
    
    // MARK: - Basic Adjustments
    public func exposure(_ value: Float) -> Recipe
    public func contrast(_ value: Float) -> Recipe
    public func saturation(_ value: Float) -> Recipe
    public func temperature(_ value: Float) -> Recipe
    
    // MARK: - Advanced Adjustments
    public func curves(_ curves: Curves) -> Recipe
    public func colorGrading(_ grading: ColorGrading) -> Recipe
    public func selectiveColor(_ adjustments: SelectiveColorAdjustments) -> Recipe
    
    // MARK: - Effects
    public func blur(_ type: BlurType, amount: Float) -> Recipe
    public func sharpen(_ settings: SharpenSettings) -> Recipe
    public func vignette(_ settings: VignetteSettings) -> Recipe
    
    // MARK: - Filters
    public func filter(_ filter: Filter) -> Recipe
    public func lut(_ lutFile: URL) -> Recipe
    
    // MARK: - Composition
    public func mask(_ mask: Mask) -> Recipe
    public func blend(with image: UIImage, mode: BlendMode) -> Recipe
}
```

### 3. Timeline API

```swift
public class Timeline {
    // MARK: - Track Management
    public func addVideoTrack() -> VideoTrack
    public func addAudioTrack() -> AudioTrack  
    public func addEffectTrack() -> EffectTrack
    
    // MARK: - Timeline Operations
    public var duration: CMTime { get }
    public func trim(to range: CMTimeRange)
    public func split(at time: CMTime)
    
    // MARK: - Playback
    public func play()
    public func pause()
    public func seek(to time: CMTime)
}

public class VideoTrack {
    // MARK: - Clip Management
    public func add(clip: VideoClip, at time: CMTime)
    public func remove(clip: VideoClip)
    public func move(clip: VideoClip, to time: CMTime)
    
    // MARK: - Track Properties
    public var opacity: Float { get set }
    public var blendMode: BlendMode { get set }
    public var effects: [Effect] { get set }
}
```

### 4. Effect API

```swift
public protocol Effect {
    var identifier: String { get }
    var parameters: ParameterSet { get }
    var isEnabled: Bool { get set }
}

public struct ParameterSet {
    public subscript<T>(key: ParameterKey<T>) -> T { get set }
    public func animate<T>(_ key: ParameterKey<T>, 
                          from: T, 
                          to: T, 
                          duration: TimeInterval)
}

// Concrete Effects
public struct BlurEffect: Effect {
    public static let radius = ParameterKey<Float>("radius")
    public static let quality = ParameterKey<BlurQuality>("quality")
}

public struct ColorCorrectionEffect: Effect {
    public static let exposure = ParameterKey<Float>("exposure")
    public static let contrast = ParameterKey<Float>("contrast")
    public static let saturation = ParameterKey<Float>("saturation")
}
```

### 5. Export API

```swift
public struct ExportSession {
    // MARK: - Configuration
    public var outputURL: URL
    public var format: ExportFormat
    public var quality: ExportQuality
    public var metadata: ExportMetadata?
    
    // MARK: - Export Control
    public func start() async throws -> ExportTask
    public func cancel()
    
    // MARK: - Progress
    public var progress: AsyncStream<ExportProgress> { get }
    public var estimatedTimeRemaining: TimeInterval? { get }
}

public struct ExportTask {
    public let id: UUID
    public func pause()
    public func resume()
    public func cancel()
    public var state: ExportState { get }
}

// Export Formats
public enum ExportFormat {
    case image(ImageFormat)
    case video(VideoFormat)
    
    public enum ImageFormat {
        case jpeg(quality: Float)
        case png
        case heif
        case raw
        case custom(codec: String, options: [String: Any])
    }
    
    public enum VideoFormat {
        case h264(profile: H264Profile)
        case h265(profile: H265Profile)
        case prores(variant: ProResVariant)
        case custom(codec: String, options: [String: Any])
    }
}

### 6. Preset System API

```swift
public struct Preset {
    public let id: String
    public let name: String
    public let category: PresetCategory
    public let recipe: Recipe
    public let thumbnail: UIImage?
    
    // MARK: - Built-in Presets
    public static let vibrant = Preset(...)
    public static let moody = Preset(...)
    public static let cinematic = Preset(...)
    public static let vintage = Preset(...)
}

public class PresetManager {
    // MARK: - Preset Discovery
    public func presets(in category: PresetCategory) -> [Preset]
    public func search(query: String) -> [Preset]
    
    // MARK: - Custom Presets
    public func save(recipe: Recipe, as name: String) throws -> Preset
    public func delete(preset: Preset) throws
    public func export(preset: Preset, to url: URL) throws
    public func `import`(from url: URL) throws -> Preset
    
    // MARK: - Intelligent Suggestions
    public func suggestedPresets(for image: UIImage) async -> [Preset]
    public func suggestedPresets(for video: AVAsset) async -> [Preset]
}
```

### 7. Masking API

```swift
public protocol Mask {
    func evaluate(at point: CGPoint) -> Float
    func bounds() -> CGRect
}

public struct GradientMask: Mask {
    public var startPoint: CGPoint
    public var endPoint: CGPoint
    public var falloff: Float
    
    public init(from start: CGPoint, to end: CGPoint, falloff: Float = 0.5)
}

public struct RadialMask: Mask {
    public var center: CGPoint
    public var innerRadius: Float
    public var outerRadius: Float
    
    public init(center: CGPoint, innerRadius: Float, outerRadius: Float)
}

public struct PathMask: Mask {
    public var path: UIBezierPath
    public var feather: Float
    
    public init(path: UIBezierPath, feather: Float = 2.0)
}

public class MaskBuilder {
    // MARK: - AI-Powered Selection
    public func selectSubject(in image: UIImage) async throws -> PathMask
    public func selectSky(in image: UIImage) async throws -> PathMask
    public func selectByColor(in image: UIImage, 
                             color: UIColor, 
                             tolerance: Float) -> PathMask
    
    // MARK: - Manual Creation
    public func gradient(from start: CGPoint, to end: CGPoint) -> GradientMask
    public func radial(center: CGPoint, radius: Float) -> RadialMask
    public func path(_ path: UIBezierPath) -> PathMask
    
    // MARK: - Mask Operations
    public func combine(_ masks: [Mask], operation: MaskOperation) -> CompositeMask
    public func invert(_ mask: Mask) -> InvertedMask
}
```

### 8. Real-time Preview API

```swift
public class RenderView: UIView {
    // MARK: - Configuration
    public var contentMode: ContentMode { get set }
    public var preferredFramesPerSecond: Int { get set }
    
    // MARK: - Gesture Support
    public func addPanHandler(_ handler: @escaping (CGPoint) -> Void)
    public func addPinchHandler(_ handler: @escaping (CGFloat) -> Void)
    public func addRotationHandler(_ handler: @escaping (CGFloat) -> Void)
    
    // MARK: - Display
    public var transform3D: CATransform3D { get set }
    public var debugOverlay: DebugOverlay? { get set }
}

public struct DebugOverlay {
    public var showFPS: Bool
    public var showHistogram: Bool
    public var showClipping: Bool
    public var showFocusPeaking: Bool
}
```

### 9. Color Management API

```swift
public struct ColorSpace {
    public static let sRGB = ColorSpace(...)
    public static let displayP3 = ColorSpace(...)
    public static let adobeRGB = ColorSpace(...)
    public static let rec709 = ColorSpace(...)
    public static let rec2020 = ColorSpace(...)
    
    public init(iccProfile: Data) throws
}

public class ColorManager {
    // MARK: - Color Space Conversion
    public func convert(image: UIImage, 
                       from: ColorSpace, 
                       to: ColorSpace) async throws -> UIImage
    
    // MARK: - Color Analysis
    public func analyze(image: UIImage) async -> ColorAnalysis
    public func generateHistogram(for image: UIImage) async -> Histogram
    
    // MARK: - Calibration
    public func calibrate(display: UIScreen, 
                         target: ColorSpace) throws -> DisplayProfile
}
```

### 10. Performance API

```swift
public struct PerformanceMetrics {
    public let fps: Double
    public let frameTime: TimeInterval
    public let gpuUtilization: Float
    public let memoryUsage: MemoryUsage
    public let thermalState: ThermalState
}

public class PerformanceMonitor {
    // MARK: - Monitoring
    public func startMonitoring() -> AsyncStream<PerformanceMetrics>
    public func stopMonitoring()
    
    // MARK: - Optimization
    public func suggestOptimizations() -> [OptimizationSuggestion]
    public func enablePowerSaving()
    public func enableHighPerformance()
}
```

### 11. Error Handling

```swift
public enum RenderError: LocalizedError {
    case deviceNotSupported(reason: String)
    case outOfMemory(required: Int, available: Int)
    case invalidInput(description: String)
    case effectNotAvailable(effect: String, reason: String)
    case exportFailed(underlying: Error)
    
    public var errorDescription: String? { get }
    public var recoverySuggestion: String? { get }
}

public struct ErrorRecovery {
    public static func recover(from error: RenderError) -> RecoveryAction?
    public static func fallback(for operation: Operation) -> Operation?
}
```

### 12. SwiftUI Integration

```swift
import SwiftUI

public struct RenderEngineView: UIViewRepresentable {
    let source: MediaSource
    @Binding var recipe: Recipe
    let onFrameRendered: ((ProcessedImage) -> Void)?
    
    public func makeUIView(context: Context) -> RenderView
    public func updateUIView(_ uiView: RenderView, context: Context)
}

public struct EffectSlider: View {
    let effect: Effect
    let parameter: ParameterKey<Float>
    @Binding var value: Float
    
    public var body: some View {
        VStack {
            Text(parameter.displayName)
            Slider(value: $value, 
                   in: parameter.range,
                   onEditingChanged: { editing in
                       if !editing {
                           effect.parameters[parameter] = value
                       }
                   })
        }
    }
}
```

### 13. Combine Integration

```swift
import Combine

extension RenderEngine {
    // MARK: - Reactive Processing
    public func processPublisher(image: UIImage, 
                                recipe: Recipe) -> AnyPublisher<ProcessedImage, RenderError>
    
    public func previewPublisher(source: MediaSource,
                                quality: PreviewQuality) -> AnyPublisher<RenderedFrame, Never>
}

extension Recipe {
    // MARK: - Reactive Updates
    @Published public var adjustments: Adjustments
    
    public var recipePublisher: AnyPublisher<Recipe, Never> { get }
}
```

### 14. Extensibility API

```swift
public protocol RenderEnginePlugin {
    static var identifier: String { get }
    static var version: Version { get }
    
    func initialize(engine: RenderEngine) throws
    func registerEffects() -> [Effect.Type]
    func registerFilters() -> [Filter.Type]
    func registerExportFormats() -> [ExportFormat]
}

public class PluginManager {
    public func load(plugin: RenderEnginePlugin.Type) throws
    public func unload(identifier: String)
    public func availablePlugins() -> [PluginInfo]
}
```

## Usage Examples

### Basic Image Processing
```swift
let engine = try RenderEngine()

// Simple enhancement
let enhanced = try await engine.process(
    image: photo,
    with: Recipe()
        .exposure(0.5)
        .contrast(0.2)
        .vibrance(0.3)
)

// Using presets
let vintage = try await engine.process(
    image: photo,
    with: Recipe.from(preset: .vintage)
)
```

### Advanced Video Editing
```swift
let timeline = engine.createTimeline(from: [videoClip1, videoClip2])
    .addTransition(.dissolve, duration: 1.0)
    .addEffect(.colorCorrection(exposure: 0.3))
    .build()

let processed = try await engine.process(
    video: timeline,
    quality: .high
)

// Export with progress
let export = ExportSession(
    outputURL: outputURL,
    format: .video(.h264(profile: .high)),
    quality: .high
)

for await progress in export.progress {
    print("Export progress: \(progress.percentage)%")
}
```

### Real-time Preview
```swift
let renderView = RenderView()
engine.startPreview(source: .camera, in: renderView)

// Apply effects in real-time
engine.updatePreview(
    with: Recipe()
        .filter(.noir)
        .vignette(VignetteSettings(intensity: 0.8))
)
```

## Best Practices

1. **Progressive Disclosure**: Simple operations should be simple, complex operations should be possible
2. **Type Safety**: Leverage Swift's type system to prevent runtime errors
3. **Async by Default**: All potentially long operations use async/await
4. **Cancellation**: All async operations support proper cancellation
5. **Memory Safety**: Automatic memory management with manual optimization options
6. **Thread Safety**: All public APIs are thread-safe
7. **Error Recovery**: Graceful degradation with helpful recovery suggestions