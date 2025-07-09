import Metal
import Foundation
import CryptoKit
import os.log
import QuartzCore

public enum TexturePoolError: Error, LocalizedError {
    case invalidDescriptor
    case poolExhausted
    case incompatibleFormat
    case textureCreationFailed
    case allocationFailed
    
    public var errorDescription: String? {
        switch self {
        case .invalidDescriptor:
            return "Invalid texture descriptor"
        case .poolExhausted:
            return "Texture pool is exhausted"
        case .incompatibleFormat:
            return "Incompatible texture format"
        case .textureCreationFailed:
            return "Failed to create texture"
        case .allocationFailed:
            return "Failed to allocate texture memory"
        }
    }
}

public struct TextureDescriptorKey: Hashable {
    public let width: Int
    public let height: Int
    public let depth: Int
    public let mipmapLevelCount: Int
    public let sampleCount: Int
    public let arrayLength: Int
    public let pixelFormat: MTLPixelFormat
    public let textureType: MTLTextureType
    public let usageRawValue: UInt
    public let storageMode: MTLStorageMode
    public let allowGPUOptimizedContents: Bool
    
    public init(_ descriptor: MTLTextureDescriptor) {
        self.width = descriptor.width
        self.height = descriptor.height
        self.depth = descriptor.depth
        self.mipmapLevelCount = descriptor.mipmapLevelCount
        self.sampleCount = descriptor.sampleCount
        self.arrayLength = descriptor.arrayLength
        self.pixelFormat = descriptor.pixelFormat
        self.textureType = descriptor.textureType
        self.usageRawValue = descriptor.usage.rawValue
        self.storageMode = descriptor.storageMode
        self.allowGPUOptimizedContents = descriptor.allowGPUOptimizedContents
    }
    
    public var memorySize: Int {
        let bytesPerPixel = pixelFormat.bytesPerPixel
        let pixelCount = width * height * depth * arrayLength
        let mipLevels = mipmapLevelCount > 1 ? Int(Double(mipmapLevelCount) * 1.33) : 1 // Account for mip chain
        return pixelCount * bytesPerPixel * mipLevels * sampleCount
    }
    
    public var cacheKey: String {
        return "\(width)x\(height)x\(depth)_\(pixelFormat.rawValue)_\(textureType.rawValue)_\(usageRawValue)_\(storageMode.rawValue)_\(mipmapLevelCount)_\(sampleCount)_\(arrayLength)"
    }
}

public struct PooledTexture {
    public let texture: MTLTexture
    public let key: TextureDescriptorKey
    public let creationTime: Date
    public var lastAccessTime: Date
    public var accessCount: Int
    public let isFromPool: Bool
    public let poolPriority: TexturePriority
    
    public init(
        texture: MTLTexture,
        key: TextureDescriptorKey,
        isFromPool: Bool = true,
        priority: TexturePriority = .normal
    ) {
        self.texture = texture
        self.key = key
        self.creationTime = Date()
        self.lastAccessTime = Date()
        self.accessCount = 1
        self.isFromPool = isFromPool
        self.poolPriority = priority
    }
    
    public var ageInSeconds: TimeInterval {
        return Date().timeIntervalSince(creationTime)
    }
    
    public var timeSinceLastAccess: TimeInterval {
        return Date().timeIntervalSince(lastAccessTime)
    }
    
    public mutating func recordAccess() {
        lastAccessTime = Date()
        accessCount += 1
    }
    
    public var evictionScore: Double {
        let timeFactor = timeSinceLastAccess / 3600.0 // Hours since last access
        let sizeFactor = Double(key.memorySize) / (1024.0 * 1024.0) // Size in MB
        let accessFactor = 1.0 / max(1.0, Double(accessCount))
        let priorityFactor = poolPriority.evictionWeight
        
        return timeFactor * sizeFactor * accessFactor * priorityFactor
    }
}

public enum TexturePriority: Int, CaseIterable {
    case critical = 0
    case high = 1
    case normal = 2
    case low = 3
    case disposable = 4
    
    public var evictionWeight: Double {
        switch self {
        case .critical: return 0.1
        case .high: return 0.3
        case .normal: return 1.0
        case .low: return 2.0
        case .disposable: return 5.0
        }
    }
    
