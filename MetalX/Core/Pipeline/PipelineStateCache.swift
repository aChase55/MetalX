import Metal
import Foundation
import CryptoKit
import QuartzCore
import os.log

public enum PipelineError: Error, LocalizedError {
    case shaderNotFound(String)
    case compilationFailed(String, Error)
    case invalidDescriptor
    case deviceUnsupported
    case asyncCompilationFailed
    
    public var errorDescription: String? {
        switch self {
        case .shaderNotFound(let name):
            return "Shader not found: \(name)"
        case .compilationFailed(let name, let error):
            return "Pipeline compilation failed for \(name): \(error.localizedDescription)"
        case .invalidDescriptor:
            return "Invalid pipeline descriptor"
        case .deviceUnsupported:
            return "Pipeline not supported on this device"
        case .asyncCompilationFailed:
            return "Asynchronous pipeline compilation failed"
        }
    }
}

public struct PipelineCacheKey: Hashable, CustomStringConvertible {
    public let hash: String
    public let vertexFunction: String?
    public let fragmentFunction: String?
    public let computeFunction: String?
    public let colorAttachmentCount: Int
    public let depthAttachmentFormat: MTLPixelFormat?
    public let stencilAttachmentFormat: MTLPixelFormat?
    public let sampleCount: Int
    
    public var description: String {
        if let compute = computeFunction {
            return "compute:\(compute)[\(hash.prefix(8))]"
        } else {
            return "render:\(vertexFunction ?? "nil")+\(fragmentFunction ?? "nil")[\(hash.prefix(8))]"
        }
    }
    
    public static func == (lhs: PipelineCacheKey, rhs: PipelineCacheKey) -> Bool {
        return lhs.hash == rhs.hash
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(hash)
    }
}

public struct PipelineCacheEntry {
    public let key: PipelineCacheKey
    public let renderPipelineState: MTLRenderPipelineState?
    public let computePipelineState: MTLComputePipelineState?
    public let creationDate: Date
    public var lastAccessDate: Date
    public var accessCount: Int
    
    public init(
        key: PipelineCacheKey,
        renderPipelineState: MTLRenderPipelineState? = nil,
        computePipelineState: MTLComputePipelineState? = nil
    ) {
        self.key = key
        self.renderPipelineState = renderPipelineState
        self.computePipelineState = computePipelineState
        self.creationDate = Date()
        self.lastAccessDate = Date()
        self.accessCount = 1
    }
    
    public mutating func recordAccess() {
        lastAccessDate = Date()
        accessCount += 1
    }
    
    public var isRenderPipeline: Bool {
        return renderPipelineState != nil
    }
    
    public var isComputePipeline: Bool {
        return computePipelineState != nil
    }
    
    public var ageInSeconds: TimeInterval {
        return Date().timeIntervalSince(creationDate)
    }
    
    public var accessFrequency: Double {
        return Double(accessCount) / ageInSeconds
    }
}

public class PipelineStateCache {
    private let device: MetalDevice
    private let shaderLibrary: ShaderLibrary
    private let logger = Logger(subsystem: "com.metalx.engine", category: "PipelineCache")
    
    private var renderPipelineCache: [PipelineCacheKey: PipelineCacheEntry] = [:]
    private var computePipelineCache: [PipelineCacheKey: PipelineCacheEntry] = [:]
    private var pendingCompilations: [PipelineCacheKey: Task<Void, Error>] = [:]
    
    private let accessQueue = DispatchQueue(label: "com.metalx.pipeline.cache", attributes: .concurrent)
    private let compilationQueue = DispatchQueue(label: "com.metalx.pipeline.compilation", qos: .userInitiated)
    
    private let maxCacheSize: Int
    private let maxPendingCompilations: Int
    private let enableAsyncCompilation: Bool
    
    public var cacheStatistics: CacheStatistics {
        return accessQueue.sync {
            let totalEntries = renderPipelineCache.count + computePipelineCache.count
            let renderHits = renderPipelineCache.values.reduce(0) { $0 + $1.accessCount }
            let computeHits = computePipelineCache.values.reduce(0) { $0 + $1.accessCount }
            
            return CacheStatistics(
                totalEntries: totalEntries,
                renderPipelineCount: renderPipelineCache.count,
                computePipelineCount: computePipelineCache.count,
                pendingCompilations: pendingCompilations.count,
                totalHits: renderHits + computeHits,
                memoryUsageBytes: estimatedMemoryUsage()
            )
        }
    }
    
