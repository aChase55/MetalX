import SwiftUI
import MetalKit

struct MetalView: UIViewRepresentable {
    let renderEngine: RenderEngine
    
    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = renderEngine.device.device
        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false
        mtkView.delegate = context.coordinator
        mtkView.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MTKViewDelegate {
        let parent: MetalView
        var pipelineState: MTLRenderPipelineState?
        
        init(_ parent: MetalView) {
            self.parent = parent
            super.init()
            setupPipeline()
        }
        
        func setupPipeline() {
            let device = parent.renderEngine.device.device
            
            // Get the default library
            guard let library = device.makeDefaultLibrary() else { return }
            
            // Get shader functions
            guard let vertexFunction = library.makeFunction(name: "simpleQuadVertex"),
                  let fragmentFunction = library.makeFunction(name: "simpleQuadFragment") else { return }
            
            // Create pipeline descriptor
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragmentFunction
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            
            // Create pipeline state
            do {
                pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            } catch {
                print("Failed to create pipeline state: \(error)")
            }
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        
        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let renderPassDescriptor = view.currentRenderPassDescriptor,
                  let pipelineState = pipelineState else { return }
            
            // Create command buffer
            guard let commandBuffer = parent.renderEngine.device.makeCommandBuffer(label: "Draw") else { return }
            
            // Create render encoder
            guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
            
            // Set pipeline state and draw
            renderEncoder.setRenderPipelineState(pipelineState)
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            
            renderEncoder.endEncoding()
            
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}