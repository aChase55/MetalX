import Metal
import Foundation
import CryptoKit
import os.log

public enum RenderPassError: Error, LocalizedError {
    case invalidAttachment
    case incompatibleFormat
    case unsupportedConfiguration
    case attachmentMismatch
    
    public var errorDescription: String? {
        switch self {
        case .invalidAttachment:
            return "Invalid render pass attachment"
        case .incompatibleFormat:
            return "Incompatible pixel format for attachment"
        case .unsupportedConfiguration:
            return "Unsupported render pass configuration"
        case .attachmentMismatch:
            return "Render pass attachment mismatch"
        }
    }
}

public struct RenderPassAttachment {
    public let texture: MTLTexture?
    public let level: Int
    public let slice: Int
    public let depthPlane: Int
    public let loadAction: MTLLoadAction
    public let storeAction: MTLStoreAction
    public let clearColor: MTLClearColor
    public let clearDepth: Double
    public let clearStencil: UInt32
    public let resolveTexture: MTLTexture?
    public let resolveLevel: Int
    public let resolveSlice: Int
    public let resolveDepthPlane: Int
    
    public init(
        texture: MTLTexture? = nil,
        level: Int = 0,
        slice: Int = 0,
        depthPlane: Int = 0,
        loadAction: MTLLoadAction = .clear,
        storeAction: MTLStoreAction = .store,
        clearColor: MTLClearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0),
        clearDepth: Double = 1.0,
        clearStencil: UInt32 = 0,
        resolveTexture: MTLTexture? = nil,
        resolveLevel: Int = 0,
        resolveSlice: Int = 0,
        resolveDepthPlane: Int = 0
    ) {
        self.texture = texture
        self.level = level
        self.slice = slice
        self.depthPlane = depthPlane
        self.loadAction = loadAction
        self.storeAction = storeAction
        self.clearColor = clearColor
        self.clearDepth = clearDepth
        self.clearStencil = clearStencil
        self.resolveTexture = resolveTexture
        self.resolveLevel = resolveLevel
        self.resolveSlice = resolveSlice
        self.resolveDepthPlane = resolveDepthPlane
    }
    
    public var isValid: Bool {
        return texture != nil
    }
    
    public var hasResolveTexture: Bool {
        return resolveTexture != nil
    }
    
    public var pixelFormat: MTLPixelFormat {
        return texture?.pixelFormat ?? .invalid
    }
    
    public var sampleCount: Int {
        return texture?.sampleCount ?? 1
    }
}

public struct RenderPassDescriptor {
    public var colorAttachments: [RenderPassAttachment]
    public var depthAttachment: RenderPassAttachment?
    public var stencilAttachment: RenderPassAttachment?
    public var visibilityResultBuffer: MTLBuffer?
    public var renderTargetArrayLength: Int
    public var renderTargetWidth: Int
    public var renderTargetHeight: Int
    public var defaultRasterSampleCount: Int
    public var imageblockSampleLength: Int
    public var threadgroupMemoryLength: Int
    public var tileWidth: Int
    public var tileHeight: Int
    
    public init() {
        self.colorAttachments = Array(repeating: RenderPassAttachment(), count: 8)
        self.depthAttachment = nil
        self.stencilAttachment = nil
        self.visibilityResultBuffer = nil
        self.renderTargetArrayLength = 1
        self.renderTargetWidth = 0
        self.renderTargetHeight = 0
        self.defaultRasterSampleCount = 1
        self.imageblockSampleLength = 0
        self.threadgroupMemoryLength = 0
        self.tileWidth = 0
        self.tileHeight = 0
    }
    
    public var isValid: Bool {
        let hasValidColorAttachment = colorAttachments.prefix(8).contains { $0.isValid }
        let hasValidDepthAttachment = depthAttachment?.isValid ?? false
        let hasValidStencilAttachment = stencilAttachment?.isValid ?? false
        
        return hasValidColorAttachment || hasValidDepthAttachment || hasValidStencilAttachment
    }
    
    public var primaryTexture: MTLTexture? {
        return colorAttachments.first { $0.isValid }?.texture ?? depthAttachment?.texture
    }
    
