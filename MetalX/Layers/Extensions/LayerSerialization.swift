import UIKit
import CoreGraphics
import MetalKit

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
            bounds: bounds,
            dropShadow: dropShadow.isEnabled ? DropShadowData(
                isEnabled: dropShadow.isEnabled,
                offset: dropShadow.offset,
                blur: dropShadow.blur,
                color: CodableColor(cgColor: dropShadow.color),
                opacity: dropShadow.opacity
            ) : nil
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
        default: 
            print("Warning: Unknown layer type \(type(of: self)), defaulting to shape")
            return .shape // Default to shape for unknown types
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
        var gradientData: GradientSerializationData? = nil
        var imageData: Data? = nil
        
        if let fillType = fillType {
            switch fillType {
            case .solid(let color):
                fillColor = CodableColor(cgColor: color)
            case .gradient(let gradient):
                gradientData = GradientSerializationData(
                    type: gradientTypeString(gradient.type),
                    colorStops: gradient.colorStops.map { ColorStopData(color: CodableColor(cgColor: $0.color), location: $0.location) },
                    startPoint: gradient.startPoint,
                    endPoint: gradient.endPoint
                )
            case .pattern(let texture):
                // Convert texture to image data for serialization
                imageData = textureToImageData(texture)
            }
        }
        
        let strokeCol = strokeColor.map { CodableColor(cgColor: $0) }
        
        return ShapeLayerData(
            shapeType: shapeType,
            fillColor: fillColor,
            gradientData: gradientData,
            imageData: imageData,
            strokeColor: strokeCol,
            strokeWidth: strokeWidth,
            size: CGSize(width: bounds.width, height: bounds.height),
            sides: sides,
            radius: polygonRadius
        )
    }
    
    private func gradientTypeString(_ type: Gradient.GradientType) -> String {
        switch type {
        case .linear: return "linear"
        case .radial: return "radial"
        case .angular: return "angular"
        }
    }
    
    private func textureToImageData(_ texture: MTLTexture) -> Data? {
        // Extract pixel data from texture and convert to PNG
        let width = texture.width
        let height = texture.height
        let bytesPerRow = width * 4
        let dataSize = height * bytesPerRow
        
        var pixelData = [UInt8](repeating: 0, count: dataSize)
        
        texture.getBytes(
            &pixelData,
            bytesPerRow: bytesPerRow,
            from: MTLRegion(
                origin: MTLOrigin(x: 0, y: 0, z: 0),
                size: MTLSize(width: width, height: height, depth: 1)
            ),
            mipmapLevel: 0
        )
        
        // Create CGImage from pixel data
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ),
        let cgImage = context.makeImage() else {
            return nil
        }
        
        // Convert to UIImage and then to PNG data
        let image = UIImage(cgImage: cgImage)
        return image.pngData()
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
            // Use saved radius if available, otherwise calculate from size
            let radius = shapeData.radius ?? min(shapeData.size.width, shapeData.size.height) / 2
            layer = VectorShapeLayer.polygon(sides: sides, radius: radius)
        default:
            layer = VectorShapeLayer.rectangle(size: shapeData.size)
        }
        
        // Load fill type (gradient > image > solid color precedence)
        if let gradientData = shapeData.gradientData {
            layer.fillType = .gradient(loadGradient(from: gradientData))
        } else if let imageData = shapeData.imageData {
            if let texture = loadImageTexture(from: imageData) {
                layer.fillType = .pattern(texture)
            }
        } else if let fillColor = shapeData.fillColor {
            layer.fillType = .solid(fillColor.cgColor)
        }
        
        if let strokeColor = shapeData.strokeColor {
            layer.strokeColor = strokeColor.cgColor
        }
        
        layer.strokeWidth = shapeData.strokeWidth
        
        applyCommonProperties(to: layer, from: data)
        
        // Force re-render at correct resolution after loading
        layer.invalidateRenderCache()
        
        return layer
    }
    
    private static func loadGradient(from data: GradientSerializationData) -> Gradient {
        let gradientType: Gradient.GradientType
        switch data.type {
        case "linear":
            gradientType = .linear
        case "radial":
            gradientType = .radial
        case "angular":
            gradientType = .angular
        default:
            gradientType = .linear // fallback
        }
        
        let colorStops = data.colorStops.map { stopData in
            Gradient.ColorStop(color: stopData.color.cgColor, location: stopData.location)
        }
        
        return Gradient(
            type: gradientType,
            colorStops: colorStops,
            startPoint: data.startPoint,
            endPoint: data.endPoint
        )
    }
    
    private static func loadImageTexture(from imageData: Data) -> MTLTexture? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let image = UIImage(data: imageData),
              let cgImage = image.cgImage else {
            return nil
        }
        
        let loader = MTKTextureLoader(device: device)
        do {
            let texture = try loader.newTexture(cgImage: cgImage, options: [
                .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
                .SRGB: false
            ])
            return texture
        } catch {
            print("Failed to load texture from image data: \(error)")
            return nil
        }
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
        
        // Apply drop shadow data if present
        if let shadowData = data.dropShadow {
            layer.dropShadow = DropShadow(
                isEnabled: shadowData.isEnabled,
                offset: shadowData.offset,
                blur: shadowData.blur,
                color: shadowData.color.cgColor,
                opacity: shadowData.opacity
            )
        }
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