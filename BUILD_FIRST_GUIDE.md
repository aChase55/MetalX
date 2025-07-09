# MetalX Build-First Implementation Guide

## ⚠️ CRITICAL: READ THIS FIRST

### Golden Rules for AI Coding Agents
1. **NEVER mark a task complete if the project has compile errors**
2. **BUILD after EVERY file you create or modify**
3. **Start with the SIMPLEST working version - optimize later**
4. **Use the EXISTING Xcode project at `/Users/alexchase/Developer/MetalX/MetalX.xcodeproj`**

### Build Command
```bash
cd /Users/alexchase/Developer/MetalX
xcodebuild -scheme MetalX -destination 'platform=iOS Simulator,name=iPhone 15' build
```

## 🎯 Goal: Get Something Visible ASAP

We want to see an image on screen within the first hour. Everything else comes later.

## Phase 1: Minimal Working App (Day 1)

### Task 1.1: Create Basic Image Display
**File**: `MetalX/Core/SimpleImageView.swift`
```swift
import SwiftUI
import MetalKit

// SIMPLE VERSION - NO OPTIMIZATION
struct SimpleImageView: UIViewRepresentable {
    let image: UIImage
    
    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.delegate = context.coordinator
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.image = image
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(image: image)
    }
    
    class Coordinator: NSObject, MTKViewDelegate {
        var image: UIImage
        var device: MTLDevice?
        var commandQueue: MTLCommandQueue?
        var texture: MTLTexture?
        
        init(image: UIImage) {
            self.image = image
            super.init()
            setupMetal()
            loadTexture()
        }
        
        func setupMetal() {
            device = MTLCreateSystemDefaultDevice()
            commandQueue = device?.makeCommandQueue()
        }
        
        func loadTexture() {
            // SIMPLE VERSION - just get it working
            guard let device = device,
                  let cgImage = image.cgImage else { return }
            
            let textureLoader = MTKTextureLoader(device: device)
            texture = try? textureLoader.newTexture(cgImage: cgImage, options: nil)
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        
        func draw(in view: MTKView) {
            // SIMPLE VERSION - just clear to red to verify it's working
            guard let drawable = view.currentDrawable,
                  let descriptor = view.currentRenderPassDescriptor else { return }
            
            descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 1, green: 0, blue: 0, alpha: 1)
            
            let commandBuffer = commandQueue?.makeCommandBuffer()
            let encoder = commandBuffer?.makeRenderCommandEncoder(descriptor: descriptor)
            encoder?.endEncoding()
            
            commandBuffer?.present(drawable)
            commandBuffer?.commit()
        }
    }
}
```

**BUILD AND TEST** ✓

### Task 1.2: Create Demo App
**File**: `MetalXDemo/ContentView.swift`
```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Text("MetalX Demo")
                .font(.title)
            
            // Red rectangle should appear if Metal is working
            SimpleImageView(image: UIImage(systemName: "photo")!)
                .frame(width: 300, height: 300)
                .border(Color.blue, width: 2)
        }
    }
}
```

**BUILD AND RUN** - You should see a red rectangle. If not, STOP and fix.

### Task 1.3: Display Actual Image
Now modify the `draw` function in `SimpleImageView.swift` to show the image:

```swift
func draw(in view: MTKView) {
    // Only proceed once the simple red clear is working
    guard let drawable = view.currentDrawable,
          let descriptor = view.currentRenderPassDescriptor,
          let texture = texture else { return }
    
    // For now, just clear to white - we'll add image rendering next
    descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 1, green: 1, blue: 1, alpha: 1)
    
    let commandBuffer = commandQueue?.makeCommandBuffer()
    let encoder = commandBuffer?.makeRenderCommandEncoder(descriptor: descriptor)
    
    // TODO: Add simple quad rendering here
    
    encoder?.endEncoding()
    commandBuffer?.present(drawable)
    commandBuffer?.commit()
}
```

**BUILD** - Should still work, now showing white instead of red.

## Phase 2: Basic Image Rendering (Day 2)

### Task 2.1: Create Simple Shaders
**File**: `MetalX/Shaders/Simple.metal`
```metal
#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut simpleVertex(VertexIn in [[stage_in]]) {
    VertexOut out;
    out.position = float4(in.position, 0.0, 1.0);
    out.texCoord = in.texCoord;
    return out;
}

fragment float4 simpleFragment(VertexOut in [[stage_in]],
                               texture2d<float> texture [[texture(0)]],
                               sampler textureSampler [[sampler(0)]]) {
    return texture.sample(textureSampler, in.texCoord);
}
```

**BUILD** - Fix any Metal compilation errors before proceeding.

