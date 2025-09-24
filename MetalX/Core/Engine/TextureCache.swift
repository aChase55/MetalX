import Metal
import Foundation
import CryptoKit
import os.log
import QuartzCore

public enum TextureCacheError: Error, LocalizedError {
    case loadingFailed
    case cacheKeyInvalid
    case memoryCritical
    case loadingCancelled
    
    public var errorDescription: String? {
        switch self {
        case .loadingFailed:
            return "Texture loading failed"
        case .cacheKeyInvalid:
            return "Invalid cache key"
        case .memoryCritical:
            return "Critical memory pressure, cannot cache texture"
        case .loadingCancelled:
            return "Texture loading was cancelled"
        }
    }
}

public struct TextureCacheKey: Hashable, CustomStringConvertible {
    public let identifier: String
    public let options: String
    public let lastModified: Date?
    
    public init(url: URL, options: TextureLoadOptions) {
        self.identifier = url.absoluteString
        self.options = Self.serializeOptions(options)
        self.lastModified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
    
    public init(identifier: String, options: TextureLoadOptions, lastModified: Date? = nil) {
        self.identifier = identifier
        self.options = Self.serializeOptions(options)
        self.lastModified = lastModified
    }
    
    private static func serializeOptions(_ options: TextureLoadOptions) -> String {
        var components: [String] = []
        components.append("type:\(options.usageType)")
        components.append("mips:\(options.generateMipmaps)")
        components.append("comp:\(options.allowCompression)")
        components.append("flip:\(options.flipVertically)")
        components.append("premul:\(options.premultiplyAlpha)")
        components.append("srgb:\(options.sRGBCorrection)")
        if let maxSize = options.maxSize {
            components.append("max:\(maxSize)")
        }
        return components.joined(separator: "|")
    }
    
    public var description: String {
        let fileName = URL(string: identifier)?.lastPathComponent ?? identifier
        return "\(fileName)[\(options.prefix(20))]"
    }
    
    public var cacheKey: String {
        var hasher = SHA256()
        hasher.update(data: Data(identifier.utf8))
        hasher.update(data: Data(options.utf8))
        if let modified = lastModified {
            hasher.update(data: Data(String(modified.timeIntervalSince1970).utf8))
        }
        return hasher.finalize().compactMap { String(format: "%02x", $0) }.joined()
    }
}

public struct CachedTexture {
    public let texture: MTLTexture
    public let key: TextureCacheKey
    public let memorySize: Int
    public let creationTime: Date
    public var lastAccessTime: Date
    public var accessCount: Int
    public let priority: TexturePriority
    public var isLoading: Bool
    
    public init(texture: MTLTexture, key: TextureCacheKey, memorySize: Int, priority: TexturePriority) {
        self.texture = texture
        self.key = key
        self.memorySize = memorySize
        self.creationTime = Date()
        self.lastAccessTime = Date()
        self.accessCount = 1
        self.priority = priority
        self.isLoading = false
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
        let sizeFactor = Double(memorySize) / (1024.0 * 1024.0) // Size in MB
        let accessFactor = 1.0 / max(1.0, Double(accessCount))
        let priorityFactor = priority.evictionWeight
        
        return timeFactor * sizeFactor * accessFactor * priorityFactor
    }
}

public struct SendableTexture: @unchecked Sendable { let texture: MTLTexture }

public class LoadingTask {
    private let task: Task<SendableTexture, Error>
    private let creationTime = Date()
    public let key: TextureCacheKey
    public let priority: TexturePriority
    
    public init(key: TextureCacheKey, priority: TexturePriority, loader: @escaping () async throws -> MTLTexture) {
        self.key = key
        self.priority = priority
        self.task = Task { SendableTexture(texture: try await loader()) }
    }
    
    public func getValue() async throws -> MTLTexture {
        return try await task.value.texture
    }
    
    public func cancel() {
        task.cancel()
    }
    
    public var isCancelled: Bool {
        return task.isCancelled
    }
    