    public var renderTargetSize: (width: Int, height: Int) {
        if renderTargetWidth > 0 && renderTargetHeight > 0 {
            return (renderTargetWidth, renderTargetHeight)
        }
        
        if let texture = primaryTexture {
            return (texture.width, texture.height)
        }
        
        return (0, 0)
    }
    
    public mutating func setColorAttachment(_ attachment: RenderPassAttachment, at index: Int) {
        guard index >= 0 && index < 8 else { return }
        colorAttachments[index] = attachment
        updateRenderTargetDimensions()
    }
    
    public mutating func setDepthAttachment(_ attachment: RenderPassAttachment) {
        depthAttachment = attachment
        updateRenderTargetDimensions()
    }
    
    public mutating func setStencilAttachment(_ attachment: RenderPassAttachment) {
        stencilAttachment = attachment
        updateRenderTargetDimensions()
    }
    
    private mutating func updateRenderTargetDimensions() {
        if let texture = primaryTexture {
            renderTargetWidth = texture.width
            renderTargetHeight = texture.height
            defaultRasterSampleCount = texture.sampleCount
        }
    }
    
    public func validate() throws {
        guard isValid else {
            throw RenderPassError.invalidAttachment
        }
        
        // Validate color attachments
        let validColorAttachments = colorAttachments.prefix(8).filter { $0.isValid }
        for attachment in validColorAttachments {
            guard let texture = attachment.texture else { continue }
            
            if texture.usage.contains(.renderTarget) == false {
                throw RenderPassError.incompatibleFormat
            }
        }
        
        // Validate depth attachment
        if let depthAttachment = depthAttachment, depthAttachment.isValid {
            guard let texture = depthAttachment.texture else {
                throw RenderPassError.invalidAttachment
            }
            
            if !texture.pixelFormat.isDepthFormat {
                throw RenderPassError.incompatibleFormat
            }
        }
        
        // Validate stencil attachment
        if let stencilAttachment = stencilAttachment, stencilAttachment.isValid {
            guard let texture = stencilAttachment.texture else {
                throw RenderPassError.invalidAttachment
            }
            
            if !texture.pixelFormat.isStencilFormat {
                throw RenderPassError.incompatibleFormat
            }
        }
        
        // Check sample count consistency
        var sampleCounts = validColorAttachments.map { $0.sampleCount }
        if let depthAttachment = depthAttachment, depthAttachment.isValid {
            sampleCounts.append(depthAttachment.sampleCount)
        }
        if let stencilAttachment = stencilAttachment, stencilAttachment.isValid {
            sampleCounts.append(stencilAttachment.sampleCount)
        }
        
        if Set(sampleCounts).count > 1 {
            throw RenderPassError.attachmentMismatch
        }
    }
}

public class RenderPassCache {
    private let device: MetalDevice
    private let logger = Logger(subsystem: "com.metalx.engine", category: "RenderPassCache")
    
    private var descriptorCache: [String: MTLRenderPassDescriptor] = [:]
    private var accessCounts: [String: Int] = [:]
    private var lastAccessTime: [String: Date] = [:]
    
    private let maxCacheSize: Int = 256
    private let accessQueue = DispatchQueue(label: "com.metalx.renderpass.cache", attributes: .concurrent)
    
    public init(device: MetalDevice) {
        self.device = device
    }
    
    public func getDescriptor(for renderPass: RenderPassDescriptor) throws -> MTLRenderPassDescriptor {
        try renderPass.validate()
        
        let cacheKey = generateCacheKey(for: renderPass)
        
        if let cached = getCachedDescriptor(for: cacheKey) {
            return cached
        }
        
        return try accessQueue.sync(flags: .barrier) {
            // Double-check pattern
            if let cached = descriptorCache[cacheKey] {
                recordAccess(for: cacheKey)
                return cached
            }
            
            let mtlDescriptor = try createMTLDescriptor(from: renderPass)
            descriptorCache[cacheKey] = mtlDescriptor
            recordAccess(for: cacheKey)
            
            // Perform cache maintenance if needed
            if descriptorCache.count > maxCacheSize {
                performCacheMaintenance()
            }
            
            return mtlDescriptor
        }
    }
    
