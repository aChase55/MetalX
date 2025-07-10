import Metal
import CoreGraphics
import CoreImage
import ImageIO
import Foundation
import os.log

public enum TextureLoaderError: Error, LocalizedError {
    case imageCreationFailed
    case unsupportedFormat
    case invalidImageData
    case textureCreationFailed
    case memoryAllocationFailed
    case compressionFailed
    
    public var errorDescription: String? {
        switch self {
        case .imageCreationFailed:
            return "Failed to create image from data"
        case .unsupportedFormat:
            return "Unsupported image format"
        case .invalidImageData:
            return "Invalid image data"
        case .textureCreationFailed:
            return "Failed to create Metal texture"
        case .memoryAllocationFailed:
            return "Memory allocation failed"
        case .compressionFailed:
            return "Texture compression failed"
        }
    }
}

public enum TextureUsageType {
    case color
    case normal
    case mask
    case data
    case hdr
    case depth
    
    public var preferredPixelFormats: [MTLPixelFormat] {
        switch self {
        case .color:
            return [.rgba8Unorm_srgb, .bgra8Unorm_srgb, .rgba8Unorm, .bgra8Unorm]
        case .normal:
            return [.rg8Unorm, .rgba8Unorm, .rgba16Float]
        case .mask:
            return [.r8Unorm, .a8Unorm, .rgba8Unorm]
        case .data:
            return [.rgba16Float, .rgba32Float, .rgba8Unorm]
        case .hdr:
            return [.rgba16Float, .rgba32Float, .rgb9e5Float]
        case .depth:
            return [.depth32Float, .depth16Unorm]
        }
    }
    
    public var shouldGenerateMipmaps: Bool {
        switch self {
        case .color, .normal: return true
        case .mask, .data, .hdr, .depth: return false
        }
    }
    
    public var compressionSupport: Bool {
        switch self {
        case .color: return true
        case .normal, .mask: return true
        case .data, .hdr, .depth: return false
        }
    }
}

public struct TextureLoadOptions {
    public let usageType: TextureUsageType
    public let generateMipmaps: Bool
    public let allowCompression: Bool
    public let flipVertically: Bool
    public let premultiplyAlpha: Bool
    public let sRGBCorrection: Bool
    public let maxSize: Int?
    public let priority: TexturePriority
    
    public init(
        usageType: TextureUsageType = .color,
        generateMipmaps: Bool? = nil,
        allowCompression: Bool? = nil,
        flipVertically: Bool = false,
        premultiplyAlpha: Bool = true,
        sRGBCorrection: Bool? = nil,
        maxSize: Int? = nil,
        priority: TexturePriority = .normal
    ) {
        self.usageType = usageType
        self.generateMipmaps = generateMipmaps ?? usageType.shouldGenerateMipmaps
        self.allowCompression = allowCompression ?? usageType.compressionSupport
        self.flipVertically = flipVertically
        self.premultiplyAlpha = premultiplyAlpha
        self.sRGBCorrection = sRGBCorrection ?? (usageType == .color)
        self.maxSize = maxSize
        self.priority = priority
    }
    
    public static var `default`: TextureLoadOptions {
        return TextureLoadOptions()
    }
    
    public static var normal: TextureLoadOptions {
        return TextureLoadOptions(usageType: .normal, sRGBCorrection: false)
    }
    
    public static var mask: TextureLoadOptions {
        return TextureLoadOptions(usageType: .mask, generateMipmaps: false, sRGBCorrection: false)
    }
    
    public static var hdr: TextureLoadOptions {
        return TextureLoadOptions(usageType: .hdr, allowCompression: false, sRGBCorrection: false)
    }
}

public struct LoadedImageData {
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    public let pixelFormat: MTLPixelFormat
    public let data: Data
    public let colorSpace: CGColorSpace?
    public let hasAlpha: Bool
    
    public init(width: Int, height: Int, bytesPerRow: Int, pixelFormat: MTLPixelFormat, data: Data, colorSpace: CGColorSpace?, hasAlpha: Bool) {
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.pixelFormat = pixelFormat
        self.data = data
        self.colorSpace = colorSpace
        self.hasAlpha = hasAlpha
    }
    
    public var size: CGSize {
        return CGSize(width: width, height: height)
    }
    
    public var memorySize: Int {
        return data.count
    }
}

public class TextureLoader {
    private let device: MetalDevice
    private let texturePool: TexturePool
    private let logger = Logger(subsystem: "com.metalx.engine", category: "TextureLoader")
    
    private let loadingQueue = DispatchQueue(label: "com.metalx.texture.loading", qos: .userInitiated, attributes: .concurrent)
    private let compressionQueue = DispatchQueue(label: "com.metalx.texture.compression", qos: .utility)
    
