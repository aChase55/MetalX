# Image Processing Pipeline Specification

## Overview
The image processing pipeline handles still images from 1MP thumbnails to 100MP+ RAW files, providing real-time preview and high-quality export capabilities.

## Image Pipeline Architecture

### Input Stage

#### Supported Formats
```swift
enum ImageFormat {
    // Standard Formats
    case jpeg(quality: Float)
    case png(interlaced: Bool)
    case heif(depth: BitDepth)
    case webp(lossless: Bool)
    
    // Professional Formats
    case raw(camera: CameraProfile)
    case dng(version: String)
    case tiff(compression: TIFFCompression)
    case psd(layers: Bool)
    
    // HDR Formats
    case exr(compression: EXRCompression)
    case hdr(format: RadianceFormat)
}
```

#### Image Loader
```swift
class ImageLoader {
    // Async loading with progress
    func load(url: URL, 
             options: LoadOptions,
             progress: @escaping (Float) -> Void) async -> LoadedImage
    
    // Metadata extraction
    func extractMetadata(url: URL) -> ImageMetadata
    
    // Quick preview generation
    func generatePreview(url: URL, maxSize: CGSize) -> UIImage
}
```

### Decode Pipeline

#### Progressive Decoding
- **Level 0**: Thumbnail (256x256)
- **Level 1**: Preview (1024x1024)
- **Level 2**: Working (2048x2048)
- **Level 3**: Full resolution

#### RAW Processing
```swift
class RAWProcessor {
    // Demosaic algorithms
    enum DemosaicMethod {
        case bilinear      // Fast, lower quality
        case ahd           // Adaptive Homogeneity-Directed
        case dcb           // DCB interpolation
        case amaze         // AMaZE algorithm
    }
    
    // Processing pipeline
    func process(rawData: Data, 
                settings: RAWSettings) -> ProcessedImage {
        // 1. Demosaic
        // 2. White balance
        // 3. Highlight recovery
        // 4. Noise reduction
        // 5. Lens corrections
    }
}
```

### Color Management

#### Color Pipeline
```swift
class ColorManager {
    // Color space conversions
    func convert(image: MTLTexture,
                from: ColorSpace,
                to: ColorSpace) -> MTLTexture
    
    // ICC profile support
    func applyProfile(image: MTLTexture,
                     profile: ICCProfile) -> MTLTexture
    
    // HDR tone mapping
    func toneMap(hdrImage: MTLTexture,
                method: ToneMappingMethod) -> MTLTexture
}
```

#### Tone Mapping Operators
- **Reinhard**: Classic, balanced
- **ACES**: Film-like response  
- **Hable**: Uncharted 2 filmic
- **Local**: Adaptive local method

### Core Effects Pipeline

#### 1. Basic Adjustments
```metal
struct BasicAdjustments {
    float exposure;      // -5.0 to +5.0 EV
    float contrast;      // -100 to +100
    float highlights;    // -100 to +100  
    float shadows;       // -100 to +100
    float whites;        // -100 to +100
    float blacks;        // -100 to +100
    float vibrance;      // -100 to +100
    float saturation;    // -100 to +100
};
```

#### 2. Color Grading
```swift
class ColorGrading {
    // 3-way color wheels
    struct ColorWheels {
        var shadows: SIMD3<Float>
        var midtones: SIMD3<Float>
        var highlights: SIMD3<Float>
    }
    
    // Curves adjustment
    struct Curves {
        var rgb: CubicBezier
        var red: CubicBezier
        var green: CubicBezier
        var blue: CubicBezier
    }
    
    // HSL adjustments
    struct HSLAdjustment {
        var hueShift: Float
        var saturationCurve: Curve
        var luminanceCurve: Curve
    }
}
```

#### 3. Local Adjustments

##### Gradient Filter
```swift
struct GradientFilter {
    var startPoint: CGPoint
    var endPoint: CGPoint
    var feather: Float
    var adjustments: BasicAdjustments
}
```

##### Radial Filter
```swift
struct RadialFilter {
    var center: CGPoint
    var radius: Float
    var feather: Float
    var invert: Bool
    var adjustments: BasicAdjustments
}
```

##### Masking System
```swift
class MaskingSystem {
    // AI-powered selection
    func selectSubject(image: MTLTexture) -> MTLTexture
    func selectSky(image: MTLTexture) -> MTLTexture
    
    // Color range selection
    func selectColorRange(image: MTLTexture,
                         color: SIMD3<Float>,
                         tolerance: Float) -> MTLTexture
    
    // Luminosity masking
    func createLuminosityMask(image: MTLTexture,
                             range: ClosedRange<Float>) -> MTLTexture
}
```

### Advanced Effects

