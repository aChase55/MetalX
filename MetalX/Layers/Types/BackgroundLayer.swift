import Foundation
import UIKit
import Metal
import MetalKit
import CoreGraphics
import simd

// Background layer that covers the entire canvas
class BackgroundLayer: BaseLayer {
    enum FillType {
        case solid(CGColor)
        case gradient(Gradient)
        case image(UIImage)
    }
    
    var fillType: FillType = .solid(UIColor.white.cgColor) {
        didSet {
            invalidateRenderCache()
        }
    }
    
    private weak var canvas: Canvas?
    private var cachedTexture: MTLTexture?
    private var cachedFillType: String = ""
    
    // Cached pipelines for gradient rendering
    private var gradientLinearPSO: MTLRenderPipelineState?
    private var gradientRadialPSO: MTLRenderPipelineState?
    private var gradientAngularPSO: MTLRenderPipelineState?
    
    // Vertex descriptor for a simple quad (float2 positions)
    private lazy var quadVertexDescriptor: MTLVertexDescriptor = {
        let vd = MTLVertexDescriptor()
        vd.attributes[0].format = .float2
        vd.attributes[0].offset = 0
        vd.attributes[0].bufferIndex = 0
        vd.layouts[0].stride = MemoryLayout<SIMD2<Float>>.stride
        return vd
    }()
    
    init(canvas: Canvas) {
        self.canvas = canvas
        super.init()
        self.name = "Background"
        self.isLocked = true // Background should typically stay locked
        self.zIndex = -1000 // Always render first
        updateBoundsToCanvas()
    }
    
    // Background layers are internal and shown differently in UI
    override var isInternal: Bool { true }
    
    override func render(context: RenderContext) -> MTLTexture? {
        guard let canvas = canvas else { return nil }
        
        // Update bounds if canvas size changed
        if bounds.size != canvas.size {
            updateBoundsToCanvas()
            cachedTexture = nil
        }
        
        // Check if we need to re-render
        let currentFillType = fillTypeDescription
        if let cached = cachedTexture,
           cached.width == Int(canvas.size.width),
           cached.height == Int(canvas.size.height),
           cachedFillType == currentFillType {
            return cached
        }
        
        // Create texture matching canvas size
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: Int(canvas.size.width),
            height: Int(canvas.size.height),
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        
        guard let texture = context.device.device.makeTexture(descriptor: descriptor),
              let commandBuffer = context.device.commandQueue.makeCommandBuffer() else {
            return nil
        }
        
        // Render based on fill type
        switch fillType {
        case .solid(let color):
            renderSolidColor(color, to: texture, commandBuffer: commandBuffer)
            
        case .gradient(let gradient):
            renderGradient(gradient, to: texture, context: context, commandBuffer: commandBuffer)
            
        case .image(let image):
            renderImage(image, to: texture, context: context, commandBuffer: commandBuffer)
        }
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        cachedTexture = texture
        cachedFillType = currentFillType
        
        return texture
    }
    