    public var maxIdleTime: TimeInterval {
        switch self {
        case .critical: return 3600 // 1 hour
        case .high: return 1800 // 30 minutes
        case .normal: return 600 // 10 minutes
        case .low: return 300 // 5 minutes
        case .disposable: return 60 // 1 minute
        }
    }
}

public class TexturePool {
    private let device: MetalDevice
    private let resourceHeap: ResourceHeap?
    private let logger = Logger(subsystem: "com.metalx.engine", category: "TexturePool")
    
    private var availableTextures: [TextureDescriptorKey: [PooledTexture]] = [:]
    private var activeTextures: [ObjectIdentifier: PooledTexture] = [:]
    private var textureDescriptorCache: [String: MTLTextureDescriptor] = [:]
    
    private let accessQueue = DispatchQueue(label: "com.metalx.texturepool", attributes: .concurrent)
    private var currentMemoryPressure: MemoryPressure = .normal
    
    // Pool configuration
    private let maxPoolSize: Int = 1000
    private let maxTexturesPerDescriptor: Int = 10
    private let memoryPressureThreshold: Double = 0.8
    private let garbageCollectionInterval: TimeInterval = 30.0
    
    private var lastGarbageCollection: Date = Date()
    
    public var memoryUsage: Int {
        return 0 // Removed memory tracking
    }
    
    public var poolStatistics: TexturePoolStatistics {
        return accessQueue.sync {
            let availableCount = availableTextures.values.reduce(0) { $0 + $1.count }
            let activeCount = activeTextures.count
            
            return TexturePoolStatistics(
                availableTextures: availableCount,
                activeTextures: activeCount,
                totalMemoryUsage: 0,
                maxMemoryUsage: 0,
                memoryUtilization: 0,
                memoryPressure: currentMemoryPressure,
                uniqueDescriptors: availableTextures.count
            )
        }
    }
    
    public init(
        device: MetalDevice,
        maxMemoryUsage: Int? = nil,
        resourceHeap: ResourceHeap? = nil
    ) {
        self.device = device
        self.resourceHeap = resourceHeap
        
        // startGarbageCollectionTimer() // Disabled - causing crashes
        logger.info("Initialized texture pool")
    }
    
    public func acquireTexture(descriptor: MTLTextureDescriptor, priority: TexturePriority = .normal) throws -> MTLTexture {
        let key = TextureDescriptorKey(descriptor)
        
        // Try to get from pool first
        if let pooledTexture = getFromPool(key: key, priority: priority) {
            return pooledTexture.texture
        }
        
        // Create new texture
        return try createNewTexture(descriptor: descriptor, key: key, priority: priority)
    }
    
    public func returnTexture(_ texture: MTLTexture) {
        accessQueue.async(flags: .barrier) {
            let identifier = ObjectIdentifier(texture)
            
            guard var pooledTexture = self.activeTextures.removeValue(forKey: identifier) else {
                self.logger.warning("Attempted to return texture not from pool")
                return
            }
            
            // Update texture info
            pooledTexture.recordAccess()
            
            // Return to pool if there's space and it's worth keeping
            let key = pooledTexture.key
            if self.shouldReturnToPool(pooledTexture) {
                self.availableTextures[key, default: []].append(pooledTexture)
                
                // Limit textures per descriptor
                if self.availableTextures[key]!.count > self.maxTexturesPerDescriptor {
                    let excess = self.availableTextures[key]!.removeFirst()
                }
            } else {
            }
            
            self.updateMemoryPressure()
        }
    }
    
    public func setMemoryPressure(_ pressure: MemoryPressure) {
        accessQueue.async(flags: .barrier) {
            let oldPressure = self.currentMemoryPressure
            self.currentMemoryPressure = pressure
            
            if pressure.rawValue > oldPressure.rawValue {
                self.performMemoryPressureResponse(pressure)
            }
        }
    }
    
    public func preloadTextures(descriptors: [MTLTextureDescriptor], priority: TexturePriority = .low) {
        for descriptor in descriptors {
            Task {
                do {
                    let texture = try acquireTexture(descriptor: descriptor, priority: priority)
                    returnTexture(texture)
                } catch {
                    logger.error("Failed to preload texture: \(error.localizedDescription)")
                }
            }
        }
    }
    