    public func clearCache() {
        accessQueue.async(flags: .barrier) {
            self.descriptorCache.removeAll()
            self.accessCounts.removeAll()
            self.lastAccessTime.removeAll()
        }
        logger.info("Render pass descriptor cache cleared")
    }
    
    public var cacheStatistics: (entries: Int, totalAccesses: Int) {
        return accessQueue.sync {
            let totalAccesses = accessCounts.values.reduce(0, +)
            return (entries: descriptorCache.count, totalAccesses: totalAccesses)
        }
    }
    
    private func getCachedDescriptor(for key: String) -> MTLRenderPassDescriptor? {
        return accessQueue.sync {
            guard let descriptor = descriptorCache[key] else { return nil }
            recordAccess(for: key)
            return descriptor
        }
    }
    
    private func recordAccess(for key: String) {
        accessCounts[key, default: 0] += 1
        lastAccessTime[key] = Date()
    }
    
    private func createMTLDescriptor(from renderPass: RenderPassDescriptor) throws -> MTLRenderPassDescriptor {
        let descriptor = MTLRenderPassDescriptor()
        
        // Configure color attachments
        for (index, attachment) in renderPass.colorAttachments.enumerated() {
            guard index < 8 && attachment.isValid else { continue }
            
            let mtlAttachment = descriptor.colorAttachments[index]!
            mtlAttachment.texture = attachment.texture
            mtlAttachment.level = attachment.level
            mtlAttachment.slice = attachment.slice
            mtlAttachment.depthPlane = attachment.depthPlane
            mtlAttachment.loadAction = attachment.loadAction
            mtlAttachment.storeAction = attachment.storeAction
            mtlAttachment.clearColor = attachment.clearColor
            
            if attachment.hasResolveTexture {
                mtlAttachment.resolveTexture = attachment.resolveTexture
                mtlAttachment.resolveLevel = attachment.resolveLevel
                mtlAttachment.resolveSlice = attachment.resolveSlice
                mtlAttachment.resolveDepthPlane = attachment.resolveDepthPlane
            }
        }
        
        // Configure depth attachment
        if let depthAttachment = renderPass.depthAttachment, depthAttachment.isValid {
            descriptor.depthAttachment.texture = depthAttachment.texture
            descriptor.depthAttachment.level = depthAttachment.level
            descriptor.depthAttachment.slice = depthAttachment.slice
            descriptor.depthAttachment.depthPlane = depthAttachment.depthPlane
            descriptor.depthAttachment.loadAction = depthAttachment.loadAction
            descriptor.depthAttachment.storeAction = depthAttachment.storeAction
            descriptor.depthAttachment.clearDepth = depthAttachment.clearDepth
            
            if depthAttachment.hasResolveTexture {
                descriptor.depthAttachment.resolveTexture = depthAttachment.resolveTexture
                descriptor.depthAttachment.resolveLevel = depthAttachment.resolveLevel
                descriptor.depthAttachment.resolveSlice = depthAttachment.resolveSlice
                descriptor.depthAttachment.resolveDepthPlane = depthAttachment.resolveDepthPlane
            }
        }
        
        // Configure stencil attachment
        if let stencilAttachment = renderPass.stencilAttachment, stencilAttachment.isValid {
            descriptor.stencilAttachment.texture = stencilAttachment.texture
            descriptor.stencilAttachment.level = stencilAttachment.level
            descriptor.stencilAttachment.slice = stencilAttachment.slice
            descriptor.stencilAttachment.depthPlane = stencilAttachment.depthPlane
            descriptor.stencilAttachment.loadAction = stencilAttachment.loadAction
            descriptor.stencilAttachment.storeAction = stencilAttachment.storeAction
            descriptor.stencilAttachment.clearStencil = stencilAttachment.clearStencil
            
            if stencilAttachment.hasResolveTexture {
                descriptor.stencilAttachment.resolveTexture = stencilAttachment.resolveTexture
                descriptor.stencilAttachment.resolveLevel = stencilAttachment.resolveLevel
                descriptor.stencilAttachment.resolveSlice = stencilAttachment.resolveSlice
                descriptor.stencilAttachment.resolveDepthPlane = stencilAttachment.resolveDepthPlane
            }
        }
        
        // Configure additional properties
        descriptor.visibilityResultBuffer = renderPass.visibilityResultBuffer
        descriptor.renderTargetArrayLength = renderPass.renderTargetArrayLength
        
        if renderPass.renderTargetWidth > 0 && renderPass.renderTargetHeight > 0 {
            descriptor.renderTargetWidth = renderPass.renderTargetWidth
            descriptor.renderTargetHeight = renderPass.renderTargetHeight
        }
        
        descriptor.defaultRasterSampleCount = renderPass.defaultRasterSampleCount
        
        // Configure tile-based rendering parameters if supported
        if device.capabilities.isTBDR {
            descriptor.imageblockSampleLength = renderPass.imageblockSampleLength
            descriptor.threadgroupMemoryLength = renderPass.threadgroupMemoryLength
            
            if renderPass.tileWidth > 0 && renderPass.tileHeight > 0 {
                descriptor.tileWidth = renderPass.tileWidth
                descriptor.tileHeight = renderPass.tileHeight
            }
        }
        
        return descriptor
    }
    
