import Metal
import MetalKit
import CoreText
import UIKit

// Proper text rendering system that supports advanced features
class TextRenderer {
    private let device: MTLDevice
    private var fontAtlas: FontAtlas?
    private var textMeshGenerator: TextMeshGenerator
    
    init(device: MTLDevice) {
        self.device = device
        self.textMeshGenerator = TextMeshGenerator()
    }
    
    // Generate geometry for text
    func generateTextMesh(text: String, font: UIFont, bounds: CGSize) -> TextMesh {
        return textMeshGenerator.generateMesh(
            text: text,
            font: font,
            bounds: bounds
        )
    }
    
    // Render text using Metal
    func render(
        text: String,
        font: UIFont,
        color: UIColor,
        transform: simd_float4x4,
        encoder: MTLRenderCommandEncoder
    ) {
        // This will handle the actual Metal rendering
        // For now, we need to build the infrastructure
    }
}

// Text mesh data
struct TextMesh {
    let vertices: [TextVertex]
    let indices: [UInt16]
    let bounds: CGRect
}

struct TextVertex {
    let position: simd_float2
    let texCoord: simd_float2
    let color: simd_float4
}

// Generates mesh data from text
class TextMeshGenerator {
    func generateMesh(text: String, font: UIFont, bounds: CGSize) -> TextMesh {
        var vertices: [TextVertex] = []
        var indices: [UInt16] = []
        
        // Create attributed string
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font
        ]
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        
        // Create CTLine
        let line = CTLineCreateWithAttributedString(attributedString)
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        
        var currentX: Float = 0
        
        for run in runs {
            let glyphCount = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: glyphCount)
            var positions = [CGPoint](repeating: .zero, count: glyphCount)
            
            CTRunGetGlyphs(run, CFRange(location: 0, length: glyphCount), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: glyphCount), &positions)
            
            let runFont = CFDictionaryGetValue(
                CTRunGetAttributes(run),
                Unmanaged.passUnretained(kCTFontAttributeName).toOpaque()
            )
            let ctFont = runFont.map { Unmanaged<CTFont>.fromOpaque($0).takeUnretainedValue() }
            
            // Generate vertices for each glyph
            for i in 0..<glyphCount {
                let glyph = glyphs[i]
                let position = positions[i]
                
                // Get glyph bounds
                var glyphRect = CGRect()
                CTFontGetBoundingRectsForGlyphs(
                    ctFont ?? font as CTFont,
                    .default,
                    &glyphs[i],
                    &glyphRect,
                    1
                )
                
                // Add vertices for this glyph (simplified quad for now)
                let baseIndex = UInt16(vertices.count)
                let x = Float(position.x) + currentX
                let y = Float(position.y)
                
                // Bottom left
                vertices.append(TextVertex(
                    position: simd_float2(x, y),
                    texCoord: simd_float2(0, 1),
                    color: simd_float4(1, 1, 1, 1)
                ))
                
                // Bottom right
                vertices.append(TextVertex(
                    position: simd_float2(x + Float(glyphRect.width), y),
                    texCoord: simd_float2(1, 1),
                    color: simd_float4(1, 1, 1, 1)
                ))
                
                // Top right
                vertices.append(TextVertex(
                    position: simd_float2(x + Float(glyphRect.width), y + Float(glyphRect.height)),
                    texCoord: simd_float2(1, 0),
                    color: simd_float4(1, 1, 1, 1)
                ))
                
                // Top left
                vertices.append(TextVertex(
                    position: simd_float2(x, y + Float(glyphRect.height)),
                    texCoord: simd_float2(0, 0),
                    color: simd_float4(1, 1, 1, 1)
                ))
                
                // Add indices
                indices.append(contentsOf: [
                    baseIndex, baseIndex + 1, baseIndex + 2,
                    baseIndex + 2, baseIndex + 3, baseIndex
                ])
                
                currentX += Float(glyphRect.width)
            }
        }
        
        let textBounds = CTLineGetImageBounds(line, nil)
        
        return TextMesh(
            vertices: vertices,
            indices: indices,
            bounds: textBounds
        )
    }
}

// Font atlas for efficient glyph rendering
class FontAtlas {
    private let device: MTLDevice
    private var atlasTexture: MTLTexture?
    private var glyphCache: [CGGlyph: GlyphInfo] = [:]
    
    struct GlyphInfo {
        let textureRect: CGRect
        let glyphBounds: CGRect
    }
    
    init(device: MTLDevice) {
        self.device = device
    }
    
    // Generate atlas texture from font
    func generateAtlas(font: UIFont, fontSize: CGFloat) {
        // This would create a texture atlas with all glyphs
        // For advanced text rendering
    }
}