    private func renderSolidColor(_ color: CGColor, to texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        
        let components = color.components ?? [0, 0, 0, 1]
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: Double(components[safe: 0] ?? 0),
            green: Double(components[safe: 1] ?? 0),
            blue: Double(components[safe: 2] ?? 0),
            alpha: Double(components[safe: 3] ?? 1)
        )
        
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        encoder.endEncoding()
    }
    
    private func renderGradient(_ gradient: Gradient, to texture: MTLTexture, context: RenderContext, commandBuffer: MTLCommandBuffer) {
        guard let device = context.device.device.mxMakeDefaultLibrary()?.device else {
            // Fallback to solid first color if library unavailable
            if let first = gradient.colorStops.first?.color {
                renderSolidColor(first, to: texture, commandBuffer: commandBuffer)
            }
            return
        }
        
        // Lazily set up pipeline states
        if gradientLinearPSO == nil || gradientRadialPSO == nil || gradientAngularPSO == nil {
            setupGradientPipelines(device: device)
        }
        
        // Choose pipeline based on gradient type
        let pso: MTLRenderPipelineState?
        switch gradient.type {
        case .linear: pso = gradientLinearPSO
        case .radial: pso = gradientRadialPSO
        case .angular: pso = gradientAngularPSO
        }
        guard let pipelineState = pso else { return }
        
        // Prepare encoder
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        
        // Full-quad vertices in pixel space centered at (0,0): [-w/2..w/2]
        let w = Float(texture.width)
        let h = Float(texture.height)
        let halfW = w * 0.5
        let halfH = h * 0.5
        var quad: [SIMD2<Float>] = [
            SIMD2<Float>(-halfW, -halfH),
            SIMD2<Float>( halfW, -halfH),
            SIMD2<Float>(-halfW,  halfH),
            SIMD2<Float>( halfW,  halfH),
        ]
        // Transform from pixel to NDC (-1..1)
        let pixelToNDC = SIMD2<Float>(2.0 / w, -2.0 / h)
        var transform = matrix_identity_float4x4
        transform.columns.0.x = pixelToNDC.x
        transform.columns.1.y = pixelToNDC.y
        
        // Build gradient uniforms
        struct GradientUniforms
        {
            var transform: matrix_float4x4
            var color0,color1,color2,color3,color4,color5,color6,color7: SIMD4<Float>
            var location0,location1,location2,location3,location4,location5,location6,location7: Float
            var colorCount: Int32
            var gradientType: Int32
            var startPoint: SIMD2<Float>
            var endPoint: SIMD2<Float>
        }
        func colorToSIMD(_ c: CGColor) -> SIMD4<Float> {
            let comps = c.components ?? [0,0,0,1]
            let r = Float(comps[safe: 0] ?? 0)
            let g = Float(comps[safe: 1] ?? 0)
            let b = Float((comps.count > 2 ? comps[2] : comps[0]))
            let a = Float(comps.last ?? 1)
            return SIMD4<Float>(r,g,b,a)
        }
        var u = GradientUniforms(
            transform: transform,
            color0: .zero, color1: .zero, color2: .zero, color3: .zero,
            color4: .zero, color5: .zero, color6: .zero, color7: .zero,
            location0: 0, location1: 0, location2: 0, location3: 0,
            location4: 0, location5: 0, location6: 0, location7: 0,
            colorCount: Int32(min(gradient.colorStops.count, 8)),
            gradientType: 0,
            startPoint: SIMD2<Float>(Float(gradient.startPoint.x), Float(gradient.startPoint.y)),
            endPoint: SIMD2<Float>(Float(gradient.endPoint.x), Float(gradient.endPoint.y))
        )
        for (idx, stop) in gradient.colorStops.prefix(8).enumerated() {
            let col = colorToSIMD(stop.color)
            switch idx {
            case 0: u.color0 = col; u.location0 = stop.location
            case 1: u.color1 = col; u.location1 = stop.location
            case 2: u.color2 = col; u.location2 = stop.location
            case 3: u.color3 = col; u.location3 = stop.location
            case 4: u.color4 = col; u.location4 = stop.location
            case 5: u.color5 = col; u.location5 = stop.location
            case 6: u.color6 = col; u.location6 = stop.location
            case 7: u.color7 = col; u.location7 = stop.location
            default: break
            }
        }
        var shapeSize = SIMD2<Float>(w, h)
        
        // Set pipeline and resources
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBytes(&quad, length: MemoryLayout<SIMD2<Float>>.stride * quad.count, index: 0)
        encoder.setVertexBytes(&u, length: MemoryLayout<GradientUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&u, length: MemoryLayout<GradientUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&shapeSize, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
        
        // Draw as triangle strip
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
    }
    
    private func setupGradientPipelines(device: MTLDevice) {
        guard let library = device.mxMakeDefaultLibrary() else { return }
        func makePSO(fragment: String) -> MTLRenderPipelineState? {
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = library.makeFunction(name: "shapeVertex")
            desc.fragmentFunction = library.makeFunction(name: fragment)
            desc.vertexDescriptor = quadVertexDescriptor
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            desc.colorAttachments[0].isBlendingEnabled = false
            return try? device.makeRenderPipelineState(descriptor: desc)
        }
        gradientLinearPSO = makePSO(fragment: "shapeLinearGradient")
        gradientRadialPSO = makePSO(fragment: "shapeRadialGradient")
        gradientAngularPSO = makePSO(fragment: "shapeAngularGradient")
    }
    
    private func renderImage(_ image: UIImage, to texture: MTLTexture, context: RenderContext, commandBuffer: MTLCommandBuffer) {
        // Create texture from UIImage using MTKTextureLoader
        guard let cgImage = image.cgImage else { return }
        
        let textureLoader = MTKTextureLoader(device: context.device.device)
        guard let imageTexture = try? textureLoader.newTexture(cgImage: cgImage, options: [
            .SRGB: false,
            .generateMipmaps: false
        ]) else { return }
        
        // Calculate how to fit image to canvas
        let canvasSize = canvas?.size ?? .zero
        let imageSize = image.size
        
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        
        // Create a quad renderer
        let renderer = QuadRenderer(device: context.device.device)
        
        // Calculate transform to fit image
        var transform = matrix_identity_float4x4
        
        // Scale to fill canvas (you could also add fit/fill/stretch options)
        let scaleX = Float(canvasSize.width / imageSize.width)
        let scaleY = Float(canvasSize.height / imageSize.height)
        let scale = max(scaleX, scaleY) // Fill mode - use min for fit mode
        
        transform.columns.0.x = scale
        transform.columns.1.y = scale
        
        renderer.render(
            encoder: encoder,
            texture: imageTexture,
            transform: transform,
            opacity: 1.0,
            blendMode: .normal
        )
        
        encoder.endEncoding()
    }
    
    override func getBounds(includeEffects: Bool) -> CGRect {
        return bounds
    }
    
    override func hitTest(point: CGPoint) -> Bool {
        // Background always fills the canvas
        return bounds.contains(point)
    }
    
    func updateBoundsToCanvas() {
        guard let canvas = canvas else { return }
        
        self.bounds = CGRect(origin: .zero, size: canvas.size)
        self.transform.position = CGPoint(x: canvas.size.width / 2, y: canvas.size.height / 2)
        self.transform.scale = 1.0
        
        invalidateRenderCache()
    }
    
    private func invalidateRenderCache() {
        cachedTexture = nil
        NotificationCenter.default.post(name: NSNotification.Name("CanvasNeedsDisplay"), object: nil)
    }
    
    private var fillTypeDescription: String {
        switch fillType {
        case .solid(let color):
            return "solid:\(color.components?.description ?? "")"
        case .gradient(let gradient):
            return "gradient:\(gradient.colorStops.count)"
        case .image(let image):
            return "image:\(image.size)"
        }
    }
}
