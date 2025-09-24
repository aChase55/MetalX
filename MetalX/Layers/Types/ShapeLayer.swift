import UIKit
import Metal
import CoreGraphics
import simd

// Shape layer implementation for vector graphics
class VectorShapeLayer: BaseLayer, ShapeLayer {
    var path: CGPath = CGMutablePath() {
        didSet {
            updateGeometry()
        }
    }
    
    private var lastRenderScale: CGFloat = 1.0
    
    // Store original polygon radius for proper serialization
    var polygonRadius: CGFloat?
    
    var fillType: FillType? = .solid(UIColor.white.cgColor) {
        didSet {
            updateAppearance()
        }
    }
    
    var strokeColor: CGColor? = UIColor.black.cgColor {
        didSet {
            updateAppearance()
        }
    }
    
    var strokeWidth: Float = 0.0 {
        didSet {
            updateAppearance()
        }
    }
    
    var lineCap: CGLineCap = .round {
        didSet {
            updateAppearance()
        }
    }
    
    var lineJoin: CGLineJoin = .round {
        didSet {
            updateAppearance()
        }
    }
    
    // Cached rendering data
    private var vertices: [Float] = []
    private var indices: [UInt16] = []
    var vertexBuffer: MTLBuffer?
    var indexBuffer: MTLBuffer?
    var indexCount: Int { indices.count }
    private var texture: MTLTexture?
    private var device: MTLDevice?
    private var metalDevice: MetalDevice?
    private var shapeRenderer: ShapeRenderer?
    
    override init() {
        super.init()
        self.device = MTLCreateSystemDefaultDevice()
        self.name = "Shape Layer"
        
        if let device = device {
            do {
                self.metalDevice = try MetalDevice(preferredDevice: device)
                self.shapeRenderer = try ShapeRenderer(device: device)
            } catch {
                // Failed to create shape renderer or metal device
            }
        }
    }
    
    // MARK: - Geometry Updates
    
