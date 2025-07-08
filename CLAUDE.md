# MetalX Implementation Guide for Claude Code

## Project Overview

MetalX is a professional GPU rendering engine for iOS that combines the power of desktop editing applications with mobile-first design. This guide provides step-by-step instructions for implementing the engine using the specifications in the `/docs` directory.

## Documentation Structure

All detailed specifications are in the `/docs` directory:

```
/docs/
├── high-level-rendering-spec.md     # Overall system architecture
├── primitives-spec.md               # Core rendering primitives
├── architecture-spec.md             # System architecture details
├── image-processing-spec.md         # Image pipeline specification
├── video-processing-spec.md         # Video pipeline specification
├── pipeline-implementation-spec.md  # Metal pipeline details
├── api-spec.md                      # Public API design
├── memory-management-spec.md        # Memory system design
├── advanced-text-spec.md            # 3D text and typography
├── compositing-masking-spec.md      # Layer compositing system
├── particle-fluid-spec.md           # Particle and fluid effects
├── motion-input-spec.md             # Device motion and gestures
├── performance-monitoring-spec.md   # Performance optimization
├── audio-processing-spec.md         # Audio system design
├── ml-ai-integration-spec.md        # Machine learning features
├── undo-redo-spec.md               # Undo/redo system
├── testing-strategy-spec.md         # Testing approach
└── layer-system-spec.md            # Layer management system
```

## How to Use the Specifications

When implementing each component, reference the corresponding spec:

1. **Start with architecture-spec.md** to understand the overall system
2. **Reference specific specs** as you implement each module
3. **Cross-reference between specs** as they often interconnect

### Example Workflow

When implementing the Layer System (Week 4):
1. Open `/docs/layer-system-spec.md` for complete layer details
2. Reference `/docs/compositing-masking-spec.md` for blend modes
3. Check `/docs/api-spec.md` for the public API design
4. Use `/docs/memory-management-spec.md` for resource handling

## Project Structure

```
MetalX/
├── MetalX/                      # Main framework
│   ├── Core/                    # Core rendering engine
│   │   ├── Engine/             # Main engine classes
│   │   ├── Pipeline/           # Metal pipeline
│   │   ├── Memory/             # Memory management
│   │   └── Math/               # Math utilities
│   ├── Layers/                 # Layer system
│   │   ├── Base/              # Base layer protocols
│   │   ├── Types/             # Layer implementations
│   │   └── Effects/           # Layer effects
│   ├── Effects/                # Effects library
│   │   ├── Filters/           # Image filters
│   │   ├── Adjustments/       # Color adjustments
│   │   ├── Particles/         # Particle systems
│   │   └── Transitions/       # Video transitions
│   ├── Timeline/               # Video timeline
│   ├── Typography/             # Text rendering
│   ├── UI/                     # UI components
│   ├── ML/                     # Machine learning
│   ├── Audio/                  # Audio processing
│   └── Shaders/               # Metal shaders
├── MetalXDemo/                 # Demo application
├── MetalXTests/                # Test suites
└── docs/                       # Specifications
```

## Implementation Priority

### Phase 1: Foundation (Weeks 1-3)
Start with the core rendering pipeline and basic image processing.

### Phase 2: Layer System (Weeks 4-5)
Implement the layer stack and compositing system.

### Phase 3: Effects Engine (Weeks 6-8)
Build the effects pipeline and basic filters.

### Phase 4: Video Support (Weeks 9-11)
Add timeline and video processing capabilities.

### Phase 5: Advanced Features (Weeks 12-14)
Implement ML features, particles, and advanced text.

### Phase 6: Polish (Weeks 15-16)
Optimization, testing, and demo app completion.

## Key Implementation Notes

### Metal Pipeline Setup
1. Always use TBDR optimization for Apple GPUs
2. Implement proper resource heaps for memory efficiency
3. Use programmable blending to minimize render passes
4. Cache compiled pipeline states