    public init(device: MetalDevice, texturePool: TexturePool) {
        self.device = device
        self.texturePool = texturePool
    }
    
    // MARK: - Public Loading Methods
    
    public func loadTexture(from url: URL, options: TextureLoadOptions = .default) async throws -> MTLTexture {
        let imageData = try await loadImageData(from: url, options: options)
        return try await createTexture(from: imageData, options: options)
    }
    
    public func loadTexture(from data: Data, options: TextureLoadOptions = .default) async throws -> MTLTexture {
        let imageData = try await loadImageData(from: data, options: options)
        return try await createTexture(from: imageData, options: options)
    }
    
    public func loadTexture(from cgImage: CGImage, options: TextureLoadOptions = .default) async throws -> MTLTexture {
        let imageData = try await loadImageData(from: cgImage, options: options)
        return try await createTexture(from: imageData, options: options)
    }
    
    public func loadTexture(from ciImage: CIImage, options: TextureLoadOptions = .default) async throws -> MTLTexture {
        let cgImage = try await convertCIImageToCGImage(ciImage)
        return try await loadTexture(from: cgImage, options: options)
    }
    
    // MARK: - Image Data Loading
    
    public func loadImageData(from url: URL, options: TextureLoadOptions) async throws -> LoadedImageData {
        return try await withCheckedThrowingContinuation { continuation in
            loadingQueue.async {
                do {
                    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                        continuation.resume(throwing: TextureLoaderError.imageCreationFailed)
                        return
                    }
                    
                    let imageData = try self.processImageSource(imageSource, options: options)
                    continuation.resume(returning: imageData)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    public func loadImageData(from data: Data, options: TextureLoadOptions) async throws -> LoadedImageData {
        return try await withCheckedThrowingContinuation { continuation in
            loadingQueue.async {
                do {
                    guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
                        continuation.resume(throwing: TextureLoaderError.imageCreationFailed)
                        return
                    }
                    
                    let imageData = try self.processImageSource(imageSource, options: options)
                    continuation.resume(returning: imageData)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    public func loadImageData(from cgImage: CGImage, options: TextureLoadOptions) async throws -> LoadedImageData {
        return try await withCheckedThrowingContinuation { continuation in
            loadingQueue.async {
                do {
                    let imageData = try self.processImage(cgImage, options: options)
                    continuation.resume(returning: imageData)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Image Processing
    
    private func processImageSource(_ imageSource: CGImageSource, options: TextureLoadOptions) throws -> LoadedImageData {
        guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw TextureLoaderError.imageCreationFailed
        }
        
        return try processImage(cgImage, options: options)
    }
    
    private func processImage(_ cgImage: CGImage, options: TextureLoadOptions) throws -> LoadedImageData {
        var processedImage = cgImage
        
        // Apply size constraints
        if let maxSize = options.maxSize {
            processedImage = try resizeImage(processedImage, maxSize: maxSize)
        }
        
        // Select optimal pixel format
        let pixelFormat = selectPixelFormat(for: processedImage, options: options)
        
        // Create bitmap context with appropriate settings
        let (context, data) = try createBitmapContext(for: processedImage, pixelFormat: pixelFormat, options: options)
        
        // Draw image into context
        drawImage(processedImage, into: context, options: options)
        
        return LoadedImageData(
            width: processedImage.width,
            height: processedImage.height,
            bytesPerRow: context.bytesPerRow,
            pixelFormat: pixelFormat,
            data: data,
            colorSpace: processedImage.colorSpace,
            hasAlpha: processedImage.alphaInfo != .none
        )
    }
    
    private func selectPixelFormat(for image: CGImage, options: TextureLoadOptions) -> MTLPixelFormat {
        let preferredFormats = options.usageType.preferredPixelFormats
        
        for format in preferredFormats {
            if device.supportsTexture(format: format) {
                // Additional validation based on image properties
                if validatePixelFormat(format, for: image, options: options) {
                    return format
                }
            }
        }
        
        // Fallback to RGBA8
        return options.sRGBCorrection ? .rgba8Unorm_srgb : .rgba8Unorm
    }
    
    private func validatePixelFormat(_ format: MTLPixelFormat, for image: CGImage, options: TextureLoadOptions) -> Bool {
        switch format {
        case .rgba8Unorm_srgb, .bgra8Unorm_srgb:
            return options.sRGBCorrection
        case .rgba8Unorm, .bgra8Unorm:
            return !options.sRGBCorrection || !options.usageType.compressionSupport
        case .r8Unorm, .a8Unorm:
            return options.usageType == .mask
        case .rg8Unorm:
            return options.usageType == .normal
        case .rgba16Float, .rgba32Float:
            return options.usageType == .hdr || options.usageType == .data
        default:
            return true
        }
    }
    
    private func createBitmapContext(for image: CGImage, pixelFormat: MTLPixelFormat, options: TextureLoadOptions) throws -> (CGContext, Data) {
        let width = image.width
        let height = image.height
        let bytesPerPixel = pixelFormat.bytesPerPixel
        let bytesPerRow = width * bytesPerPixel
        let dataSize = height * bytesPerRow
        
        var data = Data(count: dataSize)
        
        let colorSpace: CGColorSpace
        let bitmapInfo: CGBitmapInfo
        
        switch pixelFormat {
        case .rgba8Unorm, .rgba8Unorm_srgb:
            colorSpace = options.sRGBCorrection ? CGColorSpace(name: CGColorSpace.sRGB)! : CGColorSpace(name: CGColorSpace.linearSRGB)!
            bitmapInfo = options.premultiplyAlpha ? 
                CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue) :
                CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
                
        case .bgra8Unorm, .bgra8Unorm_srgb:
            colorSpace = options.sRGBCorrection ? CGColorSpace(name: CGColorSpace.sRGB)! : CGColorSpace(name: CGColorSpace.linearSRGB)!
            bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            
        case .r8Unorm, .a8Unorm:
            colorSpace = CGColorSpace(name: CGColorSpace.linearGray)!
            bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
            
        default:
            colorSpace = CGColorSpace(name: CGColorSpace.linearSRGB)!
            bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        }
        
        guard let context = data.withUnsafeMutableBytes({ bytes in
            CGContext(
                data: bytes.bindMemory(to: UInt8.self).baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            )
        }) else {
            throw TextureLoaderError.imageCreationFailed
        }
        
        return (context, data)
    }
    
    private func drawImage(_ image: CGImage, into context: CGContext, options: TextureLoadOptions) {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        
        // Configure context
        context.interpolationQuality = .high
        
        // Clear background if needed
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        
        // Calculate draw rect
        var drawRect = CGRect(x: 0, y: 0, width: width, height: height)
        
        if options.flipVertically {
            context.scaleBy(x: 1, y: -1)
            drawRect.origin.y = -height
        }
        
        // Draw image
        context.draw(image, in: drawRect)
    }
    
    private func resizeImage(_ image: CGImage, maxSize: Int) throws -> CGImage {
        let width = image.width
        let height = image.height
        let maxDimension = max(width, height)
        
        guard maxDimension > maxSize else {
            return image // No resizing needed
        }
        
        let scale = Float(maxSize) / Float(maxDimension)
        let newWidth = Int(Float(width) * scale)
        let newHeight = Int(Float(height) * scale)
        
        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            throw TextureLoaderError.imageCreationFailed
        }
        
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        
        guard let resizedImage = context.makeImage() else {
            throw TextureLoaderError.imageCreationFailed
        }
        
        return resizedImage
    }
    
    // MARK: - Texture Creation
    
    private func createTexture(from imageData: LoadedImageData, options: TextureLoadOptions) async throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: imageData.pixelFormat,
            width: imageData.width,
            height: imageData.height,
            mipmapped: options.generateMipmaps
        )
        
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = device.optimalStorageMode(for: [.read])
        
        let texture = try texturePool.acquireTexture(descriptor: descriptor, priority: options.priority)
        
        // Upload image data
        try await uploadImageData(imageData, to: texture, generateMipmaps: options.generateMipmaps)
        
        return texture
    }
    
    private func uploadImageData(_ imageData: LoadedImageData, to texture: MTLTexture, generateMipmaps: Bool) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            loadingQueue.async {
                do {
                    // Upload base level
                    imageData.data.withUnsafeBytes { bytes in
                        texture.replace(
                            region: MTLRegion(
                                origin: MTLOrigin(x: 0, y: 0, z: 0),
                                size: MTLSize(width: imageData.width, height: imageData.height, depth: 1)
                            ),
                            mipmapLevel: 0,
                            withBytes: bytes.baseAddress!,
                            bytesPerRow: imageData.bytesPerRow
                        )
                    }
                    
                    // Generate mipmaps if requested
                    if generateMipmaps && texture.mipmapLevelCount > 1 {
                        try self.generateMipmaps(for: texture)
                    }
                    
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func generateMipmaps(for texture: MTLTexture) throws {
        // Only generate mipmaps if texture has multiple mip levels
        guard texture.mipmapLevelCount > 1 else {
            return // No need to generate mipmaps for single-level textures
        }
        
        guard let commandBuffer = device.makeCommandBuffer(label: "Mipmap Generation") else {
            throw TextureLoaderError.textureCreationFailed
        }
        
        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            throw TextureLoaderError.textureCreationFailed
        }
        
        blitEncoder.generateMipmaps(for: texture)
        blitEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        if let error = commandBuffer.error {
            throw error
        }
    }
    
    // MARK: - Utility Methods
    
    private func convertCIImageToCGImage(_ ciImage: CIImage) async throws -> CGImage {
        return try await withCheckedThrowingContinuation { continuation in
            loadingQueue.async {
                let context = CIContext()
                
                guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
                    continuation.resume(throwing: TextureLoaderError.imageCreationFailed)
                    return
                }
                
                continuation.resume(returning: cgImage)
            }
        }
    }
    
    public func preloadTextures(urls: [URL], options: TextureLoadOptions = .default) {
        for url in urls {
            Task {
                do {
                    let texture = try await loadTexture(from: url, options: options)
                    // Texture is now cached in the pool
                    texturePool.returnTexture(texture)
                } catch {
                    logger.error("Failed to preload texture \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
    }
    
    public func supportedFormats(for usageType: TextureUsageType) -> [MTLPixelFormat] {
        return usageType.preferredPixelFormats.filter { 
            device.supportsTexture(format: $0)
        }
    }
    
    public func estimateMemoryUsage(for image: CGImage, options: TextureLoadOptions) -> Int {
        let width = image.width
        let height = image.height
        let pixelFormat = selectPixelFormat(for: image, options: options)
        let bytesPerPixel = pixelFormat.bytesPerPixel
        
        var totalSize = width * height * bytesPerPixel
        
        if options.generateMipmaps {
            // Mipmaps add approximately 33% more memory
            totalSize = Int(Double(totalSize) * 1.33)
        }
        
        return totalSize
    }
}

// MARK: - Extensions

extension TextureLoader {
    public static func createSolidColorTexture(
        device: MetalDevice,
        texturePool: TexturePool,
        color: SIMD4<Float>,
        size: CGSize = CGSize(width: 1, height: 1)
    ) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: Int(size.width),
            height: Int(size.height),
            mipmapped: false
        )
        
        descriptor.usage = [.shaderRead]
        
        let texture = try texturePool.acquireTexture(descriptor: descriptor)
        
        // Create color data
        let pixelCount = Int(size.width * size.height)
        var pixelData = [UInt8]()
        
        for _ in 0..<pixelCount {
            pixelData.append(UInt8(color.x * 255))
            pixelData.append(UInt8(color.y * 255))
            pixelData.append(UInt8(color.z * 255))
            pixelData.append(UInt8(color.w * 255))
        }
        
        texture.replace(
            region: MTLRegion(
                origin: MTLOrigin(x: 0, y: 0, z: 0),
                size: MTLSize(width: Int(size.width), height: Int(size.height), depth: 1)
            ),
            mipmapLevel: 0,
            withBytes: pixelData,
            bytesPerRow: Int(size.width) * 4
        )
        
        return texture
    }
    
    public static func createCheckerboardTexture(
        device: MetalDevice,
        texturePool: TexturePool,
        size: CGSize = CGSize(width: 512, height: 512),
        checkerSize: Int = 64,
        color1: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1),
        color2: SIMD4<Float> = SIMD4<Float>(0.8, 0.8, 0.8, 1)
    ) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: Int(size.width),
            height: Int(size.height),
            mipmapped: true
        )
        
        descriptor.usage = [.shaderRead]
        
        let texture = try texturePool.acquireTexture(descriptor: descriptor)
        
        // Generate checkerboard pattern
        let width = Int(size.width)
        let height = Int(size.height)
        var pixelData = [UInt8]()
        
        for y in 0..<height {
            for x in 0..<width {
                let checkerX = x / checkerSize
                let checkerY = y / checkerSize
                let isEven = (checkerX + checkerY) % 2 == 0
                let color = isEven ? color1 : color2
                
                pixelData.append(UInt8(color.x * 255))
                pixelData.append(UInt8(color.y * 255))
                pixelData.append(UInt8(color.z * 255))
                pixelData.append(UInt8(color.w * 255))
            }
        }
        
        texture.replace(
            region: MTLRegion(
                origin: MTLOrigin(x: 0, y: 0, z: 0),
                size: MTLSize(width: width, height: height, depth: 1)
            ),
            mipmapLevel: 0,
            withBytes: pixelData,
            bytesPerRow: width * 4
        )
        
        // Generate mipmaps only if texture has multiple mip levels
        if texture.mipmapLevelCount > 1,
           let commandBuffer = device.makeCommandBuffer(label: "Checkerboard Mipmaps"),
           let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
            blitEncoder.generateMipmaps(for: texture)
            blitEncoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
        
        return texture
    }
}