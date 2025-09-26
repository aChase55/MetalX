import UIKit
import Metal
import MetalKit
import CoreText
import Combine

class TextLayer: BaseLayer, ObservableObject {
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
    
    @Published var fillType: TextFillType = .solid(.white) {
        didSet {
            updateTexture()
        }
    }
    
    // Store the last solid color separately
    private var lastSolidColor: UIColor = .white
    
    // Convenience property for backward compatibility
    var textColor: UIColor {
        get {
            switch fillType {
            case .solid(let color):
                lastSolidColor = color
                return color
            default:
                return lastSolidColor
            }
        }
        set {
            lastSolidColor = newValue
            fillType = .solid(newValue)
        }
    }
    
    var backgroundColor: UIColor = .clear {
        didSet {
            updateTexture()
        }
    }
    
    @Published var hasOutline: Bool = false {
        didSet {
            updateTexture()
        }
    }
    
    @Published var outlineColor: UIColor = .black {
        didSet {
            updateTexture()
        }
    }
    
    @Published var outlineWidth: CGFloat = 2.0 {
        didSet {
            updateTexture()
        }
    }
    
    @Published var alignment: NSTextAlignment = .center {
        didSet { updateTexture() }
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
            texture = nil
            bounds = .zero
            return
        }
        
        // Create texture using the proper renderer
        texture = textRenderer.createTextTexture(
            text: text,
            font: font,
            fillType: fillType,
            maxWidth: 800, // Max width for text wrapping
            alignment: alignment,
            hasOutline: hasOutline,
            outlineColor: outlineColor,
            outlineWidth: outlineWidth
        )
        
        if let texture = texture {
            // Update bounds based on texture size (accounting for 2x scale)
            bounds = CGRect(
                origin: .zero,
                size: CGSize(width: texture.width / 2, height: texture.height / 2)
            )
        } else {
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
