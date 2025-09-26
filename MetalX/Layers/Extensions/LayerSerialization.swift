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
                rotation: transform.rotation,
                flipHorizontal: transform.flipHorizontal,
                flipVertical: transform.flipVertical
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
                opacity: dropShadow.opacity,
                scale: dropShadow.scale
            ) : nil,
            effects: serializeEffects()
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
    
    private func serializeEffects() -> [EffectData] {
        return effectStack.effects.map { effect in
            var parameters: [String: Float] = [:]
            
            if let brightnessEffect = effect as? BrightnessContrastEffect {
                parameters["brightness"] = brightnessEffect.brightness
                parameters["contrast"] = brightnessEffect.contrast
            } else if let hueEffect = effect as? HueSaturationEffect {
                parameters["hueShift"] = hueEffect.hueShift
                parameters["saturation"] = hueEffect.saturation
                parameters["lightness"] = hueEffect.lightness
            } else if let pixellateEffect = effect as? PixellateEffect {
                parameters["pixelSize"] = pixellateEffect.pixelSize
            } else if let noiseEffect = effect as? NoiseEffect {
                parameters["amount"] = noiseEffect.amount
                parameters["seed"] = noiseEffect.seed
            } else if let thresholdEffect = effect as? ThresholdEffect {
                parameters["threshold"] = thresholdEffect.threshold
                parameters["smoothness"] = thresholdEffect.smoothness
            } else if let chromaticEffect = effect as? ChromaticAberrationEffect {
                parameters["redOffset"] = chromaticEffect.redOffset
                parameters["blueOffset"] = chromaticEffect.blueOffset
            } else if let vhsEffect = effect as? VHSEffect {
                parameters["lineIntensity"] = vhsEffect.lineIntensity
                parameters["noiseIntensity"] = vhsEffect.noiseIntensity
                parameters["colorBleed"] = vhsEffect.colorBleed
                parameters["distortion"] = vhsEffect.distortion
            } else if let posterizeEffect = effect as? PosterizeEffect {
                parameters["levels"] = posterizeEffect.levels
            } else if let vignetteEffect = effect as? VignetteEffect {
                parameters["size"] = vignetteEffect.size
                parameters["smoothness"] = vignetteEffect.smoothness
                parameters["darkness"] = vignetteEffect.darkness
            } else if let cmyk = effect as? CMYKHalftoneEffect {
                parameters["dotSize"] = cmyk.dotSize
                parameters["angle"] = cmyk.angle
                parameters["sharpness"] = cmyk.sharpness
                parameters["grayComponentReplacement"] = cmyk.grayComponentReplacement
                parameters["underColorRemoval"] = cmyk.underColorRemoval
            }
            
            return EffectData(
                id: effect.id.uuidString,
                name: effect.name,
                type: String(describing: type(of: effect)),
                isEnabled: effect.isEnabled,
                intensity: effect.intensity,
                parameters: parameters
            )
        }
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
        // Serialize fill type
        var fillTypeString: String?
        var gradientData: GradientSerializationData?
        var imageData: Data?
        
        switch fillType {
        case .solid:
            fillTypeString = "solid"
        case .gradient(let gradient):
            fillTypeString = "gradient"
            gradientData = GradientSerializationData(
                type: gradientTypeString(gradient.type),
                colorStops: gradient.colorStops.map { stop in
                    ColorStopData(
                        color: CodableColor(cgColor: stop.color),
                        location: stop.location
                    )
                },
                startPoint: gradient.startPoint,
                endPoint: gradient.endPoint
            )
        case .image(let image):
            fillTypeString = "image"
            imageData = image.pngData()
        case .none:
            fillTypeString = "none"
        }
        
        return TextLayerData(
            text: text,
            fontSize: font.pointSize,
            fontName: font.fontName,
            textColor: CodableColor(cgColor: textColor.cgColor),
            alignment: alignmentString(self.alignment),
            fillType: fillTypeString,
            gradientData: gradientData,
            imageData: imageData,
            hasOutline: hasOutline,
            outlineColor: hasOutline ? CodableColor(cgColor: outlineColor.cgColor) : nil,
            outlineWidth: hasOutline ? outlineWidth : nil
        )
    }
    
    private func gradientTypeString(_ type: MetalX.Gradient.GradientType) -> String {
        switch type {
        case .linear: return "linear"
        case .radial: return "radial"
        case .angular: return "angular"
        }
    }
    
    private func alignmentString(_ alignment: NSTextAlignment) -> String {
        switch alignment {
        case .left: return "left"
        case .right: return "right"
        case .center: return "center"
        default: return "left"
        }
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
        // Alignment
        let align = textData.alignment.lowercased()
        switch align {
        case "left": layer.alignment = .left
        case "right": layer.alignment = .right
        case "center": layer.alignment = .center
        default: break
        }
        
        // Load fill type
        if let fillTypeString = textData.fillType {
            switch fillTypeString {
            case "solid":
                layer.fillType = .solid(UIColor(cgColor: textData.textColor.cgColor))
            case "gradient":
                if let gradientData = textData.gradientData {
                    layer.fillType = .gradient(loadGradient(from: gradientData))
                }
            case "image":
                if let imageData = textData.imageData,
                   let image = UIImage(data: imageData) {
                    layer.fillType = .image(image)
                }
            case "none":
                layer.fillType = .none
            default:
                layer.fillType = .solid(UIColor(cgColor: textData.textColor.cgColor))
            }
        } else {
            // Legacy support - use textColor as solid fill
            layer.fillType = .solid(UIColor(cgColor: textData.textColor.cgColor))
        }
        
        // Load outline properties
        if let hasOutline = textData.hasOutline {
            layer.hasOutline = hasOutline
            if hasOutline,
               let outlineColor = textData.outlineColor {
                layer.outlineColor = UIColor(cgColor: outlineColor.cgColor)
            }
            if hasOutline,
               let outlineWidth = textData.outlineWidth {
                layer.outlineWidth = outlineWidth
            }
        }
        
        applyCommonProperties(to: layer, from: data)
        
        // Delay texture update to ensure it happens after layer is added to canvas
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5    ) {
            layer.forceUpdateTexture()
        }
        
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
        layer.transform.flipHorizontal = data.transform.flipHorizontal
        layer.transform.flipVertical = data.transform.flipVertical
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
                opacity: shadowData.opacity,
                scale: shadowData.scale
            )
        }
        
        // Load effects
        if let effectsData = data.effects {
            for effectData in effectsData {
                if let effect = createEffect(from: effectData) {
                    layer.effectStack.addEffect(effect)
                }
            }
        }
    }
    
    static func createEffect(from data: EffectData) -> Effect? {
        let effect: Effect?
        
        if data.type.contains("BrightnessContrastEffect") {
            let brightnessEffect = BrightnessContrastEffect()
            brightnessEffect.brightness = data.parameters["brightness"] ?? 0.0
            brightnessEffect.contrast = data.parameters["contrast"] ?? 1.0
            effect = brightnessEffect
        } else if data.type.contains("HueSaturationEffect") {
            let hueEffect = HueSaturationEffect()
            hueEffect.hueShift = data.parameters["hueShift"] ?? 0.0
            hueEffect.saturation = data.parameters["saturation"] ?? 1.0
            hueEffect.lightness = data.parameters["lightness"] ?? 0.0
            effect = hueEffect
        } else if data.type.contains("PixellateEffect") {
            let pixellateEffect = PixellateEffect()
            pixellateEffect.pixelSize = data.parameters["pixelSize"] ?? 8.0
            effect = pixellateEffect
        } else if data.type.contains("NoiseEffect") {
            let noiseEffect = NoiseEffect()
            noiseEffect.amount = data.parameters["amount"] ?? 0.1
            noiseEffect.seed = data.parameters["seed"] ?? 0.5
            effect = noiseEffect
        } else if data.type.contains("ThresholdEffect") {
            let thresholdEffect = ThresholdEffect()
            thresholdEffect.threshold = data.parameters["threshold"] ?? 0.5
            thresholdEffect.smoothness = data.parameters["smoothness"] ?? 0.01
            effect = thresholdEffect
        } else if data.type.contains("ChromaticAberrationEffect") {
            let chromaticEffect = ChromaticAberrationEffect()
            chromaticEffect.redOffset = data.parameters["redOffset"] ?? 2.0
            chromaticEffect.blueOffset = data.parameters["blueOffset"] ?? -2.0
            effect = chromaticEffect
        } else if data.type.contains("VHSEffect") {
            let vhsEffect = VHSEffect()
            vhsEffect.lineIntensity = data.parameters["lineIntensity"] ?? 0.5
            vhsEffect.noiseIntensity = data.parameters["noiseIntensity"] ?? 0.3
            vhsEffect.colorBleed = data.parameters["colorBleed"] ?? 0.2
            vhsEffect.distortion = data.parameters["distortion"] ?? 0.1
            effect = vhsEffect
        } else if data.type.contains("PosterizeEffect") {
            let posterizeEffect = PosterizeEffect()
            posterizeEffect.levels = data.parameters["levels"] ?? 8.0
            effect = posterizeEffect
        } else if data.type.contains("VignetteEffect") {
            let vignetteEffect = VignetteEffect()
            vignetteEffect.size = data.parameters["size"] ?? 0.5
            vignetteEffect.smoothness = data.parameters["smoothness"] ?? 0.3
            vignetteEffect.darkness = data.parameters["darkness"] ?? 0.8
            effect = vignetteEffect
        } else if data.type.contains("CMYKHalftoneEffect") {
            let cmyk = CMYKHalftoneEffect()
            cmyk.dotSize = data.parameters["dotSize"] ?? 6.0
            cmyk.angle = data.parameters["angle"] ?? 0.0
            cmyk.sharpness = data.parameters["sharpness"] ?? 0.7
            cmyk.grayComponentReplacement = data.parameters["grayComponentReplacement"] ?? 1.0
            cmyk.underColorRemoval = data.parameters["underColorRemoval"] ?? 0.5
            effect = cmyk
        } else if data.type.contains("HalftoneEffect") {
            // Legacy: map mono Halftone to CMYKHalftone with similar parameters
            let cmyk = CMYKHalftoneEffect()
            cmyk.dotSize = data.parameters["dotSize"] ?? 8.0
            cmyk.angle = data.parameters["angle"] ?? 45.0
            cmyk.sharpness = data.parameters["sharpness"] ?? 0.8
            effect = cmyk
        } else {
            return nil
        }
        
        if let effect = effect {
            effect.isEnabled = data.isEnabled
            effect.intensity = data.intensity
        }
        
        return effect
    }
}