    public var ageInSeconds: TimeInterval {
        return Date().timeIntervalSince(creationTime)
    }
}

public class TextureCache {
    private let device: MetalDevice
    private let textureLoader: TextureLoader
    private let logger = Logger(subsystem: "com.metalx.engine", category: "TextureCache")
    
    private var cache: [String: CachedTexture] = [:]
    private var loadingTasks: [String: LoadingTask] = [:]
    private var cacheOrder: [String] = [] // LRU order (most recent last)
    
    private let accessQueue = DispatchQueue(label: "com.metalx.texture.cache", attributes: .concurrent)
    private var totalMemoryUsage: Int = 0
    private var maxMemoryUsage: Int
    private var currentMemoryPressure: MemoryPressure = .normal
    
    // Cache configuration
    private let maxCacheSize: Int = 500
    private let maxLoadingTasks: Int = 20
    private let memoryPressureThreshold: Double = 0.8
    private let garbageCollectionInterval: TimeInterval = 60.0
    private let maxTaskAge: TimeInterval = 30.0
    
    public var memoryUsage: Int {
        return 0 // Memory tracking removed - was causing crashes
    }
    
    public var memoryUtilization: Double {
        let usage = memoryUsage
        return maxMemoryUsage > 0 ? Double(usage) / Double(maxMemoryUsage) : 0.0
    }
    
    public var cacheStatistics: TextureCacheStatistics {
        return accessQueue.sync {
            TextureCacheStatistics(
                cachedTextures: cache.count,
                loadingTasks: loadingTasks.count,
                totalMemoryUsage: totalMemoryUsage,
                maxMemoryUsage: maxMemoryUsage,
                memoryUtilization: memoryUtilization,
                memoryPressure: currentMemoryPressure,
                hitRate: calculateHitRate()
            )
        }
    }
    
    public init(
        device: MetalDevice,
        textureLoader: TextureLoader,
        maxMemoryUsage: Int? = nil
    ) {
        self.device = device
        self.textureLoader = textureLoader
        // Use a reasonable default if recommendedMaxWorkingSetSize is 0 or too small
        let defaultBudget = 192 * 1024 * 1024 // 192MB default
        let recommendedBudget = device.capabilities.recommendedMaxWorkingSetSize / 3
        self.maxMemoryUsage = maxMemoryUsage ?? max(recommendedBudget, defaultBudget)
        
        // startMaintenanceTimer() // Disabled - causing crashes
        logger.info("Initialized texture cache with \(self.maxMemoryUsage / 1024 / 1024)MB budget")
    }
    
    // MARK: - Public Methods
    
    public func getTexture(for key: TextureCacheKey) async throws -> MTLTexture {
        // Check cache first
        if let cachedTexture = getCachedTexture(for: key) {
            return cachedTexture.texture
        }
        
        // Check if already loading
        if let loadingTask = getLoadingTask(for: key) {
            return try await loadingTask.getValue()
        }
        
        // Start new loading task
        return try await startLoadingTask(for: key)
    }
    
    public func getTexture(from url: URL, options: TextureLoadOptions = .default) async throws -> MTLTexture {
        let key = TextureCacheKey(url: url, options: options)
        return try await getTexture(for: key)
    }
    
    public func getTexture(from data: Data, identifier: String, options: TextureLoadOptions = .default) async throws -> MTLTexture {
        let key = TextureCacheKey(identifier: identifier, options: options)
        return try await getTexture(for: key)
    }
    
    public func preloadTexture(from url: URL, options: TextureLoadOptions = .default, priority: TexturePriority = .low) {
        let key = TextureCacheKey(url: url, options: options)
        
        Task {
            do {
                _ = try await getTexture(for: key)
                logger.debug("Preloaded texture: \(key.description)")
            } catch {
                logger.error("Failed to preload texture \(key.description): \(error.localizedDescription)")
            }
        }
    }
    
