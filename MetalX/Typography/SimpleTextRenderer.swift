import Metal
import MetalKit
import CoreGraphics
import UIKit
import SwiftUI

// Simplified text renderer that works now but can be extended
class SimpleTextRenderer {
    private let device: MTLDevice
    
    init(device: MTLDevice) {
        self.device = device
    }
    
    // Create texture from text using Core Graphics
    func createTextTexture(
        text: String,
        font: UIFont,
        fillType: TextFillType,
        maxWidth: CGFloat,
        alignment: NSTextAlignment,
        hasOutline: Bool = false,
        outlineColor: UIColor = .black,
        outlineWidth: CGFloat = 2.0
    ) -> MTLTexture? {
        let scale: CGFloat = 2.0
        let scaledFont = font.withSize(font.pointSize * scale)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        let tempAttributes: [NSAttributedString.Key: Any] = [
            .font: scaledFont,
            .foregroundColor: UIColor.black,
            .paragraphStyle: paragraph
        ]
        let sizingString = NSAttributedString(string: text, attributes: tempAttributes)
        let textSize = sizingString.boundingRect(
            with: CGSize(width: maxWidth * scale, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).size
        let padding: CGFloat = 4 * scale
        let textureSize = CGSize(width: ceil(textSize.width + padding * 2), height: ceil(textSize.height + padding * 2))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(textureSize.width),
            height: Int(textureSize.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(textureSize.width) * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }
        context.translateBy(x: 0, y: textureSize.height)
        context.scaleBy(x: 1, y: -1)
        context.clear(CGRect(origin: .zero, size: textureSize))
        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 0)
        context.fill(CGRect(origin: .zero, size: textureSize))
        UIGraphicsPushContext(context)
        let drawRect = CGRect(x: padding, y: padding, width: textureSize.width - padding * 2, height: textureSize.height - padding * 2)
        switch fillType {
        case .solid(let color):
            if hasOutline {
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: scaledFont,
                    .strokeColor: outlineColor,
                    .strokeWidth: -(outlineWidth * scale),
                    .foregroundColor: color,
                    .paragraphStyle: paragraph
                ]
                let string = NSAttributedString(string: text, attributes: attributes)
                string.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            } else {
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: scaledFont,
                    .foregroundColor: color,
                    .paragraphStyle: paragraph
                ]
                let string = NSAttributedString(string: text, attributes: attributes)
                string.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            }
        case .none:
            var attributes: [NSAttributedString.Key: Any] = [
                .font: scaledFont,
                .strokeColor: outlineColor,
                .strokeWidth: outlineWidth * scale,
                .foregroundColor: UIColor.clear,
                .paragraphStyle: paragraph
            ]
            let string = NSAttributedString(string: text, attributes: attributes)
            string.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        case .gradient(let gradient):
            let gradientImage = createGradientImage(gradient: gradient, size: textureSize)
            if let gradientImage = gradientImage {
                let patternColor = UIColor(patternImage: gradientImage)
                if hasOutline {
                    var attributes: [NSAttributedString.Key: Any] = [
                        .font: scaledFont,
                        .strokeColor: outlineColor,
                        .strokeWidth: -(outlineWidth * scale),
                        .foregroundColor: patternColor,
                        .paragraphStyle: paragraph
                    ]
                    let string = NSAttributedString(string: text, attributes: attributes)
                    string.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                } else {
                    var attributes: [NSAttributedString.Key: Any] = [
                        .font: scaledFont,
                        .foregroundColor: patternColor,
                        .paragraphStyle: paragraph
                    ]
                    let string = NSAttributedString(string: text, attributes: attributes)
                    string.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                }
            }
        case .image(let image):
            UIGraphicsBeginImageContextWithOptions(textureSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: textureSize))
            let scaledImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
            UIGraphicsEndImageContext()
            let patternColor = UIColor(patternImage: scaledImage)
            if hasOutline {
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: scaledFont,
                    .strokeColor: outlineColor,
                    .strokeWidth: -(outlineWidth * scale),
                    .foregroundColor: patternColor,
                    .paragraphStyle: paragraph
                ]
                let string = NSAttributedString(string: text, attributes: attributes)
                string.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            } else {
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: scaledFont,
                    .foregroundColor: patternColor,
                    .paragraphStyle: paragraph
                ]
                let string = NSAttributedString(string: text, attributes: attributes)
                string.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            }
        }
        UIGraphicsPopContext()
        guard let image = context.makeImage() else { return nil }
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: Int(textureSize.width),
            height: Int(textureSize.height),
            mipmapped: true
        )
        textureDescriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else { return nil }
        let region = MTLRegionMake2D(0, 0, Int(textureSize.width), Int(textureSize.height))
        if let data = image.dataProvider?.data {
            let bytes = CFDataGetBytePtr(data)
            texture.replace(region: region, mipmapLevel: 0, withBytes: bytes!, bytesPerRow: Int(textureSize.width) * 4)
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
    
    private func createGradientImage(gradient: MetalX.Gradient, size: CGSize) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { _ in
            // Create SwiftUI gradient
            let stops = gradient.colorStops.map { stop in
                SwiftUI.Gradient.Stop(
                    color: Color(UIColor(cgColor: stop.color)),
                    location: CGFloat(stop.location)
                )
            }
            
            let swiftUIGradient = SwiftUI.Gradient(stops: stops)
            
            // Create the appropriate gradient view
            let gradientView: AnyView
            switch gradient.type {
            case .linear:
                gradientView = AnyView(
                    LinearGradient(
                        gradient: swiftUIGradient,
                        startPoint: UnitPoint(x: gradient.startPoint.x, y: gradient.startPoint.y),
                        endPoint: UnitPoint(x: gradient.endPoint.x, y: gradient.endPoint.y)
                    )
                )
            case .radial:
                gradientView = AnyView(
                    RadialGradient(
                        gradient: swiftUIGradient,
                        center: UnitPoint(x: gradient.startPoint.x, y: gradient.startPoint.y),
                        startRadius: 0,
                        endRadius: size.width / 2
                    )
                )
            case .angular:
                gradientView = AnyView(
                    AngularGradient(
                        gradient: swiftUIGradient,
                        center: UnitPoint(x: gradient.startPoint.x, y: gradient.startPoint.y)
                    )
                )
            }
            
            // Render SwiftUI view to UIKit context
            let controller = UIHostingController(rootView: gradientView)
            controller.view.bounds = CGRect(origin: .zero, size: size)
            controller.view.backgroundColor = .clear
            
            // Draw the view hierarchy
            controller.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
    }
}