    private func generateCacheKey(for renderPass: RenderPassDescriptor) -> String {
        var hasher = SHA256()
        
        // Hash color attachments
        for (index, attachment) in renderPass.colorAttachments.enumerated() {
            guard attachment.isValid else { continue }
            
            hasher.update(data: Data([UInt8(index)]))
            hasher.update(data: Data([UInt8(attachment.pixelFormat.rawValue)]))
            hasher.update(data: Data([UInt8(attachment.loadAction.rawValue)]))
            hasher.update(data: Data([UInt8(attachment.storeAction.rawValue)]))
            hasher.update(data: Data([UInt8(attachment.sampleCount)]))
            
            if attachment.hasResolveTexture {
                hasher.update(data: Data([1]))
            } else {
                hasher.update(data: Data([0]))
            }
        }
        
        // Hash depth attachment
        if let depthAttachment = renderPass.depthAttachment, depthAttachment.isValid {
            hasher.update(data: Data([UInt8(depthAttachment.pixelFormat.rawValue)]))
            hasher.update(data: Data([UInt8(depthAttachment.loadAction.rawValue)]))
            hasher.update(data: Data([UInt8(depthAttachment.storeAction.rawValue)]))
        }
        
        // Hash stencil attachment
        if let stencilAttachment = renderPass.stencilAttachment, stencilAttachment.isValid {
            hasher.update(data: Data([UInt8(stencilAttachment.pixelFormat.rawValue)]))
            hasher.update(data: Data([UInt8(stencilAttachment.loadAction.rawValue)]))
            hasher.update(data: Data([UInt8(stencilAttachment.storeAction.rawValue)]))
        }
        
        // Hash render target dimensions
        hasher.update(data: Data([UInt8(renderPass.renderTargetWidth & 0xFF)]))
        hasher.update(data: Data([UInt8(renderPass.renderTargetWidth >> 8)]))
        hasher.update(data: Data([UInt8(renderPass.renderTargetHeight & 0xFF)]))
        hasher.update(data: Data([UInt8(renderPass.renderTargetHeight >> 8)]))
        
        let digest = hasher.finalize()
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    private func performCacheMaintenance() {
        let now = Date()
        let maxAge: TimeInterval = 300 // 5 minutes
        
        // Remove old entries first
        var keysToRemove: [String] = []
        for (key, lastAccess) in lastAccessTime {
            if now.timeIntervalSince(lastAccess) > maxAge {
                keysToRemove.append(key)
            }
        }
        
        // If still over capacity, remove least frequently used
        if descriptorCache.count - keysToRemove.count > maxCacheSize * 3 / 4 {
            let sortedByAccess = accessCounts.sorted { $0.value < $1.value }
            let additionalRemovalCount = descriptorCache.count - keysToRemove.count - maxCacheSize * 3 / 4
            
            for (key, _) in sortedByAccess.prefix(additionalRemovalCount) {
                if !keysToRemove.contains(key) {
                    keysToRemove.append(key)
                }
            }
        }
        
        // Remove selected entries
        for key in keysToRemove {
            descriptorCache.removeValue(forKey: key)
            accessCounts.removeValue(forKey: key)
            lastAccessTime.removeValue(forKey: key)
        }
        
        if !keysToRemove.isEmpty {
            logger.info("Evicted \(keysToRemove.count) render pass descriptors from cache")
        }
    }
}

// MARK: - MTLPixelFormat Extensions

extension MTLPixelFormat {
    public var isDepthFormat: Bool {
        switch self {
        case .depth16Unorm, .depth32Float, .depth24Unorm_stencil8, .depth32Float_stencil8:
            return true
        default:
            return false
        }
    }
    