### Memory Management
1. Implement the unified memory architecture from the spec
2. Use purgeable resources for cached data
3. Monitor thermal state and adapt quality
4. Triple buffer for smooth video playback

### Performance Critical Paths
1. Layer rendering must maintain 60 FPS
2. Video scrubbing needs predictive caching
3. Effect preview requires LOD system
4. Export can be slower but needs progress reporting

### Testing Strategy
1. Start each component with unit tests
2. Add visual regression tests for all effects
3. Performance test on iPhone 12 (minimum spec)
4. Stress test with 100+ layer projects

## Common Pitfalls to Avoid

1. **Don't assume desktop GPU patterns** - Apple GPUs are different
2. **Avoid excessive texture sampling** - It's expensive on mobile
3. **Never block the main thread** - Use async/await throughout
4. **Test memory pressure early** - iOS is aggressive about memory
5. **Profile on device** - Simulator performance is misleading

## Quick Start Commands

```bash
# Create the project structure
mkdir -p MetalX/{Core/{Engine,Pipeline,Memory,Math},Layers/{Base,Types,Effects},Effects/{Filters,Adjustments,Particles,Transitions},Timeline,Typography,UI,ML,Audio,Shaders}

# Initialize Swift package
cd MetalX
swift package init --type library

# Add Metal shader files
touch Shaders/{Common,Filters,Compositing,Particles,Text}.metal

# Create base protocols
touch Core/Engine/RenderEngine.swift
touch Layers/Base/Layer.swift
touch Effects/Effect.swift
```

## File Creation Order

1. **Core/Math/MathExtensions.swift** - ✅ SIMD helpers and matrix operations
2. **Core/Math/Geometry.swift** - ✅ CGRect/CGPoint extensions and transforms
3. **Core/Engine/MetalDevice.swift** - ✅ Device setup and capability detection  
4. **Core/Engine/RenderContext.swift** - ✅ Rendering context management
5. **Core/Engine/EngineConfiguration.swift** - ✅ Configuration and quality settings
6. **Core/Pipeline/PipelineStateCache.swift** - ✅ PSO caching with async compilation
7. **Core/Pipeline/ShaderLibrary.swift** - ✅ Shader loading and function management
8. **Core/Engine/RenderEngine.swift** - Main engine implementation
9. **Layers/Base/Layer.swift** - Layer protocol
10. **Layers/Types/ImageLayer.swift** - Basic image layer
11. **Core/Pipeline/CommandBuilder.swift** - Command buffer management
12. **Effects/Effect.swift** - Effect protocol
13. **Effects/Adjustments/BasicAdjustments.swift** - First effects

## Debugging Tools

```swift
// Enable Metal validation
setenv("METAL_DEVICE_WRAPPER_TYPE", "1", 1)

// Capture GPU frame
if let captureManager = MTLCaptureManager.shared() {
    let captureDescriptor = MTLCaptureDescriptor()
    captureDescriptor.captureObject = device
    try captureManager.startCapture(with: captureDescriptor)
}

// Performance timing
class GPUTimer {
    func time(_ label: String, _ block: () -> Void) {
        let start = CACurrentMediaTime()
        block()
        let elapsed = CACurrentMediaTime() - start
        print("[\(label)] \(elapsed * 1000)ms")
    }
}
```

## Validation Checklist

After implementing each component:

- [ ] Unit tests pass
- [ ] No memory leaks (run Instruments)
- [ ] 60 FPS maintained
- [ ] Handles memory pressure gracefully
- [ ] Visual output matches reference
- [ ] API is documented
- [ ] Error handling is comprehensive

## Resources

- [Metal Best Practices Guide](https://developer.apple.com/metal/)
- [WWDC Metal Videos](https://developer.apple.com/videos/graphics-and-games/metal/)
- Project specifications in `/docs` directory

## Getting Help

1. Check the specification documents first
2. Look for similar patterns in the codebase
3. Test on real devices early and often
4. Profile before optimizing

Remember: Start simple, test thoroughly, optimize later.