# MetalX Documentation Quick Reference

## 📋 Specification Documents Overview

### Core Architecture
- **high-level-rendering-spec.md** - Start here! Overall vision and differentiators
- **architecture-spec.md** - System components and how they interact
- **api-spec.md** - Public API design and usage examples

### Rendering Foundation
- **primitives-spec.md** - Basic building blocks (textures, buffers, shaders)
- **pipeline-implementation-spec.md** - Metal pipeline details and optimization
- **memory-management-spec.md** - Memory strategies for iOS constraints

### Layer System
- **layer-system-spec.md** - Complete layer management implementation
- **compositing-masking-spec.md** - Blend modes, masks, and compositing

### Processing Pipelines
- **image-processing-spec.md** - Still image editing pipeline
- **video-processing-spec.md** - Timeline and video editing
- **audio-processing-spec.md** - Audio tracks and effects

### Advanced Features
- **advanced-text-spec.md** - 3D text with bevels and effects (Riveo-inspired)
- **particle-fluid-spec.md** - GPU particle systems and fluid simulation
- **ml-ai-integration-spec.md** - Smart selection and AI features
- **motion-input-spec.md** - Gesture recognition and device motion

### Infrastructure
- **undo-redo-spec.md** - Non-linear undo with branching
- **performance-monitoring-spec.md** - Profiling and optimization
- **testing-strategy-spec.md** - Comprehensive testing approach

## 🎯 Quick Navigation by Task

### "I need to implement..."

**Basic image loading and display**
→ Start with `primitives-spec.md` and `image-processing-spec.md`

**Layers with blend modes**
→ See `layer-system-spec.md` and `compositing-masking-spec.md`

**Video timeline**
→ Check `video-processing-spec.md`

**3D text effects**
→ Read `advanced-text-spec.md`

**Particle effects**
→ Reference `particle-fluid-spec.md`

**Smart selection tools**
→ Look at `ml-ai-integration-spec.md`

**Memory optimization**
→ Study `memory-management-spec.md`

**Undo/redo system**
→ Implement from `undo-redo-spec.md`

## 📖 Reading Order for New Developers

1. **high-level-rendering-spec.md** - Understand the vision
2. **architecture-spec.md** - Learn the system design
3. **primitives-spec.md** - Grasp the building blocks
4. **layer-system-spec.md** - Core functionality
5. **api-spec.md** - How users interact with it
6. *Then dive into specific features as needed*

## 🔍 Spec Interconnections

Many specs reference each other:

- **Layer System** uses → Compositing, Memory Management, Primitives
- **Video Processing** uses → Timeline, Audio, Effects, Memory
- **Effects** use → Primitives, Pipeline Implementation
- **ML Features** use → Memory Management, Layer System
- **Everything** uses → Architecture, API, Performance

## 💡 Implementation Tips

1. **Keep specs open while coding** - They contain implementation details
2. **Cross-reference specs** - Features often span multiple documents  
3. **Check code examples** - Many specs include Swift/Metal code
4. **Note the dependencies** - Some features require others first

## 🏗️ Original Inspiration

- **advanced-text-spec.md** - Includes the BlingText-inspired 3D text features

Remember: The specs are living documents. Update them as you discover better approaches during implementation!