# MetalX Code Style Guide

## Swift Style

### Naming Conventions

```swift
// Types: UpperCamelCase
class RenderEngine { }
struct LayerConfiguration { }
enum BlendMode { }
protocol Drawable { }

// Variables and Functions: lowerCamelCase
let maximumLayerCount = 100
func renderFrame(at time: CMTime) { }

// Constants: lowerCamelCase (not SCREAMING_SNAKE_CASE)
let defaultFrameRate = 60.0
let maximumTextureSize = 4096

// Acronyms: Treat as words
let urlString = "https://example.com"  // not URLString
let jsonData = Data()                  // not JSONData
class LutProcessor { }                 // not LUTProcessor
```

### Code Organization

```swift
// MARK: - Section Headers
class Layer {
    // MARK: - Properties
    let id: UUID
    var name: String
    
    // MARK: - Initialization
    init() { }
    
    // MARK: - Public Methods
    public func render() { }
    
    // MARK: - Private Methods
    private func updateCache() { }
}

// Extension Organization
// Separate file: Layer+Rendering.swift
extension Layer {
    func render(in context: RenderContext) -> MTLTexture? { }
}

// Separate file: Layer+Codable.swift
extension Layer: Codable { }
```

### Swift Best Practices

```swift
// Prefer let over var
let texture = device.makeTexture(descriptor: descriptor)

// Use guard for early returns
guard let device = MTLCreateSystemDefaultDevice() else {
    throw MetalXError.deviceNotFound
}

// Avoid force unwrapping - use if let or guard
if let texture = cache[key] {
    return texture
}

// Use trailing closure syntax
layers.filter { $0.isVisible }.forEach { layer in
    layer.render()
}

// Prefer Swift's type inference
let opacity = 0.5  // not: let opacity: Float = 0.5

// Use meaningful variable names
let elapsedTime = CACurrentMediaTime() - startTime  // not: let t = ...
```

## Metal Shader Style

### Shader Naming

```metal
// File naming: FeatureName.metal
// Examples: Blur.metal, ColorGrading.metal, Particles.metal

// Function naming: camelCase with descriptive names
vertex VertexOut blurVertex(uint vertexID [[vertex_id]]);
fragment float4 gaussianBlurFragment(VertexOut in [[stage_in]]);

// Struct naming: UpperCamelCase
struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// Constant naming: UPPER_SNAKE_CASE for preprocessor
#define MAX_BLUR_RADIUS 64
#define SAMPLE_COUNT 9

// But use constexpr for actual constants
constexpr constant float PI = 3.14159265359;
```

### Shader Organization

```metal
// 1. Includes and imports
#include <metal_stdlib>
#include "Common.metal"

using namespace metal;

// 2. Constants and defines
constexpr constant int maxLights = 8;

// 3. Structures
struct VertexIn { };
struct VertexOut { };
struct Uniforms { };

// 4. Utility functions
float3 sRGBToLinear(float3 color) { }

// 5. Vertex functions
vertex VertexOut vertexMain() { }

// 6. Fragment functions  
fragment float4 fragmentMain() { }

// 7. Compute kernels
kernel void computeMain() { }
```

## Documentation

### Swift Documentation

```swift
/// Renders a layer with the specified blend mode and opacity.
///
/// This method handles all compositing operations including:
/// - Blend mode application
/// - Opacity multiplication  
/// - Clipping mask application
///
/// - Parameters:
///   - context: The current render context containing encoder and resources
///   - blendMode: How this layer should blend with layers below
///   - opacity: Layer opacity from 0.0 (transparent) to 1.0 (opaque)
///
/// - Returns: The rendered texture, or nil if rendering failed
///
/// - Throws: 
///   - `MetalXError.outOfMemory` if texture allocation fails
///   - `MetalXError.invalidParameter` if opacity is outside valid range
///
/// - Complexity: O(n) where n is the number of pixels
func render(
    in context: RenderContext,
    blendMode: BlendMode = .normal,
    opacity: Float = 1.0
) throws -> MTLTexture? {
    // Implementation
}
```

### Shader Documentation

```metal
/**
 * Gaussian blur fragment shader
 * 
 * Performs a separable gaussian blur using a fixed kernel size.
 * This is the horizontal pass - must be followed by vertical pass.
 *
 * @param in Interpolated vertex data
 * @param sourceTexture The texture to blur
 * @param uniforms Contains blur radius and direction
 * @return Blurred color value
 */
fragment float4 gaussianBlurHorizontal(
    VertexOut in [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    constant BlurUniforms& uniforms [[buffer(0)]]
) {
    // Implementation
}
```

## Project Structure

```
MetalX/
├── Core/
│   ├── Engine/
│   │   ├── RenderEngine.swift
│   │   └── RenderEngine+Timeline.swift  // Large class extensions
│   └── Errors/
│       └── MetalXError.swift           // All errors in one place
├── Layers/
│   ├── Base/
│   │   └── Layer.swift                 // Protocol definition
│   └── Types/
│       ├── ImageLayer.swift            // Concrete implementation
│       └── ImageLayer+Effects.swift    // Feature-specific extensions
└── Shaders/
    ├── Common.metal                    // Shared utilities
    ├── Filters/
    │   └── Blur.metal                  // Feature-specific shaders
    └── ShaderTypes.h                   // Bridging header for Swift/Metal
```

## Git Commit Style

```bash
# Format: <type>(<scope>): <subject>

# Types:
# feat: New feature
# fix: Bug fix  
# docs: Documentation only
# style: Code style (formatting, missing semicolons, etc)
# refactor: Code change that neither fixes a bug nor adds a feature
# perf: Performance improvement
# test: Adding missing tests
# chore: Changes to build process or auxiliary tools

# Examples:
git commit -m "feat(layers): Add drop shadow effect"
git commit -m "fix(memory): Resolve texture leak in effect chain"
git commit -m "perf(blur): Optimize gaussian blur with separable filter"
git commit -m "docs(api): Update render method documentation"

# Commit body for complex changes:
git commit -m "feat(particles): Add GPU-based particle system

- Implement emitter configuration
- Add force field support  
- Support up to 1 million particles
- Include preset effects (fire, smoke, snow)

Closes #123"
```

## Testing Style

```swift
class LayerTests: XCTestCase {
    // MARK: - Properties
    var sut: Layer!  // System Under Test
    
    // MARK: - Setup
    override func setUp() {
        super.setUp()
        sut = ImageLayer()
    }
    
    // MARK: - Tests
    // Naming: test_methodName_condition_expectedResult
    func test_render_withZeroOpacity_returnsNil() {
        // Given
        sut.opacity = 0.0
        
        // When
        let result = sut.render()
        
        // Then
        XCTAssertNil(result)
    }
}
```