// MARK: - Canvas Serialization

extension Canvas {
    func toProject(name: String) -> MetalXProject {
        var project = MetalXProject(name: name, canvasSize: size)
        // Persist solid background color when present; gradients/images are not yet serialized
        if let bg = backgroundLayer {
            switch bg.fillType {
            case .solid(let cg):
                project.backgroundColor = CodableColor(cgColor: cg)
            default:
                break
            }
        }
        // Filter out shadow layers when saving - they'll be recreated on load
        project.layers = layers.compactMap { layer in
            // Skip shadow layers
            if layer is ShadowLayer {
                return nil
            }
            return layer.toLayerData()
        }
        
        // Save canvas effects
        project.canvasEffects = serializeCanvasEffects()
        
        return project
    }
    
    private func serializeCanvasEffects() -> [EffectData] {
        return effectStack.effects.map { effect in
            var parameters: [String: Float] = [:]
            
            if let brightnessEffect = effect as? BrightnessContrastEffect {
                parameters["brightness"] = brightnessEffect.brightness
                parameters["contrast"] = brightnessEffect.contrast
            } else if let hueEffect = effect as? HueSaturationEffect {
                parameters["hueShift"] = hueEffect.hueShift
                parameters["saturation"] = hueEffect.saturation
                parameters["lightness"] = hueEffect.lightness
            } else if let pixellateEffect = effect as? PixellateEffect {
                parameters["pixelSize"] = pixellateEffect.pixelSize
            } else if let noiseEffect = effect as? NoiseEffect {
                parameters["amount"] = noiseEffect.amount
                parameters["seed"] = noiseEffect.seed
            } else if let thresholdEffect = effect as? ThresholdEffect {
                parameters["threshold"] = thresholdEffect.threshold
                parameters["smoothness"] = thresholdEffect.smoothness
            } else if let chromaticEffect = effect as? ChromaticAberrationEffect {
                parameters["redOffset"] = chromaticEffect.redOffset
                parameters["blueOffset"] = chromaticEffect.blueOffset
            } else if let vhsEffect = effect as? VHSEffect {
                parameters["lineIntensity"] = vhsEffect.lineIntensity
                parameters["noiseIntensity"] = vhsEffect.noiseIntensity
                parameters["colorBleed"] = vhsEffect.colorBleed
                parameters["distortion"] = vhsEffect.distortion
            } else if let posterizeEffect = effect as? PosterizeEffect {
                parameters["levels"] = posterizeEffect.levels
            } else if let vignetteEffect = effect as? VignetteEffect {
                parameters["size"] = vignetteEffect.size
                parameters["smoothness"] = vignetteEffect.smoothness
                parameters["darkness"] = vignetteEffect.darkness
            } else if let cmyk = effect as? CMYKHalftoneEffect {
                parameters["dotSize"] = cmyk.dotSize
                parameters["angle"] = cmyk.angle
                parameters["sharpness"] = cmyk.sharpness
                parameters["grayComponentReplacement"] = cmyk.grayComponentReplacement
                parameters["underColorRemoval"] = cmyk.underColorRemoval
            }
            
            return EffectData(
                id: effect.id.uuidString,
                name: effect.name,
                type: String(describing: type(of: effect)),
                isEnabled: effect.isEnabled,
                intensity: effect.intensity,
                parameters: parameters
            )
        }
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
        
        // Force display update after loading all layers
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.setNeedsDisplay()
        }
        
        // Load canvas effects
        if let canvasEffects = project.canvasEffects {
            for effectData in canvasEffects {
                if let effect = LayerFactory.createEffect(from: effectData) {
                    effectStack.addEffect(effect)
                }
            }
        }
        
        setNeedsDisplay()
    }
}
