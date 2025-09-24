import Metal
import MetalKit
import simd

// Quad renderer for textured quads with blend modes
class QuadRenderer {
    let device: MTLDevice
    var pipelineStates: [BlendMode: MTLRenderPipelineState] = [:]
    var selectionPipelineState: MTLRenderPipelineState?
    var vertexBuffer: MTLBuffer?
    var indexBuffer: MTLBuffer?
    
    init(device: MTLDevice) {
        self.device = device
        setupPipeline()
        setupBuffers()
    }
    
    func setupPipeline() {
        // SIMPLE - No error handling yet, just crash if it fails
        guard let library = device.mxMakeDefaultLibrary() else {
            fatalError("MetalX: Failed to load default shader library")
        }
        let vertexFunction = library.makeFunction(name: "quadVertex")!
        let fragmentFunction = library.makeFunction(name: "quadFragment")!
        
        // Setup vertex descriptor once
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.size * 2
        vertexDescriptor.attributes[1].bufferIndex = 0
        
        vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.size * 4
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        
        // Create pipeline state for each blend mode
        for blendMode in BlendMode.allCases {
            let descriptor = MTLRenderPipelineDescriptor()
            
            // For now, use quad fragment shader for all modes
            // Advanced blend modes would require render-to-texture
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.vertexDescriptor = vertexDescriptor
            
            // Configure blending based on mode
            let colorAttachment = descriptor.colorAttachments[0]!
            colorAttachment.isBlendingEnabled = true
            
            switch blendMode {
            case .normal:
                colorAttachment.sourceRGBBlendFactor = .sourceAlpha
                colorAttachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
                colorAttachment.sourceAlphaBlendFactor = .sourceAlpha
                colorAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                colorAttachment.rgbBlendOperation = .add
                
            case .multiply:
                // With premultiplied alpha:
                // - Opaque pixels: src.rgb * dst.rgb + dst.rgb * 0 = multiply effect
                // - Transparent pixels: 0 * dst.rgb + dst.rgb * 1 = unchanged destination
                // This preserves the destination where source is transparent
                colorAttachment.sourceRGBBlendFactor = .destinationColor
                colorAttachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
                colorAttachment.sourceAlphaBlendFactor = .destinationAlpha
                colorAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                colorAttachment.rgbBlendOperation = .add
                
            case .screen:
                // Screen blend: result = 1 - (1 - src) * (1 - dst)
                // With premultiplied alpha, this becomes: src + dst - src * dst
                // But we need to account for alpha to preserve transparency
                colorAttachment.sourceRGBBlendFactor = .one
                colorAttachment.destinationRGBBlendFactor = .oneMinusSourceColor
                colorAttachment.sourceAlphaBlendFactor = .one
                colorAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                colorAttachment.rgbBlendOperation = .add
                
            case .overlay:
                // Overlay is a combination of multiply and screen
                // We'll approximate with a mix based on source
                colorAttachment.sourceRGBBlendFactor = .sourceAlpha
                colorAttachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
                colorAttachment.sourceAlphaBlendFactor = .sourceAlpha
                colorAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                colorAttachment.rgbBlendOperation = .add
                
            case .darken:
                // For darken with transparency, we need to blend the effect
                // This is an approximation that respects alpha
                colorAttachment.sourceRGBBlendFactor = .oneMinusDestinationColor
                colorAttachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
                colorAttachment.sourceAlphaBlendFactor = .sourceAlpha
                colorAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                colorAttachment.rgbBlendOperation = .add
                
            case .lighten:
                // For lighten with transparency, blend towards lighter colors
                // This approximation adds source where it's lighter
                colorAttachment.sourceRGBBlendFactor = .sourceAlpha
                colorAttachment.destinationRGBBlendFactor = .one
                colorAttachment.sourceAlphaBlendFactor = .sourceAlpha
                colorAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                colorAttachment.rgbBlendOperation = .add
                
            case .colorDodge:
                // Color dodge brightens - approximate with additive blend
                colorAttachment.sourceRGBBlendFactor = .sourceAlpha
                colorAttachment.destinationRGBBlendFactor = .one
                colorAttachment.sourceAlphaBlendFactor = .sourceAlpha
                colorAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                colorAttachment.rgbBlendOperation = .add
                
            case .colorBurn:
                // Color burn darkens - approximate with subtractive blend
                colorAttachment.sourceRGBBlendFactor = .zero
                colorAttachment.destinationRGBBlendFactor = .oneMinusSourceColor
                colorAttachment.sourceAlphaBlendFactor = .sourceAlpha
                colorAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                colorAttachment.rgbBlendOperation = .add
                
            case .difference:
                // Difference would need |src - dst|, approximate with subtract
                colorAttachment.sourceRGBBlendFactor = .sourceAlpha
                colorAttachment.destinationRGBBlendFactor = .one
                colorAttachment.sourceAlphaBlendFactor = .sourceAlpha
                colorAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                colorAttachment.rgbBlendOperation = .reverseSubtract
                
            case .exclusion:
                // Exclusion = src + dst - 2*src*dst, approximate with screen-like
                colorAttachment.sourceRGBBlendFactor = .oneMinusDestinationColor
                colorAttachment.destinationRGBBlendFactor = .oneMinusSourceColor
                colorAttachment.sourceAlphaBlendFactor = .sourceAlpha
                colorAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                colorAttachment.rgbBlendOperation = .add
                
            case .softLight:
                // Soft light is like overlay but softer, use normal blend
                colorAttachment.sourceRGBBlendFactor = .sourceAlpha
                colorAttachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
                colorAttachment.sourceAlphaBlendFactor = .sourceAlpha
                colorAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                colorAttachment.rgbBlendOperation = .add
                
            case .hardLight:
                // Hard light is overlay with src/dst swapped, approximate
                colorAttachment.sourceRGBBlendFactor = .destinationColor
                colorAttachment.destinationRGBBlendFactor = .sourceColor
                colorAttachment.sourceAlphaBlendFactor = .sourceAlpha
                colorAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                colorAttachment.rgbBlendOperation = .add
            }
            
            pipelineStates[blendMode] = try! device.makeRenderPipelineState(descriptor: descriptor)
        }
        
        // Setup selection pipeline
        if let selectionVertex = library.makeFunction(name: "selectionVertex"),
           let selectionFragment = library.makeFunction(name: "selectionFragment") {
            let selectionDescriptor = MTLRenderPipelineDescriptor()
            selectionDescriptor.vertexFunction = selectionVertex
            selectionDescriptor.fragmentFunction = selectionFragment
            selectionDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            
            // Enable alpha blending for the outline
            selectionDescriptor.colorAttachments[0].isBlendingEnabled = true
            selectionDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            selectionDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            selectionDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            selectionDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            
            // Selection uses same vertex format as main shader
            selectionDescriptor.vertexDescriptor = vertexDescriptor
            
            selectionPipelineState = try? device.makeRenderPipelineState(descriptor: selectionDescriptor)
        }
    }
    