### Task 2.2: Create Quad Renderer
**File**: `MetalX/Core/QuadRenderer.swift`
```swift
import Metal
import MetalKit

// SIMPLE VERSION - Just render a textured quad
class QuadRenderer {
    let device: MTLDevice
    var pipelineState: MTLRenderPipelineState?
    var vertexBuffer: MTLBuffer?
    var indexBuffer: MTLBuffer?
    
    init(device: MTLDevice) {
        self.device = device
        setupPipeline()
        setupBuffers()
    }
    
    func setupPipeline() {
        // SIMPLE - No error handling yet, just crash if it fails
        let library = device.makeDefaultLibrary()!
        let vertexFunction = library.makeFunction(name: "simpleVertex")!
        let fragmentFunction = library.makeFunction(name: "simpleFragment")!
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        pipelineState = try! device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    func setupBuffers() {
        // Simple quad vertices
        let vertices: [Float] = [
            -1.0, -1.0, 0.0, 1.0,  // bottom left
             1.0, -1.0, 1.0, 1.0,  // bottom right
             1.0,  1.0, 1.0, 0.0,  // top right
            -1.0,  1.0, 0.0, 0.0   // top left
        ]
        
        let indices: [UInt16] = [0, 1, 2, 2, 3, 0]
        
        vertexBuffer = device.makeBuffer(bytes: vertices,
                                         length: vertices.count * MemoryLayout<Float>.size,
                                         options: [])
        
        indexBuffer = device.makeBuffer(bytes: indices,
                                        length: indices.count * MemoryLayout<UInt16>.size,
                                        options: [])
    }
    
    func render(encoder: MTLRenderCommandEncoder, texture: MTLTexture) {
        encoder.setRenderPipelineState(pipelineState!)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        
        // Simple nearest neighbor sampling for now
        let sampler = MTLSamplerDescriptor()
        sampler.minFilter = .nearest
        sampler.magFilter = .nearest
        let samplerState = device.makeSamplerState(descriptor: sampler)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        
        encoder.drawIndexedPrimitives(type: .triangle,
                                      indexCount: 6,
                                      indexType: .uint16,
                                      indexBuffer: indexBuffer!,
                                      indexBufferOffset: 0)
    }
}
```

**BUILD** - Must compile without errors.

### Task 2.3: Wire It Up
Update `SimpleImageView.swift` to use the renderer:

```swift
class Coordinator: NSObject, MTKViewDelegate {
    var quadRenderer: QuadRenderer?
    
    func setupMetal() {
        device = MTLCreateSystemDefaultDevice()
        commandQueue = device?.makeCommandQueue()
        if let device = device {
            quadRenderer = QuadRenderer(device: device)
        }
    }
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let texture = texture,
              let quadRenderer = quadRenderer else { return }
        
        let commandBuffer = commandQueue?.makeCommandBuffer()
        let encoder = commandBuffer?.makeRenderCommandEncoder(descriptor: descriptor)
        
        quadRenderer.render(encoder: encoder!, texture: texture)
        
        encoder?.endEncoding()
        commandBuffer?.present(drawable)
        commandBuffer?.commit()
    }
}
```

**BUILD AND RUN** - You should now see your image!

## Phase 3: Basic Adjustments (Day 3)

Only start this after Phase 2 is working perfectly.

### Task 3.1: Add Brightness Control
**File**: `MetalX/Effects/BrightnessEffect.swift`
```swift
import Metal

struct BrightnessEffect {
    var brightness: Float = 0.0 // -1 to 1
    
    func apply(to texture: MTLTexture, device: MTLDevice) -> MTLTexture {
        // SIMPLE VERSION - modify the fragment shader
        // We'll implement this after basic rendering works
        return texture // For now, just return unchanged
    }
}
```

## 🚫 What NOT to Do (Yet)

1. **NO memory optimization** - Just let iOS handle it
2. **NO complex architecture** - One file per feature is fine
3. **NO error handling** - Use `try!` and `!` for now
4. **NO performance monitoring** - Get it working first
5. **NO fancy effects** - Start with brightness/contrast only
6. **NO video** - Images only for the first week
7. **NO layers** - Single image editing first

## Daily Validation Checklist

Before marking ANY task complete:
- [ ] Project builds without warnings or errors
- [ ] App runs on simulator
- [ ] New feature is visible/testable in the app
- [ ] Committed working code to git

## Troubleshooting Build Errors

### "No such module 'MetalX'"
- Make sure you're building the right scheme
- Check that files are added to the correct target

### "Use of unresolved identifier"
- File might not be added to target
- May need to import the module

### Metal shader errors
- Check shader syntax carefully
- Make sure .metal files are in the project

### "Device is nil"
- Simulator might not support Metal
- Try a different simulator or real device

## Next Steps (Only After Image Display Works)

1. Add brightness/contrast adjustment
2. Add a slider to control brightness
3. Save edited image
4. Add second effect (blur)
5. Then and only then, look at the architecture specs

Remember: **A working app with one feature is better than a non-compiling app with perfect architecture!**