    public func clearPool(priority: TexturePriority? = nil) {
        accessQueue.async(flags: .barrier) {
            if let targetPriority = priority {
                // Clear only textures with specific priority
                for (key, textures) in self.availableTextures {
                    let filteredTextures = textures.filter { $0.poolPriority != targetPriority }
                    let removedTextures = textures.filter { $0.poolPriority == targetPriority }
                    
                    self.availableTextures[key] = filteredTextures.isEmpty ? nil : filteredTextures
                    
                    let removedMemory = removedTextures.reduce(0) { $0 + $1.key.memorySize }
                }
            } else {
                // Clear entire pool
                self.availableTextures.removeAll()
                let activeMemory = self.activeTextures.values.reduce(0) { $0 + $1.key.memorySize }
            }
            
            self.updateMemoryPressure()
            self.logger.info("Cleared texture pool (priority: \(priority?.rawValue ?? -1))")
        }
    }
    
    public func performGarbageCollection() {
        accessQueue.async(flags: .barrier) {
            let startTime = CACurrentMediaTime()
            var removedCount = 0
            var reclaimedMemory = 0
            
            // Collect textures based on idle time and priority
            for (key, textures) in self.availableTextures {
                var keptTextures: [PooledTexture] = []
                
                for texture in textures {
                    if texture.timeSinceLastAccess > texture.poolPriority.maxIdleTime {
                        removedCount += 1
                        reclaimedMemory += texture.key.memorySize
                    } else {
                        keptTextures.append(texture)
                    }
                }
                
                if keptTextures.isEmpty {
                    self.availableTextures.removeValue(forKey: key)
                } else {
                    self.availableTextures[key] = keptTextures
                }
            }
            
            self.lastGarbageCollection = Date()
            self.updateMemoryPressure()
            
            let duration = CACurrentMediaTime() - startTime
            if removedCount > 0 {
                self.logger.info("Garbage collection: removed \(removedCount) textures, reclaimed \(reclaimedMemory / 1024 / 1024)MB in \(Int(duration * 1000))ms")
            }
        }
    }
    
    private func getFromPool(key: TextureDescriptorKey, priority: TexturePriority) -> PooledTexture? {
        return accessQueue.sync(flags: .barrier) {
            guard var textures = availableTextures[key], !textures.isEmpty else {
                return nil
            }
            
            var pooledTexture = textures.removeLast()
            if textures.isEmpty {
                availableTextures.removeValue(forKey: key)
            } else {
                availableTextures[key] = textures
            }
            
            pooledTexture.recordAccess()
            activeTextures[ObjectIdentifier(pooledTexture.texture)] = pooledTexture
            
            logger.debug("Acquired texture from pool: \(key.cacheKey)")
            return pooledTexture
        }
    }
    
    private func createNewTexture(descriptor: MTLTextureDescriptor, key: TextureDescriptorKey, priority: TexturePriority) throws -> MTLTexture {
        return try accessQueue.sync(flags: .barrier) {
            // Check memory budget
            
            let texture: MTLTexture
            
            if let heap = resourceHeap {
                // Try to allocate from heap
                texture = try heap.allocateTexture(descriptor: descriptor)
            } else {
                // Allocate directly from device
                guard let newTexture = device.makeTexture(descriptor: descriptor) else {
                    throw TexturePoolError.textureCreationFailed
                }
                texture = newTexture
            }
            
            let pooledTexture = PooledTexture(texture: texture, key: key, isFromPool: false, priority: priority)
            activeTextures[ObjectIdentifier(texture)] = pooledTexture
            
            updateMemoryPressure()
            
            logger.debug("Created new texture: \(key.cacheKey)")
            return texture
        }
    }
    
    private func shouldReturnToPool(_ pooledTexture: PooledTexture) -> Bool {
        // Don't return to pool if memory pressure is high
        if currentMemoryPressure.rawValue >= MemoryPressure.urgent.rawValue {
            return false
        }
        
        // Don't return disposable textures
        if pooledTexture.poolPriority == .disposable {
            return false
        }
        
        // Check if pool is full for this descriptor
        let currentCount = availableTextures[pooledTexture.key]?.count ?? 0
        if currentCount >= maxTexturesPerDescriptor {
            return false
        }
        
        return true
    }
    