    func setupBuffers() {
        // Quad vertices (fixed texture coordinates)
        let vertices: [Float] = [
            -1.0, -1.0, 0.0, 0.0,  // bottom left
             1.0, -1.0, 1.0, 0.0,  // bottom right
             1.0,  1.0, 1.0, 1.0,  // top right
            -1.0,  1.0, 0.0, 1.0   // top left
        ]
        
        let indices: [UInt16] = [0, 1, 2, 2, 3, 0]
        
        vertexBuffer = device.makeBuffer(bytes: vertices,
                                         length: vertices.count * MemoryLayout<Float>.size,
                                         options: [])
        
        indexBuffer = device.makeBuffer(bytes: indices,
                                        length: indices.count * MemoryLayout<UInt16>.size,
                                        options: [])
    }
    
    func render(encoder: MTLRenderCommandEncoder, texture: MTLTexture, transform: simd_float4x4 = matrix_identity_float4x4, opacity: Float = 1.0, blendMode: BlendMode = .normal) {
        guard let pipelineState = pipelineStates[blendMode] else { return }
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        
        // Pass transform matrix as uniform
        var uniforms = transform
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<simd_float4x4>.size, index: 1)
        
        // Pass opacity as uniform
        var fragmentUniforms = simd_float4(opacity, 0, 0, 0)
        encoder.setFragmentBytes(&fragmentUniforms, length: MemoryLayout<simd_float4>.size, index: 1)
        
        encoder.setFragmentTexture(texture, index: 0)
        
        // Use linear filtering with mipmapping for better quality
        let sampler = MTLSamplerDescriptor()
        sampler.minFilter = .linear
        sampler.magFilter = .linear
        sampler.mipFilter = .linear  // Enable mipmap filtering
        let samplerState = device.makeSamplerState(descriptor: sampler)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        
        encoder.drawIndexedPrimitives(type: .triangle,
                                      indexCount: 6,
                                      indexType: .uint16,
                                      indexBuffer: indexBuffer!,
                                      indexBufferOffset: 0)
    }
    
    func renderSelection(encoder: MTLRenderCommandEncoder, transform: simd_float4x4, viewportSize: CGSize, time: Float) {
        guard let selectionPipelineState = selectionPipelineState else { return }
        
        encoder.setRenderPipelineState(selectionPipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)  // Use same vertex buffer
        
        // Pass uniforms
        struct SelectionUniforms {
            var transform: simd_float4x4
            var viewportSize: simd_float2
            var time: Float
            var padding: Float = 0
        }
        
        var uniforms = SelectionUniforms(
            transform: transform,
            viewportSize: simd_float2(Float(viewportSize.width), Float(viewportSize.height)),
            time: time
        )
        
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<SelectionUniforms>.size, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SelectionUniforms>.size, index: 0)
        
        // Draw as triangles for selection quad
        encoder.drawIndexedPrimitives(type: .triangle,
                                      indexCount: 6,
                                      indexType: .uint16,
                                      indexBuffer: indexBuffer!,
                                      indexBufferOffset: 0)
    }
}