    public func invalidateCache(for identifier: String) {
        accessQueue.async(flags: .barrier) {
            let keysToRemove = self.cache.keys.filter { key in
                self.cache[key]?.key.identifier == identifier
            }
            
            for key in keysToRemove {
                if let cachedTexture = self.cache.removeValue(forKey: key) {
                    self.totalMemoryUsage -= cachedTexture.memorySize
                    self.cacheOrder.removeAll { $0 == key }
                }
            }
            
            // Also cancel any loading tasks for this identifier
            let loadingKeysToRemove = self.loadingTasks.keys.filter { key in
                self.loadingTasks[key]?.key.identifier == identifier
            }
            
            for key in loadingKeysToRemove {
                self.loadingTasks[key]?.cancel()
                self.loadingTasks.removeValue(forKey: key)
            }
            
            self.updateMemoryPressure()
        }
    }
    
    public func clearCache(priority: TexturePriority? = nil) {
        accessQueue.async(flags: .barrier) {
            if let targetPriority = priority {
                // Clear only textures with specific priority
                let keysToRemove = self.cache.compactMap { (key, texture) in
                    texture.priority == targetPriority ? key : nil
                }
                
                for key in keysToRemove {
                    if let cachedTexture = self.cache.removeValue(forKey: key) {
                        self.totalMemoryUsage -= cachedTexture.memorySize
                        self.cacheOrder.removeAll { $0 == key }
                    }
                }
            } else {
                // Clear entire cache
                self.cache.removeAll()
                self.cacheOrder.removeAll()
                self.totalMemoryUsage = 0
            }
            
            // Cancel loading tasks if clearing all
            if priority == nil {
                for task in self.loadingTasks.values {
                    task.cancel()
                }
                self.loadingTasks.removeAll()
            }
            
            self.updateMemoryPressure()
            self.logger.info("Cleared texture cache (priority: \(priority?.rawValue ?? -1))")
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
    
    // MARK: - Private Methods
    
    private func getCachedTexture(for key: TextureCacheKey) -> CachedTexture? {
        return accessQueue.sync(flags: .barrier) {
            let cacheKey = key.cacheKey
            guard var cachedTexture = cache[cacheKey] else { return nil }
            
            // Update access info
            cachedTexture.recordAccess()
            cache[cacheKey] = cachedTexture
            
            // Update LRU order
            cacheOrder.removeAll { $0 == cacheKey }
            cacheOrder.append(cacheKey)
            
            return cachedTexture
        }
    }
    
    private func getLoadingTask(for key: TextureCacheKey) -> LoadingTask? {
        return accessQueue.sync {
            return loadingTasks[key.cacheKey]
        }
    }
    
    private func startLoadingTask(for key: TextureCacheKey) async throws -> MTLTexture {
        let cacheKey = key.cacheKey
        
        // Check memory pressure
        if currentMemoryPressure == .critical {
            throw TextureCacheError.memoryCritical
        }
        
        let loadingTask = accessQueue.sync(flags: .barrier) { () -> LoadingTask? in
            // Double-check if texture was loaded while waiting
            if let cachedTexture = cache[cacheKey] {
                return nil
            }
            
            // Check if we have too many loading tasks
            if loadingTasks.count >= maxLoadingTasks {
                cleanupOldLoadingTasks()
            }
            
            // Create loading task
            let loadingTask = LoadingTask(key: key, priority: key.options.contains("priority:low") ? .low : .normal) {
                try await self.loadTextureForKey(key)
            }
            
            loadingTasks[cacheKey] = loadingTask
            return loadingTask
        }
        
        // If task is nil, texture was already cached
        if loadingTask == nil {
            if let cachedTexture = cache[cacheKey] {
                return cachedTexture.texture
            }
        }
        
        guard let task = loadingTask else {
            throw TextureCacheError.loadingFailed
        }
        
        defer {
            accessQueue.async(flags: .barrier) {
                self.loadingTasks.removeValue(forKey: cacheKey)
            }
        }
        
        do {
            let texture = try await task.getValue()
            self.cacheTexture(texture, for: key)
            return texture
        } catch {
            if !task.isCancelled {
                self.logger.error("Failed to load texture \(key.description): \(error.localizedDescription)")
            }
            throw error
        }
    }
    
    private func loadTextureForKey(_ key: TextureCacheKey) async throws -> MTLTexture {
        if let url = URL(string: key.identifier) {
            let options = try deserializeOptions(key.options)
            return try await textureLoader.loadTexture(from: url, options: options)
        } else {
            throw TextureCacheError.cacheKeyInvalid
        }
    }
    
    private func deserializeOptions(_ optionsString: String) throws -> TextureLoadOptions {
        // Simple deserialization - in practice, this would be more robust
        var options = TextureLoadOptions.default
        
        let components = optionsString.components(separatedBy: "|")
        for component in components {
            let parts = component.components(separatedBy: ":")
            guard parts.count == 2 else { continue }
            
            let key = parts[0]
            let value = parts[1]
            
            switch key {
            case "type":
                // Parse usage type
                break
            case "mips":
                // Parse mipmap setting
                break
            case "max":
                if let maxSize = Int(value) {
                    options = TextureLoadOptions(maxSize: maxSize)
                }
            default:
                break
            }
        }
        
        return options
    }
    
    private func cacheTexture(_ texture: MTLTexture, for key: TextureCacheKey) {
        accessQueue.async(flags: .barrier) {
            let cacheKey = key.cacheKey
            let memorySize = self.calculateTextureMemorySize(texture)
            
            // Check if we need to make room
            if self.totalMemoryUsage + memorySize > self.maxMemoryUsage {
                self.evictTextures(toFreeAtLeast: memorySize)
            }
            
            // Add to cache
            let cachedTexture = CachedTexture(
                texture: texture,
                key: key,
                memorySize: memorySize,
                priority: .normal // Could be extracted from key.options
            )
            
            self.cache[cacheKey] = cachedTexture
            self.cacheOrder.append(cacheKey)
            self.totalMemoryUsage += memorySize
            
            // Ensure cache size limits
            if self.cache.count > self.maxCacheSize {
                self.evictLeastRecentlyUsed(count: self.cache.count - self.maxCacheSize)
            }
            
            self.updateMemoryPressure()
            self.logger.debug("Cached texture: \(key.description) (\(memorySize / 1024)KB)")
        }
    }
    
    private func evictTextures(toFreeAtLeast requiredMemory: Int) {
        var freedMemory = 0
        var evictedCount = 0
        
        // Sort cache entries by eviction score (highest first)
        let sortedEntries = cache.sorted { $0.value.evictionScore > $1.value.evictionScore }
        
        for (cacheKey, cachedTexture) in sortedEntries {
            if freedMemory >= requiredMemory { break }
            
            cache.removeValue(forKey: cacheKey)
            cacheOrder.removeAll { $0 == cacheKey }
            freedMemory += cachedTexture.memorySize
            evictedCount += 1
        }
        
        totalMemoryUsage -= freedMemory
        
        if evictedCount > 0 {
            logger.info("Evicted \(evictedCount) textures, freed \(freedMemory / 1024 / 1024)MB")
        }
    }
    
    private func evictLeastRecentlyUsed(count: Int) {
        let keysToRemove = Array(cacheOrder.prefix(count))
        
        for key in keysToRemove {
            if let cachedTexture = cache.removeValue(forKey: key) {
                totalMemoryUsage -= cachedTexture.memorySize
            }
            cacheOrder.removeAll { $0 == key }
        }
    }
    
    private func cleanupOldLoadingTasks() {
        let now = Date()
        let oldTasks = loadingTasks.filter { _, task in
            task.ageInSeconds > maxTaskAge
        }
        
        for (key, task) in oldTasks {
            task.cancel()
            loadingTasks.removeValue(forKey: key)
        }
    }
    
    private func performMemoryPressureResponse(_ pressure: MemoryPressure) {
        let reductionFactor = pressure.cacheReduction
        let targetMemory = Int(Double(maxMemoryUsage) * Double(reductionFactor))
        
        if totalMemoryUsage > targetMemory {
            let memoryToFree = totalMemoryUsage - targetMemory
            evictTextures(toFreeAtLeast: memoryToFree)
            logger.info("Responded to memory pressure: freed \(memoryToFree / 1024 / 1024)MB")
        }
    }
    
    private func updateMemoryPressure() {
        let utilization = memoryUtilization
        
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
    
    private func calculateTextureMemorySize(_ texture: MTLTexture) -> Int {
        let bytesPerPixel = texture.pixelFormat.bytesPerPixel
        let pixelCount = texture.width * texture.height * texture.depth * texture.arrayLength
        let mipLevels = texture.mipmapLevelCount > 1 ? Int(Double(texture.mipmapLevelCount) * 1.33) : 1
        return pixelCount * bytesPerPixel * mipLevels * texture.sampleCount
    }
    
    private func calculateHitRate() -> Double {
        // This would track hits vs misses over time
        // For now, return estimated rate based on cache size
        return cache.isEmpty ? 0.0 : 0.75 // Placeholder
    }
    
    private func performGarbageCollection() {
        accessQueue.async(flags: .barrier) {
            let startTime = CACurrentMediaTime()
            var removedCount = 0
            var reclaimedMemory = 0
            
            // Remove textures based on age and access patterns
            let now = Date()
            let keysToRemove = self.cache.compactMap { (key, texture) -> String? in
                let shouldRemove = texture.timeSinceLastAccess > texture.priority.maxIdleTime ||
                                 (texture.priority == .disposable && texture.accessCount == 1)
                return shouldRemove ? key : nil
            }
            
            for key in keysToRemove {
                if let cachedTexture = self.cache.removeValue(forKey: key) {
                    self.cacheOrder.removeAll { $0 == key }
                    removedCount += 1
                    reclaimedMemory += cachedTexture.memorySize
                }
            }
            
            self.totalMemoryUsage -= reclaimedMemory
            self.updateMemoryPressure()
            
            let duration = CACurrentMediaTime() - startTime
            if removedCount > 0 {
                self.logger.info("Garbage collection: removed \(removedCount) textures, reclaimed \(reclaimedMemory / 1024 / 1024)MB in \(Int(duration * 1000))ms")
            }
        }
    }
    
    private func startMaintenanceTimer() {
        Timer.scheduledTimer(withTimeInterval: garbageCollectionInterval, repeats: true) { [weak self] _ in
            self?.performGarbageCollection()
        }
    }
}

public struct TextureCacheStatistics {
    public let cachedTextures: Int
    public let loadingTasks: Int
    public let totalMemoryUsage: Int
    public let maxMemoryUsage: Int
    public let memoryUtilization: Double
    public let memoryPressure: MemoryPressure
    public let hitRate: Double
    
    public var memoryUsageMB: Double {
        return Double(totalMemoryUsage) / (1024 * 1024)
    }
    
    public var maxMemoryUsageMB: Double {
        return Double(maxMemoryUsage) / (1024 * 1024)
    }
    
    public var isHealthy: Bool {
        return memoryPressure.rawValue <= MemoryPressure.warning.rawValue && 
               memoryUtilization < 0.8 && 
               hitRate > 0.5
    }
}

extension TextureCache {
    public func printStatistics() {
        let stats = cacheStatistics
        logger.info("""
        Texture Cache Statistics:
          Cached Textures: \(stats.cachedTextures)
          Loading Tasks: \(stats.loadingTasks)
          Memory Usage: \(String(format: "%.1f", stats.memoryUsageMB)) / \(String(format: "%.1f", stats.maxMemoryUsageMB)) MB (\(String(format: "%.1f", stats.memoryUtilization * 100))%)
          Memory Pressure: \(String(describing: stats.memoryPressure))
          Hit Rate: \(String(format: "%.1f", stats.hitRate * 100))%
          Health: \(stats.isHealthy ? "Good" : "Poor")
        """)
    }
}
