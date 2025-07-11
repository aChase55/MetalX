import Metal
import MetalKit
import CoreGraphics
import UIKit

// Simplified text renderer that works now but can be extended
class SimpleTextRenderer {
    private let device: MTLDevice
    
    init(device: MTLDevice) {
        self.device = device
    }
    
    // Create texture from text using Core Graphics
    func createTextTexture(text: String, font: UIFont, fillType: TextFillType, maxWidth: CGFloat, hasOutline: Bool = false, outlineColor: UIColor = .black, outlineWidth: CGFloat = 2.0) -> MTLTexture? {
        // Render at 2x resolution for better quality when scaled
        let scale: CGFloat = 2.0
        
        // Create larger font for high-res rendering
        let scaledFont = font.withSize(font.pointSize * scale)
        
        // Calculate text size using a temporary color for sizing
        let tempAttributes: [NSAttributedString.Key: Any] = [
            .font: scaledFont,
            .foregroundColor: UIColor.black
        ]
        
        let sizingString = NSAttributedString(string: text, attributes: tempAttributes)
        let textSize = sizingString.boundingRect(
            with: CGSize(width: maxWidth * scale, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).size
        
        // Add padding (scaled)
        let padding: CGFloat = 4 * scale
        let textureSize = CGSize(
            width: ceil(textSize.width + padding * 2),
            height: ceil(textSize.height + padding * 2)
        )
        
        // Create bitmap context with proper alpha support
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(textureSize.width),
            height: Int(textureSize.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(textureSize.width) * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return nil
        }
        
        // Flip coordinate system
        context.translateBy(x: 0, y: textureSize.height)
        context.scaleBy(x: 1, y: -1)
        
        // Clear to transparent
        context.clear(CGRect(origin: .zero, size: textureSize))
        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 0)
        context.fill(CGRect(origin: .zero, size: textureSize))
        
        // Draw text with proper context setup
        UIGraphicsPushContext(context)
        
        // Prepare drawing position
        let drawPoint = CGPoint(x: padding, y: padding)
        
        switch fillType {
        case .solid(let color):
            if hasOutline {
                // For outline with solid fill
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: scaledFont,
                    .strokeColor: outlineColor,
                    .strokeWidth: -(outlineWidth * scale), // Negative for both stroke and fill
                    .foregroundColor: color
                ]
                let string = NSAttributedString(string: text, attributes: attributes)
                string.draw(at: drawPoint)
            } else {
                // Regular solid text
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: scaledFont,
                    .foregroundColor: color
                ]
                let string = NSAttributedString(string: text, attributes: attributes)
                string.draw(at: drawPoint)
            }
            
        case .none:
            // Outline only (no fill)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: scaledFont,
                .strokeColor: outlineColor,
                .strokeWidth: outlineWidth * scale, // Positive for stroke only
                .foregroundColor: UIColor.clear
            ]
            let string = NSAttributedString(string: text, attributes: attributes)
            string.draw(at: drawPoint)
            
        case .gradient(let colors, let startPoint, let endPoint):
            // Create gradient
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let cgColors = colors.map { $0.cgColor }
            
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: cgColors as CFArray, locations: nil) {
                context.saveGState()
                
                // Draw text to create clipping mask
                context.setTextDrawingMode(.clip)
                let attributes: [NSAttributedString.Key: Any] = [.font: scaledFont]
                let string = NSAttributedString(string: text, attributes: attributes)
                string.draw(at: drawPoint)
                
                // Draw gradient
                let gradientStart = CGPoint(
                    x: padding + textSize.width * startPoint.x, 
                    y: padding + textSize.height * startPoint.y
                )
                let gradientEnd = CGPoint(
                    x: padding + textSize.width * endPoint.x, 
                    y: padding + textSize.height * endPoint.y
                )
                context.drawLinearGradient(gradient, start: gradientStart, end: gradientEnd, options: [])
                
                context.restoreGState()
                
                // Draw outline if needed
                if hasOutline {
                    let outlineAttributes: [NSAttributedString.Key: Any] = [
                        .font: scaledFont,
                        .strokeColor: outlineColor,
                        .strokeWidth: outlineWidth * scale,
                        .foregroundColor: UIColor.clear
                    ]
                    let outlineString = NSAttributedString(string: text, attributes: outlineAttributes)
                    outlineString.draw(at: drawPoint)
                }
            }
            
        case .image(let image):
            if let cgImage = image.cgImage {
                context.saveGState()
                
                // Draw text to create clipping mask
                context.setTextDrawingMode(.clip)
                let attributes: [NSAttributedString.Key: Any] = [.font: scaledFont]
                let string = NSAttributedString(string: text, attributes: attributes)
                string.draw(at: drawPoint)
                
                // Draw image
                let drawRect = CGRect(x: padding, y: padding, width: textSize.width, height: textSize.height)
                context.draw(cgImage, in: drawRect)
                
                context.restoreGState()
                
                // Draw outline if needed
                if hasOutline {
                    let outlineAttributes: [NSAttributedString.Key: Any] = [
                        .font: scaledFont,
                        .strokeColor: outlineColor,
                        .strokeWidth: outlineWidth * scale,
                        .foregroundColor: UIColor.clear
                    ]
                    let outlineString = NSAttributedString(string: text, attributes: outlineAttributes)
                    outlineString.draw(at: drawPoint)
                }
            }
        }
        
        UIGraphicsPopContext()
        
        // Create texture from context
        guard let image = context.makeImage() else {
            return nil
        }
        
        // Create Metal texture
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: Int(textureSize.width),
            height: Int(textureSize.height),
            mipmapped: true  // Enable mipmapping for better quality when scaled
        )
        textureDescriptor.usage = [.shaderRead]
        
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            return nil
        }
        
        // Copy image data to texture
        let region = MTLRegionMake2D(0, 0, Int(textureSize.width), Int(textureSize.height))
        if let data = image.dataProvider?.data {
            let bytes = CFDataGetBytePtr(data)
            texture.replace(
                region: region,
                mipmapLevel: 0,
                withBytes: bytes!,
                bytesPerRow: Int(textureSize.width) * 4
            )
            
            // Generate mipmaps for better quality when scaled
            // Only generate mipmaps if texture has multiple mip levels
            if texture.mipmapLevelCount > 1,
               let commandQueue = device.makeCommandQueue(),
               let commandBuffer = commandQueue.makeCommandBuffer(),
               let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
                blitEncoder.generateMipmaps(for: texture)
                blitEncoder.endEncoding()
                commandBuffer.commit()
                commandBuffer.waitUntilCompleted()
            }
        }
        
        return texture
    }
}