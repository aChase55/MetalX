# Rendering Primitives Specification

## Core Primitive Types

### 1. Texture Primitives

#### BaseTexture
```swift
class BaseTexture {
    var metalTexture: MTLTexture
    var format: MTLPixelFormat
    var usage: MTLTextureUsage
    var width: Int
    var height: Int
    var storageMode: MTLStorageMode
}
```

#### Texture Types
- **SourceTexture**: Original image/video frame
- **RenderTexture**: Intermediate rendering target
- **LUTTexture**: 1D/2D/3D lookup tables
- **MaskTexture**: Alpha/selection masks
- **CacheTexture**: Cached results

#### Optimized Formats
- **Color**: `.bgra8Unorm` (standard), `.rgba16Float` (HDR)
- **Masks**: `.r8Unorm` (simple), `.r16Float` (soft edges)
- **Normal Maps**: `.rg16Float`
- **Data**: `.r32Float` (compute data)

### 2. Buffer Primitives

#### Vertex Data
```swift
struct Vertex {
    var position: SIMD3<Float>
    var texCoord: SIMD2<Float>
    var normal: SIMD3<Float>
    var tangent: SIMD4<Float>
}
```

#### Uniform Buffers
- **TransformBuffer**: MVP matrices
- **EffectParameters**: Per-effect settings
- **TimeBuffer**: Animation/timeline data
- **LightingBuffer**: Light positions/colors

### 3. Geometry Primitives

#### Mesh Types
- **QuadMesh**: Full-screen effects
- **GridMesh**: Distortion/warp effects
- **SplineMesh**: Vector/bezier rendering
- **ParticleMesh**: Instanced particles

#### Topology Support
- Triangles (default)
- Triangle strips (optimized quads)
- Points (particles)
- Lines (debugging/guides)

### 4. Shader Primitives

#### Shader Functions
```metal
// Vertex transformation
vertex VertexOut vertexTransform(VertexIn in [[stage_in]],
                                 constant Transform& transform [[buffer(0)]])

// Fragment processing
fragment float4 fragmentProcess(VertexOut in [[stage_in]],
                              texture2d<float> inputTexture [[texture(0)]],
                              constant EffectParams& params [[buffer(1)]])

// Compute kernels
kernel void computeProcess(uint2 gid [[thread_position_in_grid]],
                         texture2d<float, access::read> input [[texture(0)]],
                         texture2d<float, access::write> output [[texture(1)]])
```

#### Shader Library Organization
- **Core**: Basic transforms, sampling
- **Filters**: Blur, sharpen, stylize
- **Color**: Corrections, grading, mapping
- **Distortion**: Warp, liquify, perspective
- **Composite**: Blend modes, masks
- **Generate**: Noise, gradients, patterns

### 5. Sampler Primitives

#### Sampler States
```swift
enum SamplerType {
    case linear      // Smooth interpolation
    case nearest     // Pixel-perfect
    case cubic       // High-quality scaling
    case lanczos     // Premium downsampling
}
```

#### Address Modes
- **Clamp**: Edge pixels extend
- **Repeat**: Tiling patterns
- **Mirror**: Seamless tiling
- **Zero**: Black borders

### 6. Render State Primitives

#### Pipeline States
- **AlphaBlending**: Transparency compositing
- **AdditiveBlending**: Light accumulation
- **MultiplyBlending**: Shadow accumulation
- **ProgrammableBlending**: Custom blend ops

#### Depth/Stencil States
- **NoDepth**: 2D operations
- **DepthTest**: 3D layering
- **StencilMask**: Complex masking
- **DepthPeeling**: Order-independent transparency

### 7. Command Primitives

#### Command Types
```swift
protocol RenderCommand {
    func encode(into encoder: MTLRenderCommandEncoder)
    var debugName: String { get }
}

struct DrawCommand: RenderCommand {
    var pipeline: MTLRenderPipelineState
    var vertexBuffer: MTLBuffer
    var indexBuffer: MTLBuffer?
    var textures: [MTLTexture]
    var uniforms: [MTLBuffer]
}
```

### 8. Transform Primitives

#### 2D Transforms
- **Translation**: Pixel-precise positioning
- **Rotation**: Angle + center point
- **Scale**: Non-uniform supported
- **Skew**: Horizontal/vertical shear
- **Perspective**: 2D projection

#### 3D Transforms
- **ModelMatrix**: Object space → World space
- **ViewMatrix**: World space → Camera space
- **ProjectionMatrix**: Camera space → Clip space
- **TextureMatrix**: UV transformations

### 9. Color Primitives

#### Color Spaces
```swift
enum ColorSpace {
    case sRGB
    case displayP3
    case rec709
    case rec2020
    case aces
    case linear
}
```

#### Color Operations
- **Transform**: Space conversions
- **Adjust**: HSL/RGB modifications
- **Map**: LUT applications
- **Analyze**: Histogram generation

### 10. Timing Primitives

#### Time Sources
- **FrameTime**: Current frame timestamp
- **DeltaTime**: Time since last frame
- **AnimationTime**: Effect-local time
- **GlobalTime**: App-wide timer

#### Interpolation
```swift
protocol Interpolatable {
    static func lerp(_ a: Self, _ b: Self, t: Float) -> Self
    static func smoothstep(_ a: Self, _ b: Self, t: Float) -> Self
    static func cubicBezier(_ a: Self, _ b: Self, 
                           control1: Self, control2: Self, t: Float) -> Self
}
```

## Memory Primitives

### Allocation Strategies
- **Heap-Based**: Manual lifetime management
- **Transient**: Frame-lifetime resources
- **Persistent**: Cross-frame caching
- **Purgeable**: System-managed eviction

### Resource Pools
```swift
class ResourcePool<T: MTLResource> {
    func acquire() -> T
    func release(_ resource: T)
    func drain()
}
```

## Synchronization Primitives

### Fence Types
- **GPUFence**: GPU-GPU sync
- **CPUFence**: CPU-GPU sync
- **EventFence**: Cross-queue sync

### Semaphores
- **Binary**: Simple mutex
- **Counting**: Resource limiting
- **Timeline**: Ordered operations

## Usage Patterns

### Effect Building Blocks
1. **Input**: Texture sampling
2. **Process**: Shader computation
3. **Output**: Render target write
4. **Cache**: Result storage

### Composition Patterns
1. **Sequential**: A → B → C
2. **Parallel**: A + B → C
3. **Branching**: A → (B|C) → D
4. **Recursive**: A → A' → A''

### Performance Patterns
1. **Batch Similar**: Group by pipeline
2. **Minimize State**: Sort by state
3. **Coalesce Draws**: Merge compatible
4. **Cache Aggressively**: Reuse everything