    private func updateGeometry() {
        // Update bounds from path
        let pathBounds = path.boundingBoxOfPath
        bounds = pathBounds
        // Debug: ShapeLayer updateGeometry
        
        // TODO: Tessellate path into triangles
        // This would convert the CGPath into vertex data
        tessellatePathToMesh()
        
        // Vertices tessellated: \(vertices.count/2) vertices
        
        // Recalculate bounds from actual vertices if we have them
        if vertices.count >= 2 {
            var minX = Float.infinity
            var minY = Float.infinity
            var maxX = -Float.infinity
            var maxY = -Float.infinity
            
            // Skip center vertex at index 0,1 for triangle fan shapes
            // (ellipses and polygons have center at 0,0)
            let startIdx = (vertices.count > 2 && vertices[0] == 0 && vertices[1] == 0) ? 2 : 0
            
            for i in stride(from: startIdx, to: vertices.count, by: 2) {
                let x = vertices[i]
                let y = vertices[i + 1]
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
            
            if minX != Float.infinity {
                let newBounds = CGRect(x: CGFloat(minX), y: CGFloat(minY),
                              width: CGFloat(maxX - minX), height: CGFloat(maxY - minY))
                bounds = newBounds
                // Bounds updated from vertices
            }
        }
        
        // Create Metal buffers
        createMetalBuffers()
    }
    
    private func updateAppearance() {
        // Clear texture to force re-render with new appearance
        texture = nil
    }
    
    func clearTexture() {
        texture = nil
    }
    
    func invalidateRenderCache() {
        texture = nil
        lastRenderScale = transform.scale  // Update to current scale
    }
    
    override func getBounds(includeEffects: Bool) -> CGRect {
        // Start with base bounds
        var layerBounds = bounds
        
        // Add stroke width to bounds only when including effects
        if includeEffects && strokeWidth > 0 {
            let strokePadding = CGFloat(strokeWidth)
            layerBounds = layerBounds.insetBy(dx: -strokePadding, dy: -strokePadding)
        }
        
        // Apply transform to bounds
        let scaledWidth = layerBounds.width * transform.scale
        let scaledHeight = layerBounds.height * transform.scale
        
        // Position is the center of the layer
        let transformedBounds = CGRect(
            x: transform.position.x - scaledWidth / 2,
            y: transform.position.y - scaledHeight / 2,
            width: scaledWidth,
            height: scaledHeight
        )
        
        return transformedBounds
    }
    
    private func tessellatePathToMesh() {
        vertices = []
        indices = []
        
        // Get path elements to determine shape type
        var isRectangle = false
        var isEllipse = false
        var points: [CGPoint] = []
        var elementCount = 0
        
        path.applyWithBlock { element in
            elementCount += 1
            switch element.pointee.type {
            case .moveToPoint:
                points.append(element.pointee.points[0])
            case .addLineToPoint:
                points.append(element.pointee.points[0])
            case .addQuadCurveToPoint, .addCurveToPoint:
                // This is likely an ellipse or complex curve
                isEllipse = true
            case .closeSubpath:
                break
            @unknown default:
                break
            }
        }
        
        // Path analysis complete
        
        // Check if it's a rectangle (4 points forming right angles)
        if points.count == 4 && !isEllipse {
            isRectangle = true
        }
        
        // If we have a bounding box but no points, it's likely an ellipse
        if points.isEmpty && bounds.width > 0 && bounds.height > 0 {
            // Detected ellipse from bounds
            tessellateEllipse()
        } else if isRectangle || points.count == 4 {
            // Simple rectangle or quad
            for point in points {
                vertices.append(Float(point.x))
                vertices.append(Float(point.y))
            }
            indices = [0, 1, 2, 2, 3, 0]
        } else if isEllipse {
            // Tessellate ellipse/circle
            tessellateEllipse()
        } else if points.count >= 3 {
            // Polygon - use fan triangulation from center
            tessellatePolygon(points: points)
        } else {
            // WARNING: No tessellation performed
        }
    }
    
    private func tessellateEllipse() {
        let rect = bounds
        let radiusX = Float(rect.width / 2)
        let radiusY = Float(rect.height / 2)
        
        // Clear any existing vertices
        vertices = []
        indices = []
        
        // Add center vertex at origin
        vertices.append(0)
        vertices.append(0)
        
        // Generate vertices around the ellipse centered at origin
        let segments = 64 // Increase segments for smoother circle
        for i in 0...segments {
            let angle = Float(i) * Float.pi * 2.0 / Float(segments)
            let x = cos(angle) * radiusX
            let y = sin(angle) * radiusY
            vertices.append(x)
            vertices.append(y)
        }
        
        // Generate triangle fan indices
        for i in 0..<segments {
            indices.append(0) // Center
            indices.append(UInt16(i + 1))
            indices.append(UInt16(i + 2))
        }
    }
    
    private func tessellatePolygon(points: [CGPoint]) {
        // Clear any existing vertices
        vertices = []
        indices = []
        
        // Add center vertex at origin
        vertices.append(0)
        vertices.append(0)
        
        // Add polygon vertices (already centered at origin from polygon creation)
        for point in points {
            vertices.append(Float(point.x))
            vertices.append(Float(point.y))
        }
        
        // Generate triangle fan indices
        for i in 0..<points.count {
            indices.append(0) // Center
            indices.append(UInt16(i + 1))
            indices.append(UInt16((i + 1) % points.count + 1))
        }
    }
    
    private func createMetalBuffers() {
        guard let device = device else { return }
        
        if !vertices.isEmpty {
            vertexBuffer = device.makeBuffer(
                bytes: vertices,
                length: vertices.count * MemoryLayout<Float>.size,
                options: []
            )
            // Created vertex buffer
        }
        
        if !indices.isEmpty {
            indexBuffer = device.makeBuffer(
                bytes: indices,
                length: indices.count * MemoryLayout<UInt16>.size,
                options: []
            )
            // Created index buffer
        }
    }
    
    // MARK: - Rendering
    
    override func render(context: RenderContext) -> MTLTexture? {
        guard let device = device,
              let shapeRenderer = shapeRenderer,
              bounds.width > 0,
              bounds.height > 0 else {
            print("Shape render failed - bounds: \(bounds)")
            return nil
        }
        
        // ShapeLayer render: \(name)
        
        // For vector quality, render at a resolution based on the current scale
        // This ensures shapes stay sharp when scaled up
        let baseScale: CGFloat = 2.0 // Base quality multiplier
        let currentScale = transform.scale
        
        // Ensure minimum quality for small shapes
        let minDimension = min(bounds.width, bounds.height)
        let qualityBoost = minDimension < 150 ? 1.5 : 1.0  // Boost quality for small shapes
        
        let renderScale = baseScale * qualityBoost * min(currentScale, 3.0) // Cap at 3x to prevent excessive memory use
        
        // Render scale: \(renderScale)
        
        // Only recreate texture if scale changed significantly
        let scaleChanged = abs(currentScale - lastRenderScale) > 0.05
        if scaleChanged {
            texture = nil
            lastRenderScale = currentScale
        }
        
        // Make sure we have positive dimensions and respect Metal limits
        // Add stroke width to bounds to prevent clipping
        let strokePadding = strokeWidth * 2
        let paddedBounds = bounds.insetBy(dx: CGFloat(-strokePadding), dy: CGFloat(-strokePadding))
        
        let maxTextureSize = 8192
        let requestedWidth = Int(abs(paddedBounds.width) * renderScale)
        let requestedHeight = Int(abs(paddedBounds.height) * renderScale)
        
        // Ensure minimum texture size for quality
        let minTextureSize = 256
        let textureWidth = max(minTextureSize, min(requestedWidth, maxTextureSize))
        let textureHeight = max(minTextureSize, min(requestedHeight, maxTextureSize))
        
        // Texture size: \(textureWidth) x \(textureHeight)
        
        if texture == nil || 
           texture?.width != textureWidth ||
           texture?.height != textureHeight {
            // Creating new texture
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: textureWidth,
                height: textureHeight,
                mipmapped: true
            )
            descriptor.usage = [MTLTextureUsage.renderTarget, MTLTextureUsage.shaderRead]
            texture = device.makeTexture(descriptor: descriptor)
        }
        
        guard let texture = texture,
              let commandQueue = device.makeCommandQueue(),
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return nil
        }
        
