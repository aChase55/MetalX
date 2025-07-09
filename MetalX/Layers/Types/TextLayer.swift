import UIKit
import Metal
import MetalKit
import CoreText

class TextLayer: BaseLayer {
    var text: String = "Text" {
        didSet {
            updateTexture()
        }
    }
    
    var font: UIFont = UIFont.systemFont(ofSize: 48, weight: .medium) {
        didSet {
            updateTexture()
        }
    }
    
    var textColor: UIColor = .white {
        didSet {
            updateTexture()
        }
    }
    
    var backgroundColor: UIColor = .clear {
        didSet {
            updateTexture()
        }
    }
    
    private(set) var texture: MTLTexture?
    private var textRenderer: SimpleTextRenderer?
    private var device: MTLDevice?
    
    init(text: String = "Text") {
        super.init()
        self.device = MTLCreateSystemDefaultDevice()
        if let device = device {
            self.textRenderer = SimpleTextRenderer(device: device)
        }
        self.name = "Text Layer"
        self.text = text  // This will trigger updateTexture via didSet
    }
    
    private func updateTexture() {
        guard let textRenderer = textRenderer else {
            print("TextLayer: No text renderer available")
            texture = nil
            bounds = .zero
            return
        }
        
        print("TextLayer: Creating texture for '\(text)'")
        
        // Create texture using the proper renderer
        texture = textRenderer.createTextTexture(
            text: text,
            font: font,
            color: textColor,
            maxWidth: 800 // Max width for text wrapping
        )
        
        if let texture = texture {
            // Update bounds based on texture size (accounting for 2x scale)
            bounds = CGRect(
                origin: .zero,
                size: CGSize(width: texture.width / 2, height: texture.height / 2)
            )
            print("TextLayer: Successfully created texture with size \(texture.width)x\(texture.height)")
            print("TextLayer: Bounds set to \(bounds)")
        } else {
            print("TextLayer: Failed to create texture")
            bounds = .zero
        }
    }
    
    override func render(context: RenderContext) -> MTLTexture? {
        return texture
    }
    
    // Force update texture (useful after changing multiple properties)
    func forceUpdateTexture() {
        updateTexture()
    }
}