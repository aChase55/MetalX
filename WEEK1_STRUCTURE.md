# MetalX File Structure for Week 1

## What to Create First (In Order)

### Day 1: Minimal Display
```
MetalX/
├── Core/
│   └── SimpleImageView.swift    # Just display an image
MetalXDemo/
└── ContentView.swift           # Updated to show SimpleImageView
```

### Day 2: Basic Shader
```
MetalX/
├── Core/
│   ├── SimpleImageView.swift   # (updated)
│   └── QuadRenderer.swift      # Renders a quad with texture
└── Shaders/
    └── Simple.metal            # Basic vertex/fragment shaders
```

### Day 3: Adjustments
```
MetalX/
├── Core/
│   └── AdjustmentRenderer.swift # Handles brightness/contrast
└── Shaders/
    └── Adjustments.metal        # Brightness/contrast shaders
MetalXDemo/
└── AdjustmentView.swift         # UI with sliders
```

### Day 4: Save Function
```
MetalX/
├── Core/
│   └── ImageExporter.swift      # Render to texture & save
MetalXDemo/
└── ContentView.swift            # Add save button
```

### Day 5: Image Picker
```
MetalXDemo/
├── ContentView.swift            # Add picker button
└── ImagePicker.swift            # UIImagePickerController wrapper
```

## Example: SimpleImageView.swift (Day 1)

```swift
// MetalX/Core/SimpleImageView.swift
import SwiftUI
import MetalKit

public struct SimpleImageView: UIViewRepresentable {
    public let image: UIImage
    
    public init(image: UIImage) {
        self.image = image
    }
    
    public func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.delegate = context.coordinator
        mtkView.enableSetNeedsDisplay = true
        return mtkView
    }
    
    public func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.updateImage(image)
        uiView.setNeedsDisplay()
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    public class Coordinator: NSObject, MTKViewDelegate {
        private var device: MTLDevice?
        private var commandQueue: MTLCommandQueue?
        private var currentImage: UIImage?
        private var texture: MTLTexture?
        
        override init() {
            super.init()
            self.device = MTLCreateSystemDefaultDevice()
            self.commandQueue = device?.makeCommandQueue()
        }
        
        func updateImage(_ image: UIImage) {
            self.currentImage = image
            loadTexture()
        }
        
        private func loadTexture() {
            guard let device = device,
                  let image = currentImage,
                  let cgImage = image.cgImage else { return }
            
            let loader = MTKTextureLoader(device: device)
            self.texture = try? loader.newTexture(cgImage: cgImage, options: [
                .textureUsage: MTLTextureUsage.shaderRead.rawValue,
                .textureStorageMode: MTLStorageMode.private.rawValue
            ])
        }
        
        public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        
        public func draw(in view: MTKView) {
            // Start super simple - just clear to green to prove it works
            guard let drawable = view.currentDrawable,
                  let descriptor = view.currentRenderPassDescriptor else { return }
            
            // Green = Metal is working!
            descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 1, blue: 0, alpha: 1)
            
            let commandBuffer = commandQueue?.makeCommandBuffer()
            let encoder = commandBuffer?.makeRenderCommandEncoder(descriptor: descriptor)
            encoder?.endEncoding()
            
            commandBuffer?.present(drawable)
            commandBuffer?.commit()
        }
    }
}
```

## How to Verify It's Working

### Day 1 Check:
1. Build project: `xcodebuild -scheme MetalX build`
2. Run MetalXDemo in simulator
3. Should see a GREEN rectangle where image will be
4. If you see green = Metal is working! ✅

### Common Issues and Fixes:

**"Cannot find SimpleImageView in scope"**
- Make sure MetalX framework is imported in ContentView
- Check that SimpleImageView is marked `public`

**Black screen instead of green**
- Check MTKView delegate is set
- Verify device is not nil
- Try on different simulator

**Build errors**
- Don't use any complex Metal features yet
- Remove any optimization attempts
- Start with the exact code above

## What NOT to Create Yet

These directories should NOT exist in Week 1:
```
❌ MetalX/Pipeline/          # Too complex
❌ MetalX/Memory/            # Not needed yet  
❌ MetalX/Effects/Particles/ # Way too advanced
❌ MetalX/ML/                # Much later
❌ MetalX/Timeline/          # Video is Week 3+
```

## Success Criteria for Each Day

**Every day should end with:**
1. ✅ Project builds without errors
2. ✅ App runs in simulator
3. ✅ New feature is visible on screen
4. ✅ Screenshot of working feature
5. ✅ Commit to git

**If any of these fail:** Stop and fix before proceeding!