    public var isStencilFormat: Bool {
        switch self {
        case .stencil8, .depth24Unorm_stencil8, .depth32Float_stencil8, .x24_stencil8, .x32_stencil8:
            return true
        default:
            return false
        }
    }
    
    public var isColorFormat: Bool {
        return !isDepthFormat && !isStencilFormat && self != .invalid
    }
    
    public var bytesPerPixel: Int {
        switch self {
        case .r8Unorm, .r8Snorm, .r8Uint, .r8Sint, .a8Unorm:
            return 1
        case .r16Unorm, .r16Snorm, .r16Uint, .r16Sint, .r16Float, .rg8Unorm, .rg8Snorm, .rg8Uint, .rg8Sint:
            return 2
        case .r32Uint, .r32Sint, .r32Float, .rg16Unorm, .rg16Snorm, .rg16Uint, .rg16Sint, .rg16Float, .rgba8Unorm, .rgba8Unorm_srgb, .rgba8Snorm, .rgba8Uint, .rgba8Sint, .bgra8Unorm, .bgra8Unorm_srgb:
            return 4
        case .rg32Uint, .rg32Sint, .rg32Float, .rgba16Unorm, .rgba16Snorm, .rgba16Uint, .rgba16Sint, .rgba16Float:
            return 8
        case .rgba32Uint, .rgba32Sint, .rgba32Float:
            return 16
        default:
            return 4 // Default assumption
        }
    }
}

// MARK: - Convenience Extensions

extension RenderPassDescriptor {
    public static func colorOnly(
        texture: MTLTexture,
        loadAction: MTLLoadAction = .clear,
        storeAction: MTLStoreAction = .store,
        clearColor: MTLClearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
    ) -> RenderPassDescriptor {
        var descriptor = RenderPassDescriptor()
        let attachment = RenderPassAttachment(
            texture: texture,
            loadAction: loadAction,
            storeAction: storeAction,
            clearColor: clearColor
        )
        descriptor.setColorAttachment(attachment, at: 0)
        return descriptor
    }
    
    public static func depthOnly(
        texture: MTLTexture,
        loadAction: MTLLoadAction = .clear,
        storeAction: MTLStoreAction = .store,
        clearDepth: Double = 1.0
    ) -> RenderPassDescriptor {
        var descriptor = RenderPassDescriptor()
        let attachment = RenderPassAttachment(
            texture: texture,
            loadAction: loadAction,
            storeAction: storeAction,
            clearDepth: clearDepth
        )
        descriptor.setDepthAttachment(attachment)
        return descriptor
    }
    
    public static func colorAndDepth(
        colorTexture: MTLTexture,
        depthTexture: MTLTexture,
        colorLoadAction: MTLLoadAction = .clear,
        depthLoadAction: MTLLoadAction = .clear,
        clearColor: MTLClearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0),
        clearDepth: Double = 1.0
    ) -> RenderPassDescriptor {
        var descriptor = RenderPassDescriptor()
        
        let colorAttachment = RenderPassAttachment(
            texture: colorTexture,
            loadAction: colorLoadAction,
            clearColor: clearColor
        )
        descriptor.setColorAttachment(colorAttachment, at: 0)
        
        let depthAttachment = RenderPassAttachment(
            texture: depthTexture,
            loadAction: depthLoadAction,
            clearDepth: clearDepth
        )
        descriptor.setDepthAttachment(depthAttachment)
        
        return descriptor
    }
}