#### 1. Blur Effects
```swift
enum BlurType {
    case gaussian(radius: Float)
    case motion(angle: Float, distance: Float)
    case radial(center: CGPoint, amount: Float)
    case tiltShift(focus: CGRect, blur: Float)
    case lens(aperture: Float, blades: Int)
}
```

#### 2. Sharpening
```swift
struct SharpeningParams {
    var amount: Float      // 0-500%
    var radius: Float      // 0.1-3.0 pixels
    var detail: Float      // 0-100
    var masking: Float     // 0-100
    
    // Output sharpening
    var outputMedia: OutputMedia
    var outputSize: CGSize
}
```

#### 3. Noise Reduction
```swift
class NoiseReduction {
    struct Settings {
        var luminance: Float    // 0-100
        var color: Float        // 0-100
        var detail: Float       // 0-100
        var contrast: Float     // 0-100
    }
    
    // AI-enhanced denoising
    func denoise(image: MTLTexture,
                settings: Settings,
                useML: Bool) -> MTLTexture
}
```

#### 4. Transform Operations
```swift
class TransformOperations {
    // Perspective correction
    func correctPerspective(image: MTLTexture,
                          corners: [CGPoint]) -> MTLTexture
    
    // Lens corrections
    func correctLensDistortion(image: MTLTexture,
                             profile: LensProfile) -> MTLTexture
    
    // Smart crop suggestions
    func suggestCrops(image: MTLTexture) -> [CropSuggestion]
}
```

### Filter System

#### Artistic Filters
```swift
class ArtisticFilters {
    // Style transfer
    func applyStyle(content: MTLTexture,
                   style: StyleModel) -> MTLTexture
    
    // Classic filters
    func vintage(image: MTLTexture,
                preset: VintagePreset) -> MTLTexture
    
    // Film emulation
    func filmEmulation(image: MTLTexture,
                      stock: FilmStock) -> MTLTexture
}
```

### Batch Processing

#### Batch Operations
```swift
class BatchProcessor {
    // Apply same edits to multiple images
    func process(images: [URL],
                recipe: EditRecipe,
                progress: BatchProgress) async
    
    // Smart sync adjustments
    func syncAdjustments(images: [URL],
                        reference: URL,
                        attributes: SyncAttributes)
}
```

### Export Pipeline

#### Export Formats
```swift
struct ExportSettings {
    var format: ImageFormat
    var colorSpace: ColorSpace
    var quality: Float
    var metadata: MetadataOptions
    var watermark: WatermarkSettings?
    
    // Size options
    enum SizeOption {
        case original
        case dimension(CGSize)
        case percentage(Float)
        case fileSize(Int) // Target in bytes
    }
}
```

#### Smart Export
```swift
class SmartExporter {
    // Platform-optimized export
    func exportForPlatform(image: ProcessedImage,
                          platform: SocialPlatform) -> Data
    
    // Multi-format export
    func exportMultiple(image: ProcessedImage,
                       formats: [ExportFormat]) -> [ExportResult]
}
```

## Performance Optimizations

### Tile-Based Processing
```swift
class TileProcessor {
    // Process large images in tiles
    func processTiled(image: MTLTexture,
                     tileSize: Int = 512,
                     overlap: Int = 32,
                     processor: TileProcessor) -> MTLTexture
}
```

### Resolution Independence
- Work on reduced resolution for preview
- Apply edits to full resolution on export
- Smart cache invalidation
- Progressive rendering

### GPU Memory Management
```swift
class ImageMemoryManager {
    // Automatic quality reduction under pressure
    func handleMemoryPressure(level: MemoryPressureLevel)
    
    // Predictive loading
    func preloadNext(basedOn: UserBehavior)
    
    // Texture compression
    func compressInactive(textures: [MTLTexture])
}
```

## Quality Metrics

### Image Quality Assessment
```swift
class QualityAnalyzer {
    // Sharpness detection
    func measureSharpness(image: MTLTexture) -> Float
    
    // Noise estimation
    func estimateNoise(image: MTLTexture) -> NoiseProfile
    
    // Exposure analysis
    func analyzeExposure(image: MTLTexture) -> ExposureInfo
    
    // Composition scoring
    func scoreComposition(image: MTLTexture) -> CompositionScore
}
```

## Non-Destructive Editing

### Edit History
```swift
class EditHistory {
    // Versioning
    func checkpoint(name: String)
    func revert(to: Checkpoint)
    
    // History visualization
    func timeline() -> [EditStep]
    
    // Recipe extraction
    func exportRecipe() -> EditRecipe
}
```

### Smart Previews
- Generate once, reuse everywhere
- Update incrementally
- Background regeneration
- Quality-based invalidation