    private func performEmergencyEviction(requiredMemory: Int) throws {
        var freedMemory = 0
        var evictedCount = 0
        
        // First, try to evict from available pool
        var allAvailableTextures: [(TextureDescriptorKey, PooledTexture)] = []
        for (key, textures) in availableTextures {
            for texture in textures {
                allAvailableTextures.append((key, texture))
            }
        }
        
        // Sort by eviction score (highest first)
        allAvailableTextures.sort { $0.1.evictionScore > $1.1.evictionScore }
        
        for (key, texture) in allAvailableTextures {
            if freedMemory >= requiredMemory { break }
            
            if var textures = availableTextures[key] {
                if let index = textures.firstIndex(where: { ObjectIdentifier($0.texture) == ObjectIdentifier(texture.texture) }) {
                    let removed = textures.remove(at: index)
                    freedMemory += removed.key.memorySize
                    evictedCount += 1
                    
                    if textures.isEmpty {
                        availableTextures.removeValue(forKey: key)
                    } else {
                        availableTextures[key] = textures
                    }
                }
            }
        }
        
        
        if freedMemory < requiredMemory {
            throw TexturePoolError.poolExhausted
        }
        
        if evictedCount > 0 {
            logger.warning("Emergency eviction: freed \(freedMemory / 1024 / 1024)MB by evicting \(evictedCount) textures")
        }
    }
    
    private func performMemoryPressureResponse(_ pressure: MemoryPressure) {
        
        if false { // Disabled memory-based eviction
            let memoryToFree = 0
            
            do {
                try performEmergencyEviction(requiredMemory: memoryToFree)
                logger.info("Responded to memory pressure: freed \(memoryToFree / 1024 / 1024)MB")
            } catch {
                logger.error("Failed to respond to memory pressure: \(error.localizedDescription)")
            }
        }
    }
    
    private func updateMemoryPressure() {
        let utilization = 0.0
        
        let newPressure: MemoryPressure
        if utilization > 0.95 {
            newPressure = .critical
        } else if utilization > 0.85 {
            newPressure = .urgent
        } else if utilization > 0.7 {
            newPressure = .warning
        } else {
            newPressure = .normal
        }
        
        if newPressure != currentMemoryPressure {
            currentMemoryPressure = newPressure
            logger.debug("Memory pressure updated: \(String(describing: newPressure)) (utilization: \(String(format: "%.1f", utilization * 100))%)")
        }
    }
    
    private func startGarbageCollectionTimer() {
        Timer.scheduledTimer(withTimeInterval: garbageCollectionInterval, repeats: true) { [weak self] _ in
            self?.performGarbageCollection()
        }
    }
    
    public func performMaintenance() {
        performGarbageCollection()
    }
}

public struct TexturePoolStatistics {
    public let availableTextures: Int
    public let activeTextures: Int
    public let totalMemoryUsage: Int
    public let maxMemoryUsage: Int
    public let memoryUtilization: Double
    public let memoryPressure: MemoryPressure
    public let uniqueDescriptors: Int
    
    public var memoryUsageMB: Double {
        return Double(totalMemoryUsage) / (1024 * 1024)
    }
    
    public var maxMemoryUsageMB: Double {
        return Double(maxMemoryUsage) / (1024 * 1024)
    }
    
    public var isHealthy: Bool {
        return memoryPressure.rawValue <= MemoryPressure.warning.rawValue && memoryUtilization < 0.8
    }
}

extension TexturePool {
    public func printStatistics() {
        let stats = poolStatistics
        logger.info("""
        Texture Pool Statistics:
          Available Textures: \(stats.availableTextures)
          Active Textures: \(stats.activeTextures)
          Unique Descriptors: \(stats.uniqueDescriptors)
          Memory Usage: \(String(format: "%.1f", stats.memoryUsageMB)) / \(String(format: "%.1f", stats.maxMemoryUsageMB)) MB (\(String(format: "%.1f", stats.memoryUtilization * 100))%)
          Memory Pressure: \(String(describing: stats.memoryPressure))
          Health: \(stats.isHealthy ? "Good" : "Poor")
        """)
    }
}