        // Calculate transform matrix - use original bounds for the shape
        let transform = createTransformMatrix(renderScale: Float(renderScale))
        
        // Render shape
        shapeRenderer.render(
            shape: self,
            to: texture,
            commandBuffer: commandBuffer,
            transform: transform
        )
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Generate mipmaps for better quality when scaled down
        // Only generate mipmaps if texture has multiple mip levels
        if texture.mipmapLevelCount > 1,
           let blitCommandBuffer = commandQueue.makeCommandBuffer(),
           let blitEncoder = blitCommandBuffer.makeBlitCommandEncoder() {
            blitEncoder.generateMipmaps(for: texture)
            blitEncoder.endEncoding()
            blitCommandBuffer.commit()
            blitCommandBuffer.waitUntilCompleted()
        }
        
        return texture
    }
    
    private func createTransformMatrix(renderScale: Float) -> matrix_float4x4 {
        // Convert from shape space to normalized device coordinates
        // The shape vertices are in the coordinate system defined by bounds
        // We need to map the bounds to fill the NDC space (-1 to 1)
        
        // Calculate the padded bounds (includes stroke)
        let strokePadding = strokeWidth * 2
        let paddedBounds = bounds.insetBy(dx: CGFloat(-strokePadding), dy: CGFloat(-strokePadding))
        
        // Calculate scale to fit padded bounds in NDC space
        let scaleX = 2.0 / Float(paddedBounds.width)   // Map width to 2 units (-1 to 1)
        let scaleY = -2.0 / Float(paddedBounds.height)  // Map height to 2 units, flip Y
        
        // Calculate translation to center padded bounds in NDC
        let centerX = Float(paddedBounds.midX)
        let centerY = Float(paddedBounds.midY)
        
        var transform = matrix_identity_float4x4
        // Scale
        transform.columns.0.x = scaleX
        transform.columns.1.y = scaleY
        // Translate - map center of padded bounds to center of NDC (0,0)
        transform.columns.3.x = -centerX * scaleX
        transform.columns.3.y = -centerY * scaleY
        
        return transform
    }
    
    // MARK: - Convenience Initializers
    
    static func rectangle(size: CGSize) -> VectorShapeLayer {
        let layer = VectorShapeLayer()
        let path = CGMutablePath()
        // Center the rectangle at origin
        let rect = CGRect(x: -size.width/2, y: -size.height/2, width: size.width, height: size.height)
        path.addRect(rect)
        layer.path = path
        layer.name = "Rectangle"
        return layer
    }
    
    static func ellipse(size: CGSize) -> VectorShapeLayer {
        let layer = VectorShapeLayer()
        let path = CGMutablePath()
        // Center the ellipse at origin
        let rect = CGRect(x: -size.width/2, y: -size.height/2, width: size.width, height: size.height)
        path.addEllipse(in: rect)
        layer.path = path
        layer.name = "Ellipse"
        return layer
    }
    
    static func polygon(sides: Int, radius: CGFloat) -> VectorShapeLayer {
        let layer = VectorShapeLayer()
        let path = CGMutablePath()
        
        let angleStep = (2 * .pi) / CGFloat(sides)
        
        // For consistent sizing, adjust radius so polygon fits in a square
        // For a triangle, the height is 1.5 * radius, so scale down
        let adjustedRadius: CGFloat
        switch sides {
        case 3: // Triangle - inscribed circle radius for equilateral triangle
            adjustedRadius = radius * 0.577  // radius / sqrt(3)
        case 4: // Square - already fits perfectly
            adjustedRadius = radius * 0.707  // radius / sqrt(2)
        default: // Other polygons
            adjustedRadius = radius * 0.8  // General adjustment
        }
        
        // Start from the top (12 o'clock position) centered at origin
        var points: [CGPoint] = []
        for i in 0..<sides {
            // Start from -π/2 (top) and go clockwise
            let angle = -CGFloat.pi/2 + angleStep * CGFloat(i)
            let x = adjustedRadius * cos(angle)
            let y = adjustedRadius * sin(angle)
            points.append(CGPoint(x: x, y: y))
        }
        
        // Create path
        if !points.isEmpty {
            path.move(to: points[0])
            for i in 1..<points.count {
                path.addLine(to: points[i])
            }
            path.closeSubpath()
        }
        
        layer.path = path
        // Use specific names for common shapes
        switch sides {
        case 3:
            layer.name = "Triangle"
        case 4:
            layer.name = "Square"
        case 5:
            layer.name = "Pentagon"
        case 6:
            layer.name = "Hexagon"
        default:
            layer.name = "Polygon (\(sides) sides)"
        }
        layer.polygonRadius = radius  // Store original radius
        return layer
    }
}
