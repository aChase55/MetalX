import UIKit
import CoreGraphics

// MARK: - Layer to LayerData Conversion

extension Layer {
    func toLayerData() -> LayerData {
        var data = LayerData(
            id: id,
            name: name,
            type: layerType,
            transform: LayerTransformData(
                position: transform.position,
                scale: transform.scale,
                rotation: transform.rotation
            ),
            opacity: opacity,
            isVisible: isVisible,
            isLocked: isLocked,
            blendMode: blendMode.rawValue,
            bounds: bounds
        )
        
        // Add type-specific data
        if let imageLayer = self as? ImageLayer {
            data.imageData = imageLayer.toImageData()
        } else if let textLayer = self as? TextLayer {
            data.textData = textLayer.toTextData()
        } else if let shapeLayer = self as? VectorShapeLayer {
            data.shapeData = shapeLayer.toShapeData()
        }
        
        return data
    }
    
    private var layerType: LayerData.LayerType {
        switch self {
        case is ImageLayer: return .image
        case is TextLayer: return .text
        case is VectorShapeLayer: return .shape
        default: fatalError("Unknown layer type")
        }
    }
}

// MARK: - Image Layer Serialization

extension ImageLayer {
    func toImageData() -> ImageLayerData? {
        guard let image = image,
              let pngData = image.pngData() else { return nil }
        
        return ImageLayerData(
            imageData: pngData,
            originalSize: image.size
        )
    }
}

// MARK: - Text Layer Serialization

extension TextLayer {
    func toTextData() -> TextLayerData {
        return TextLayerData(
            text: text,
            fontSize: font.pointSize,
            fontName: font.fontName,
            textColor: CodableColor(cgColor: textColor.cgColor),
            alignment: "center" // TODO: Add alignment property to TextLayer
        )
    }
}

// MARK: - Shape Layer Serialization

extension VectorShapeLayer {
    func toShapeData() -> ShapeLayerData {
        // Determine shape type from name
        let shapeType: String
        var sides: Int? = nil
        
        if name.contains("Rectangle") {
            shapeType = "rectangle"
        } else if name.contains("Circle") || name.contains("Ellipse") {
            shapeType = "ellipse"
        } else if name.contains("Triangle") {
            shapeType = "polygon"
            sides = 3
        } else if name.contains("Hexagon") {
            shapeType = "polygon"
            sides = 6
        } else if name.contains("Polygon") {
            shapeType = "polygon"
            // Extract sides from name if possible
            if let match = name.range(of: "\\d+", options: .regularExpression) {
                sides = Int(name[match])
            }
        } else {
            shapeType = "rectangle" // Default
        }
        
        var fillColor: CodableColor? = nil
        if case .solid(let color) = fillType {
            fillColor = CodableColor(cgColor: color)
        }
        
        let strokeCol = strokeColor.map { CodableColor(cgColor: $0) }
        
        return ShapeLayerData(
            shapeType: shapeType,
            fillColor: fillColor,
            strokeColor: strokeCol,
            strokeWidth: strokeWidth,
            size: CGSize(width: bounds.width, height: bounds.height),
            sides: sides
        )
    }
}

// MARK: - LayerData to Layer Conversion

class LayerFactory {
    static func createLayer(from data: LayerData) -> (any Layer)? {
        switch data.type {
        case .image:
            return createImageLayer(from: data)
        case .text:
            return createTextLayer(from: data)
        case .shape:
            return createShapeLayer(from: data)
        }
    }
    
    private static func createImageLayer(from data: LayerData) -> ImageLayer? {
        guard let imageData = data.imageData,
              let image = UIImage(data: imageData.imageData) else { return nil }
        
        let layer = ImageLayer(image: image)
        applyCommonProperties(to: layer, from: data)
        return layer
    }
    
    private static func createTextLayer(from data: LayerData) -> TextLayer? {
        guard let textData = data.textData else { return nil }
        
        let layer = TextLayer(text: textData.text)
        layer.font = UIFont(name: textData.fontName, size: textData.fontSize) ?? UIFont.systemFont(ofSize: textData.fontSize)
        layer.textColor = UIColor(cgColor: textData.textColor.cgColor)
        applyCommonProperties(to: layer, from: data)
        return layer
    }
    
    private static func createShapeLayer(from data: LayerData) -> VectorShapeLayer? {
        guard let shapeData = data.shapeData else { return nil }
        
        let layer: VectorShapeLayer
        
        switch shapeData.shapeType {
        case "rectangle":
            layer = VectorShapeLayer.rectangle(size: shapeData.size)
        case "ellipse":
            layer = VectorShapeLayer.ellipse(size: shapeData.size)
        case "polygon":
            let sides = shapeData.sides ?? 6
            let radius = min(shapeData.size.width, shapeData.size.height) / 2
            layer = VectorShapeLayer.polygon(sides: sides, radius: radius)
        default:
            layer = VectorShapeLayer.rectangle(size: shapeData.size)
        }
        
        if let fillColor = shapeData.fillColor {
            layer.fillType = .solid(fillColor.cgColor)
        }
        
        if let strokeColor = shapeData.strokeColor {
            layer.strokeColor = strokeColor.cgColor
        }
        
        layer.strokeWidth = shapeData.strokeWidth
        
        applyCommonProperties(to: layer, from: data)
        return layer
    }
    
    private static func applyCommonProperties(to layer: any Layer, from data: LayerData) {
        layer.id = data.id
        layer.name = data.name
        layer.transform.position = data.transform.position
        layer.transform.scale = data.transform.scale
        layer.transform.rotation = data.transform.rotation
        layer.opacity = data.opacity
        layer.isVisible = data.isVisible
        layer.isLocked = data.isLocked
        layer.blendMode = BlendMode(rawValue: data.blendMode) ?? .normal
    }
}

// MARK: - Canvas Serialization

extension Canvas {
    func toProject(name: String) -> MetalXProject {
        var project = MetalXProject(name: name, canvasSize: size)
        project.backgroundColor = CodableColor(red: 0, green: 0, blue: 0, alpha: 1)
        project.layers = layers.map { $0.toLayerData() }
        return project
    }
    
    func loadFromProject(_ project: MetalXProject) {
        // Clear existing layers
        clear()
        
        // Validate and clamp canvas size to Metal limits
        let maxDimension: CGFloat = 4096
        var validatedSize = project.canvasSize
        if validatedSize.width > maxDimension || validatedSize.height > maxDimension {
            let scale = min(maxDimension / validatedSize.width, maxDimension / validatedSize.height)
            validatedSize = CGSize(
                width: validatedSize.width * scale,
                height: validatedSize.height * scale
            )
            print("Canvas size clamped from \(project.canvasSize) to \(validatedSize) due to Metal texture limits")
        }
        
        // Set canvas properties
        size = validatedSize
        backgroundColor = project.backgroundColor.cgColor
        
        // Load layers
        for layerData in project.layers {
            if let layer = LayerFactory.createLayer(from: layerData) {
                addLayer(layer)
            }
        }
        
        setNeedsDisplay()
    }
}