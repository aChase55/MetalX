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
    
    // Create texture from text using Core Graphics (temporary solution)
    func createTextTexture(text: String, font: UIFont, color: UIColor, maxWidth: CGFloat) -> MTLTexture? {
        // Render at 2x resolution for better quality when scaled
        let scale: CGFloat = 2.0
        
        // Create larger font for high-res rendering
        let scaledFont = font.withSize(font.pointSize * scale)
        
        // Calculate text size
        let attributes: [NSAttributedString.Key: Any] = [
            .font: scaledFont,
            .foregroundColor: color
        ]
        
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.boundingRect(
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
            print("Failed to create CGContext for text")
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
        context.setTextDrawingMode(.fill)
        UIGraphicsPushContext(context)
        attributedString.draw(at: CGPoint(x: padding, y: padding))
        UIGraphicsPopContext()
        
        // Create texture from context
        guard let image = context.makeImage() else {
            print("Failed to create CGImage from context")
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
            print("Failed to create Metal texture")
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
            if let commandQueue = device.makeCommandQueue(),
               let commandBuffer = commandQueue.makeCommandBuffer(),
               let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
                blitEncoder.generateMipmaps(for: texture)
                blitEncoder.endEncoding()
                commandBuffer.commit()
                commandBuffer.waitUntilCompleted()
            }
            
            print("Created text texture: \(texture.width)x\(texture.height), format: \(texture.pixelFormat.rawValue)")
        }
        
        return texture
    }
}