# MetalX Development Setup Guide

## Required Tools

### Xcode Configuration
- **Xcode Version**: 15.0 or later
- **Command Line Tools**: Install via `xcode-select --install`
- **Additional Components**: Metal Developer Tools, GPU Frame Debugger

### Recommended Xcode Settings
```
Build Settings:
- Enable Bitcode: No
- Metal Language Version: 3.1
- Metal Fast Math: Yes (for Release)
- Optimization Level: -Os (Release), -O0 (Debug)

Diagnostics:
- Metal API Validation: Enabled (Debug only)
- Metal Shader Validation: Enabled (Debug only)
- GPU Frame Capture: Enabled
```

### Environment Variables for Development
```bash
# Enable Metal debugging
export METAL_DEVICE_WRAPPER_TYPE=1
export METAL_DEBUG_ERROR_MODE=0
export METAL_SHADER_VALIDATION=1

# Performance profiling
export METAL_CAPTURE_ENABLED=1
export MTL_SHADER_VALIDATION_ENABLE_CAPTURING=1
```

## VS Code Setup (for Claude Code or Alternative Development)

### Extensions
- Swift (official)
- Metal Shader Language
- ShaderLab (for syntax highlighting)
- GitLens
- Error Lens

### tasks.json
```json
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "Build Framework",
            "type": "shell",
            "command": "xcodebuild",
            "args": [
                "-scheme", "MetalX",
                "-configuration", "Debug",
                "-destination", "platform=iOS Simulator,OS=latest"
            ]
        },
        {
            "label": "Run Tests",
            "type": "shell",
            "command": "swift test"
        },
        {
            "label": "Build Shaders",
            "type": "shell",
            "command": "xcrun",
            "args": [
                "-sdk", "iphoneos",
                "metal", "-c",
                "${file}",
                "-o", "${fileDirname}/${fileBasenameNoExtension}.air"
            ]
        }
    ]
}
```

## Development Scripts

### Scripts/setup.sh
```bash
#!/bin/bash
# Initial project setup

echo "Setting up MetalX development environment..."

# Create directory structure
mkdir -p MetalX/{Core/{Engine,Pipeline,Memory,Math},Layers/{Base,Types,Effects},Effects/{Filters,Adjustments,Particles,Transitions},Timeline,Typography,UI,ML,Audio,Cloud,Shaders}
mkdir -p MetalXDemo/{Views,ViewModels,Resources}
mkdir -p MetalXTests/{Unit,Integration,Performance,Visual}
mkdir -p Scripts
mkdir -p Resources/{Shaders,Assets,TestData}

# Create git hooks
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
# Run swift-format before commit
swift-format -i -r MetalX/
# Run tests
swift test --filter MetalXTests.Unit
EOF
chmod +x .git/hooks/pre-commit

echo "Setup complete!"
```

### Scripts/generate_docs.sh
```bash
#!/bin/bash
# Generate documentation

swift doc generate MetalX \
    --module-name MetalX \
    --output docs/api \
    --format html
```

## Debugging Helpers

### MetalX/Core/Debug/DebugOverlay.swift
```swift
#if DEBUG
class DebugOverlay {
    static var enabled = true
    
    static func renderStats(in view: MTKView) {
        guard enabled else { return }
        
        // Show FPS
        // Show memory usage
        // Show GPU timing
        // Show active effects count
    }
}
#endif
```

### Metal Shader Debugging Macros
```metal
// Shaders/Debug.metal
#define DEBUG_COLOR(condition, color) \
    if (condition) { return color; }

#define SHOW_NORMALS \
    return float4(normal * 0.5 + 0.5, 1.0);

#define SHOW_UV \
    return float4(uv, 0.0, 1.0);
```

## Simulator Limitations

### Known Simulator Issues
- No Neural Engine (Core ML runs on CPU)
- Different GPU architecture (not TBDR)
- No hardware video encoding
- Limited memory compared to devices
- Particle systems run slower

### Device Testing Matrix
```yaml
minimum_devices:
  - iPhone 12 (A14, 4GB RAM)
  - iPad Air 4 (A14, 4GB RAM)

recommended_devices:
  - iPhone 13 Pro (A15, 6GB RAM)
  - iPhone 15 Pro (A17 Pro, 8GB RAM)
  - iPad Pro M2 (M2, 8GB+ RAM)

ios_versions:
  - iOS 16.0 (minimum)
  - iOS 17.0 (recommended)
  - iOS 18.0 (latest features)
```