    public init(
        device: MetalDevice,
        maxCacheSize: Int = 512,
        maxPendingCompilations: Int = 16,
        enableAsyncCompilation: Bool = true
    ) {
        self.device = device
        self.shaderLibrary = ShaderLibrary(device: device)
        self.maxCacheSize = maxCacheSize
        self.maxPendingCompilations = maxPendingCompilations
        self.enableAsyncCompilation = enableAsyncCompilation
    }
    
    deinit {
        cancelAllPendingCompilations()
    }
    
    public func getRenderPipelineState(
        descriptor: MTLRenderPipelineDescriptor
    ) async throws -> MTLRenderPipelineState {
        let key = try createCacheKey(for: descriptor)
        
        if let entry = getCachedRenderPipelineEntry(for: key) {
            return entry.renderPipelineState!
        }
        
        if enableAsyncCompilation, let task = pendingCompilations[key] {
            try await task.value
            if let entry = getCachedRenderPipelineEntry(for: key) {
                return entry.renderPipelineState!
            }
        }
        
        return try await compileRenderPipelineState(descriptor: descriptor, key: key)
    }
    
    public func getRenderPipelineState(
        vertex: String,
        fragment: String
    ) async throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try shaderLibrary.getFunction(name: vertex)
        descriptor.fragmentFunction = try shaderLibrary.getFunction(name: fragment)
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        return try await getRenderPipelineState(descriptor: descriptor)
    }
    
    public func getComputePipelineState(
        function: String
    ) async throws -> MTLComputePipelineState {
        let mtlFunction = try shaderLibrary.getFunction(name: function)
        return try await getComputePipelineState(function: mtlFunction)
    }
    
    public func getComputePipelineState(
        function: MTLFunction
    ) async throws -> MTLComputePipelineState {
        let key = try createCacheKey(for: function)
        
        if let entry = getCachedComputePipelineEntry(for: key) {
            return entry.computePipelineState!
        }
        
        if enableAsyncCompilation, let task = pendingCompilations[key] {
            try await task.value
            if let entry = getCachedComputePipelineEntry(for: key) {
                return entry.computePipelineState!
            }
        }
        
        return try await compileComputePipelineState(function: function, key: key)
    }
    
    public func precompileRenderPipeline(
        descriptor: MTLRenderPipelineDescriptor
    ) {
        guard enableAsyncCompilation else { return }
        
        do {
            let key = try createCacheKey(for: descriptor)
            
            if renderPipelineCache[key] != nil || pendingCompilations[key] != nil {
                return
            }
            
            startAsyncCompilation(key: key) {
                try await self.compileRenderPipelineState(descriptor: descriptor, key: key)
            }
        } catch {
            logger.error("Failed to start precompilation: \(error.localizedDescription)")
        }
    }
    
    public func precompileComputePipeline(
        function: MTLFunction
    ) {
        guard enableAsyncCompilation else { return }
        
        do {
            let key = try createCacheKey(for: function)
            
            if computePipelineCache[key] != nil || pendingCompilations[key] != nil {
                return
            }
            
            startAsyncCompilation(key: key) {
                try await self.compileComputePipelineState(function: function, key: key)
            }
        } catch {
            logger.error("Failed to start precompilation: \(error.localizedDescription)")
        }
    }
    
    public func clearCache() {
        accessQueue.async(flags: .barrier) {
            self.renderPipelineCache.removeAll()
            self.computePipelineCache.removeAll()
            self.cancelAllPendingCompilations()
        }
        logger.info("Pipeline cache cleared")
    }
    
    public func evictLeastRecentlyUsed() {
        accessQueue.async(flags: .barrier) {
            self.performLRUEviction()
        }
    }
    
    public func performMaintenance() {
        accessQueue.async(flags: .barrier) {
            self.performLRUEviction()
        }
    }
    
    private func getCachedRenderPipelineEntry(for key: PipelineCacheKey) -> PipelineCacheEntry? {
        return accessQueue.sync {
            guard var entry = renderPipelineCache[key] else { return nil }
            entry.recordAccess()
            renderPipelineCache[key] = entry
            return entry
        }
    }
    
    private func getCachedComputePipelineEntry(for key: PipelineCacheKey) -> PipelineCacheEntry? {
        return accessQueue.sync {
            guard var entry = computePipelineCache[key] else { return nil }
            entry.recordAccess()
            computePipelineCache[key] = entry
            return entry
        }
    }
    
    private func compileRenderPipelineState(
        descriptor: MTLRenderPipelineDescriptor,
        key: PipelineCacheKey
    ) async throws -> MTLRenderPipelineState {
        let startTime = CACurrentMediaTime()
        
        let pipelineState = try await withCheckedThrowingContinuation { continuation in
            device.device.makeRenderPipelineState(descriptor: descriptor) { state, error in
                if let state = state {
                    continuation.resume(returning: state)
                } else if let error = error {
                    continuation.resume(throwing: PipelineError.compilationFailed(key.description, error))
                } else {
                    continuation.resume(throwing: PipelineError.asyncCompilationFailed)
                }
            }
        }
        
        let compilationTime = CACurrentMediaTime() - startTime
        logger.info("Compiled render pipeline \(key.description) in \(Int(compilationTime * 1000))ms")
        
        let entry = PipelineCacheEntry(key: key, renderPipelineState: pipelineState)
        
        accessQueue.async(flags: .barrier) {
            self.renderPipelineCache[key] = entry
            self.pendingCompilations.removeValue(forKey: key)
            self.performCacheMaintenance()
        }
        
        return pipelineState
    }
    
    private func compileComputePipelineState(
        function: MTLFunction,
        key: PipelineCacheKey
    ) async throws -> MTLComputePipelineState {
        let startTime = CACurrentMediaTime()
        
        let pipelineState = try await withCheckedThrowingContinuation { continuation in
            device.device.makeComputePipelineState(function: function) { state, error in
                if let state = state {
                    continuation.resume(returning: state)
                } else if let error = error {
                    continuation.resume(throwing: PipelineError.compilationFailed(key.description, error))
                } else {
                    continuation.resume(throwing: PipelineError.asyncCompilationFailed)
                }
            }
        }
        
        let compilationTime = CACurrentMediaTime() - startTime
        logger.info("Compiled compute pipeline \(key.description) in \(Int(compilationTime * 1000))ms")
        
        let entry = PipelineCacheEntry(key: key, computePipelineState: pipelineState)
        
        accessQueue.async(flags: .barrier) {
            self.computePipelineCache[key] = entry
            self.pendingCompilations.removeValue(forKey: key)
            self.performCacheMaintenance()
        }
        
        return pipelineState
    }
    
    private func startAsyncCompilation(key: PipelineCacheKey, compilation: @escaping () async throws -> Any) {
        guard pendingCompilations.count < maxPendingCompilations else {
            logger.warning("Too many pending compilations, skipping async compilation for \(key.description)")
            return
        }
        
        let task = Task {
            do {
                _ = try await compilation()
            } catch {
                logger.error("Async compilation failed for \(key.description): \(error.localizedDescription)")
                accessQueue.async(flags: .barrier) {
                    self.pendingCompilations.removeValue(forKey: key)
                }
                throw error
            }
        }
        
        pendingCompilations[key] = task
    }
    
    private func cancelAllPendingCompilations() {
        for (_, task) in pendingCompilations {
            task.cancel()
        }
        pendingCompilations.removeAll()
    }
    
    private func performCacheMaintenance() {
        let totalEntries = renderPipelineCache.count + computePipelineCache.count
        
        if totalEntries > maxCacheSize {
            performLRUEviction()
        }
    }
    
    private func performLRUEviction() {
        let targetSize = Int(Double(maxCacheSize) * 0.8)
        let totalEntries = renderPipelineCache.count + computePipelineCache.count
        let entriesToEvict = totalEntries - targetSize
        
        guard entriesToEvict > 0 else { return }
        
        var allEntries: [(PipelineCacheKey, PipelineCacheEntry, Bool)] = []
        
        for (key, entry) in renderPipelineCache {
            allEntries.append((key, entry, true))
        }
        
        for (key, entry) in computePipelineCache {
            allEntries.append((key, entry, false))
        }
        
        allEntries.sort { entry1, entry2 in
            if entry1.1.accessFrequency != entry2.1.accessFrequency {
                return entry1.1.accessFrequency < entry2.1.accessFrequency
            }
            return entry1.1.lastAccessDate < entry2.1.lastAccessDate
        }
        
        let evictionCount = min(entriesToEvict, allEntries.count)
        var evictedRender = 0
        var evictedCompute = 0
        
        for i in 0..<evictionCount {
            let (key, _, isRender) = allEntries[i]
            if isRender {
                renderPipelineCache.removeValue(forKey: key)
                evictedRender += 1
            } else {
                computePipelineCache.removeValue(forKey: key)
                evictedCompute += 1
            }
        }
        
        logger.info("Evicted \(evictedRender) render and \(evictedCompute) compute pipeline states")
    }
    
    private func estimatedMemoryUsage() -> Int {
        let renderPipelineSize = 1024 * 64 // Rough estimate per render pipeline
        let computePipelineSize = 1024 * 32 // Rough estimate per compute pipeline
        
        return renderPipelineCache.count * renderPipelineSize +
               computePipelineCache.count * computePipelineSize
    }
    
    private func createCacheKey(for descriptor: MTLRenderPipelineDescriptor) throws -> PipelineCacheKey {
        var hasher = SHA256()
        
        // Hash vertex function
        if let vertexFunction = descriptor.vertexFunction {
            hasher.update(data: Data(vertexFunction.name.utf8))
        }
        
        // Hash fragment function
        if let fragmentFunction = descriptor.fragmentFunction {
            hasher.update(data: Data(fragmentFunction.name.utf8))
        }
        
        // Hash color attachments
        for i in 0..<8 {
            if let attachment = descriptor.colorAttachments[i], attachment.pixelFormat != .invalid {
                hasher.update(data: Data([UInt8(attachment.pixelFormat.rawValue)]))
                hasher.update(data: Data([UInt8(attachment.sourceRGBBlendFactor.rawValue)]))
                hasher.update(data: Data([UInt8(attachment.destinationRGBBlendFactor.rawValue)]))
                hasher.update(data: Data([UInt8(attachment.rgbBlendOperation.rawValue)]))
                hasher.update(data: Data([UInt8(attachment.sourceAlphaBlendFactor.rawValue)]))
                hasher.update(data: Data([UInt8(attachment.destinationAlphaBlendFactor.rawValue)]))
                hasher.update(data: Data([UInt8(attachment.alphaBlendOperation.rawValue)]))
                hasher.update(data: Data([attachment.isBlendingEnabled ? 1 : 0]))
            }
        }
        
        // Hash depth/stencil formats
        hasher.update(data: Data([UInt8(descriptor.depthAttachmentPixelFormat.rawValue)]))
        hasher.update(data: Data([UInt8(descriptor.stencilAttachmentPixelFormat.rawValue)]))
        
        // Hash sample count
        hasher.update(data: Data([UInt8(descriptor.sampleCount)]))
        
        let hash = hasher.finalize().compactMap { String(format: "%02x", $0) }.joined()
        
        // Count active color attachments
        var colorAttachmentCount = 0
        for i in 0..<8 {
            if let attachment = descriptor.colorAttachments[i], attachment.pixelFormat != .invalid {
                colorAttachmentCount += 1
            }
        }
        
        return PipelineCacheKey(
            hash: hash,
            vertexFunction: descriptor.vertexFunction?.name,
            fragmentFunction: descriptor.fragmentFunction?.name,
            computeFunction: nil,
            colorAttachmentCount: colorAttachmentCount,
            depthAttachmentFormat: descriptor.depthAttachmentPixelFormat,
            stencilAttachmentFormat: descriptor.stencilAttachmentPixelFormat,
            sampleCount: descriptor.sampleCount
        )
    }
    
    private func createCacheKey(for function: MTLFunction) throws -> PipelineCacheKey {
        var hasher = SHA256()
        hasher.update(data: Data(function.name.utf8))
        
        let hash = hasher.finalize().compactMap { String(format: "%02x", $0) }.joined()
        
        return PipelineCacheKey(
            hash: hash,
            vertexFunction: nil,
            fragmentFunction: nil,
            computeFunction: function.name,
            colorAttachmentCount: 0,
            depthAttachmentFormat: nil,
            stencilAttachmentFormat: nil,
            sampleCount: 1
        )
    }
}

public struct CacheStatistics {
    public let totalEntries: Int
    public let renderPipelineCount: Int
    public let computePipelineCount: Int
    public let pendingCompilations: Int
    public let totalHits: Int
    public let memoryUsageBytes: Int
    
    public var memoryUsageMB: Double {
        return Double(memoryUsageBytes) / (1024 * 1024)
    }
    
    public var averageHitsPerEntry: Double {
        return totalEntries > 0 ? Double(totalHits) / Double(totalEntries) : 0
    }
}

extension PipelineStateCache {
    public func printStatistics() {
        let stats = cacheStatistics
        logger.info("""
        Pipeline Cache Statistics:
          Total Entries: \(stats.totalEntries)
          Render Pipelines: \(stats.renderPipelineCount)
          Compute Pipelines: \(stats.computePipelineCount)
          Pending Compilations: \(stats.pendingCompilations)
          Total Cache Hits: \(stats.totalHits)
          Average Hits per Entry: \(String(format: "%.1f", stats.averageHitsPerEntry))
          Memory Usage: \(String(format: "%.1f", stats.memoryUsageMB)) MB
        """)
    }
}