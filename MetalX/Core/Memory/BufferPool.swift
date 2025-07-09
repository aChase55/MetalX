import Metal
import Foundation
import os.log

public enum BufferPoolError: Error, LocalizedError {
    case allocationFailed
    case invalidSize
    case poolExhausted
    case bufferCreationFailed
    case alignmentError
    
    public var errorDescription: String? {
        switch self {
        case .allocationFailed:
            return "Buffer allocation failed"
        case .invalidSize:
            return "Invalid buffer size"
        case .poolExhausted:
            return "Buffer pool is exhausted"
        case .bufferCreationFailed:
            return "Failed to create buffer"
        case .alignmentError:
            return "Buffer alignment error"
        }
    }
}

public enum BufferType: CaseIterable {
    case vertex
    case index
    case uniform
    case storage
    case staging
    
    public var defaultSize: Int {
        switch self {
        case .vertex: return 1024 * 1024 // 1MB
        case .index: return 512 * 1024   // 512KB
        case .uniform: return 64 * 1024  // 64KB
        case .storage: return 4 * 1024 * 1024 // 4MB
        case .staging: return 2 * 1024 * 1024 // 2MB
        }
    }
    
    public var alignment: Int {
        switch self {
        case .vertex: return 4
        case .index: return 4
        case .uniform: return 256 // Uniform buffer alignment requirement
        case .storage: return 16
        case .staging: return 1
        }
    }
    
    public var resourceOptions: MTLResourceOptions {
        switch self {
        case .vertex, .index:
            return [.storageModeShared, .hazardTrackingModeUntracked]
        case .uniform:
            return [.storageModeShared, .cpuCacheModeWriteCombined]
        case .storage:
            return [.storageModePrivate]
        case .staging:
            return [.storageModeShared]
        }
    }
    
    public var usage: MTLResourceUsage {
        switch self {
        case .vertex, .index: return [.read]
        case .uniform: return [.read]
        case .storage: return [.read, .write]
        case .staging: return [.read, .write]
        }
    }
}

public struct BufferAllocation {
    public let buffer: MTLBuffer
    public let offset: Int
    public let size: Int
    public let alignment: Int
    public let type: BufferType
    public let creationTime: Date
    public var lastAccessTime: Date
    public var isActive: Bool
    
    public init(buffer: MTLBuffer, offset: Int, size: Int, alignment: Int, type: BufferType) {
        self.buffer = buffer
        self.offset = offset
        self.size = size
        self.alignment = alignment
        self.type = type
        self.creationTime = Date()
        self.lastAccessTime = Date()
        self.isActive = true
    }
    
    public var endOffset: Int {
        return offset + size
    }
    
    public var contents: UnsafeMutableRawPointer? {
        let basePointer = buffer.contents()
        return basePointer.advanced(by: offset)
    }
    
    public mutating func recordAccess() {
        lastAccessTime = Date()
    }
    
    public var timeSinceLastAccess: TimeInterval {
        return Date().timeIntervalSince(lastAccessTime)
    }
}

public class PooledBuffer {
    private let buffer: MTLBuffer
    private let type: BufferType
    private let logger = Logger(subsystem: "com.metalx.engine", category: "PooledBuffer")
    
    private var allocations: [(offset: Int, size: Int, isActive: Bool)] = []
    private var freeRanges: [(offset: Int, size: Int)] = []
    private let accessQueue = DispatchQueue(label: "com.metalx.pooled.buffer", attributes: .concurrent)
    
    public let totalSize: Int
    public var usedSize: Int = 0
    public var freeSize: Int { totalSize - usedSize }
    public var utilizationRatio: Double { Double(usedSize) / Double(totalSize) }
    public var mtlBuffer: MTLBuffer { buffer }
    
    public init(device: MetalDevice, size: Int, type: BufferType) throws {
        self.totalSize = size
        self.type = type
        
        guard let buffer = device.makeBuffer(length: size, options: type.resourceOptions) else {
            throw BufferPoolError.bufferCreationFailed
        }
        
        self.buffer = buffer
        self.freeRanges = [(offset: 0, size: size)]
        
        buffer.label = "PooledBuffer_\(type)_\(size)"
    }
    
    public func allocate(size: Int) throws -> BufferAllocation {
        return try accessQueue.sync(flags: .barrier) {
            let alignedSize = alignUp(size, to: type.alignment)
            
            guard let rangeIndex = findSuitableRange(size: alignedSize) else {
                throw BufferPoolError.poolExhausted
            }
            
            let range = freeRanges[rangeIndex]
            let allocation = BufferAllocation(
                buffer: buffer,
                offset: range.offset,
                size: alignedSize,
                alignment: type.alignment,
                type: type
            )
            
            // Update free ranges
            freeRanges.remove(at: rangeIndex)
            let remainingSize = range.size - alignedSize
            if remainingSize > 0 {
                freeRanges.append((offset: range.offset + alignedSize, size: remainingSize))
                freeRanges.sort { $0.offset < $1.offset }
            }
            
            // Track allocation
            allocations.append((offset: range.offset, size: alignedSize, isActive: true))
            usedSize += alignedSize
            
            return allocation
        }
    }
    
    public func deallocate(_ allocation: BufferAllocation) {
        accessQueue.async(flags: .barrier) {
            guard let index = self.allocations.firstIndex(where: { 
                $0.offset == allocation.offset && $0.size == allocation.size 
            }) else {
                return
            }
            
            self.allocations[index].isActive = false
            self.usedSize -= allocation.size
            
            // Add back to free ranges
            self.freeRanges.append((offset: allocation.offset, size: allocation.size))
            self.mergeAdjacentRanges()
        }
    }
    
    private func findSuitableRange(size: Int) -> Int? {
        for (index, range) in freeRanges.enumerated() {
            if range.size >= size {
                return index
            }
        }
        return nil
    }
    
    private func mergeAdjacentRanges() {
        freeRanges.sort { $0.offset < $1.offset }
        
        var mergedRanges: [(offset: Int, size: Int)] = []
        var currentRange: (offset: Int, size: Int)?
        
        for range in freeRanges {
            if let current = currentRange {
                if current.offset + current.size == range.offset {
                    // Merge ranges
                    currentRange = (offset: current.offset, size: current.size + range.size)
                } else {
                    mergedRanges.append(current)
                    currentRange = range
                }
            } else {
                currentRange = range
            }
        }
        
        if let current = currentRange {
            mergedRanges.append(current)
        }
        
        freeRanges = mergedRanges
    }
    
    public var canAllocate: Bool {
        return accessQueue.sync { !freeRanges.isEmpty }
    }
    
    public var largestFreeBlock: Int {
        return accessQueue.sync {
            freeRanges.max { $0.size < $1.size }?.size ?? 0
        }
    }
}

public class BufferPool {
    private let device: MetalDevice
    private let resourceHeap: ResourceHeap?
    private let logger = Logger(subsystem: "com.metalx.engine", category: "BufferPool")
    
    private var pools: [BufferType: [PooledBuffer]] = [:]
    private var activeAllocations: [ObjectIdentifier: BufferAllocation] = [:]
    
    private let accessQueue = DispatchQueue(label: "com.metalx.bufferpool", attributes: .concurrent)
    private var totalMemoryUsage: Int = 0
    private let maxMemoryUsage: Int
    
    // Pool configuration
    private let maxPoolsPerType: Int = 8
    private let growthFactor: Double = 1.5
    private let shrinkThreshold: Double = 0.3
    private let maxIdleTime: TimeInterval = 300 // 5 minutes
    
    public var memoryUsage: Int {
        return accessQueue.sync { totalMemoryUsage }
    }
    
    public var poolStatistics: BufferPoolStatistics {
        return accessQueue.sync {
            var typeStatistics: [BufferType: BufferTypeStatistics] = [:]
            
            for type in BufferType.allCases {
                let poolsForType = pools[type] ?? []
                let totalBuffers = poolsForType.count
                let totalCapacity = poolsForType.reduce(0) { $0 + $1.totalSize }
                let totalUsed = poolsForType.reduce(0) { $0 + $1.usedSize }
                let averageUtilization = totalBuffers > 0 ? poolsForType.reduce(0.0) { $0 + $1.utilizationRatio } / Double(totalBuffers) : 0.0
                
                typeStatistics[type] = BufferTypeStatistics(
                    bufferCount: totalBuffers,
                    totalCapacity: totalCapacity,
                    usedCapacity: totalUsed,
                    averageUtilization: averageUtilization
                )
            }
            
            return BufferPoolStatistics(
                totalMemoryUsage: totalMemoryUsage,
                maxMemoryUsage: maxMemoryUsage,
                activeAllocations: activeAllocations.count,
                typeStatistics: typeStatistics
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
        // Use a reasonable default if recommendedMaxWorkingSetSize is 0 or too small
        let defaultBudget = 128 * 1024 * 1024 // 128MB default
        let recommendedBudget = device.capabilities.recommendedMaxWorkingSetSize / 8
        self.maxMemoryUsage = maxMemoryUsage ?? max(recommendedBudget, defaultBudget)
        
        // Initialize pools for each buffer type
        for type in BufferType.allCases {
            pools[type] = []
        }
        
        // startMaintenanceTimer() // Disabled - causing crashes
        logger.info("Initialized buffer pool with \(self.maxMemoryUsage / 1024 / 1024)MB budget")
    }
    
    public func allocateBuffer(size: Int, type: BufferType) throws -> BufferAllocation {
        return try accessQueue.sync(flags: .barrier) { () throws -> BufferAllocation in
            let alignedSize = alignUp(size, to: type.alignment)
            
            // Try to allocate from existing pools
            if let allocation = tryAllocateFromExistingPools(size: alignedSize, type: type) {
                activeAllocations[ObjectIdentifier(allocation.buffer)] = allocation
                return allocation
            }
            
            // Create new pool if needed and allowed
            let newPoolSize = max(alignedSize * 2, type.defaultSize)
            
            if totalMemoryUsage + newPoolSize > maxMemoryUsage {
                throw BufferPoolError.poolExhausted
            }
            
            let newPool = try createNewPool(size: newPoolSize, type: type)
            pools[type]!.append(newPool)
            totalMemoryUsage += newPoolSize
            
            let allocation = try newPool.allocate(size: alignedSize)
            activeAllocations[ObjectIdentifier(allocation.buffer)] = allocation
            
            logger.debug("Created new \(String(describing: type)) pool (\(newPoolSize / 1024)KB) and allocated \(alignedSize) bytes")
            return allocation
        }
    }
    
    public func deallocateBuffer(_ allocation: BufferAllocation) {
        accessQueue.async(flags: .barrier) {
            let identifier = ObjectIdentifier(allocation.buffer)
            guard self.activeAllocations.removeValue(forKey: identifier) != nil else {
                self.logger.warning("Attempted to deallocate buffer not from pool")
                return
            }
            
            // Find the pool that owns this buffer
            if let pools = self.pools[allocation.type] {
                for pool in pools {
                    if ObjectIdentifier(pool.mtlBuffer) == ObjectIdentifier(allocation.buffer) {
                        pool.deallocate(allocation)
                        break
                    }
                }
            }
        }
    }
    
    public func allocateVertexBuffer(size: Int) throws -> BufferAllocation {
        return try allocateBuffer(size: size, type: .vertex)
    }
    
    public func allocateIndexBuffer(size: Int) throws -> BufferAllocation {
        return try allocateBuffer(size: size, type: .index)
    }
    
    public func allocateUniformBuffer(size: Int) throws -> BufferAllocation {
        return try allocateBuffer(size: size, type: .uniform)
    }
    
    public func allocateStorageBuffer(size: Int) throws -> BufferAllocation {
        return try allocateBuffer(size: size, type: .storage)
    }
    
    public func allocateStagingBuffer(size: Int) throws -> BufferAllocation {
        return try allocateBuffer(size: size, type: .staging)
    }
    
    public func preloadBuffers(type: BufferType, count: Int = 4) {
        for _ in 0..<count {
            do {
                let allocation = try allocateBuffer(size: type.defaultSize / 4, type: type)
                deallocateBuffer(allocation)
            } catch {
                self.logger.error("Failed to preload \(String(describing: type)) buffer: \(error.localizedDescription)")
            }
        }
    }
    
    public func performMaintenanceCycle() {
        accessQueue.async(flags: .barrier) {
            for type in BufferType.allCases {
                self.performMaintenanceForType(type)
            }
        }
    }
    
    public func clearPool(type: BufferType? = nil) {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            if let specificType = type {
                let removedPools = self.pools[specificType] ?? []
                let reclaimedMemory = removedPools.reduce(0) { $0 + $1.totalSize }
                self.pools[specificType] = []
                self.totalMemoryUsage -= reclaimedMemory
                
                self.logger.info("Cleared \(String(describing: specificType)) buffer pool, reclaimed \(reclaimedMemory / 1024 / 1024)MB")
            } else {
                let reclaimedMemory = self.totalMemoryUsage
                for type in BufferType.allCases {
                    self.pools[type] = []
                }
                self.totalMemoryUsage = 0
                
                self.logger.info("Cleared all buffer pools, reclaimed \(reclaimedMemory / 1024 / 1024)MB")
            }
        }
    }
    
    private func tryAllocateFromExistingPools(size: Int, type: BufferType) -> BufferAllocation? {
        guard let poolsForType = pools[type] else { return nil }
        
        // Try pools in order of utilization (prefer less utilized pools)
        let sortedPools = poolsForType.sorted { $0.utilizationRatio < $1.utilizationRatio }
        
        for pool in sortedPools {
            if pool.largestFreeBlock >= size {
                do {
                    return try pool.allocate(size: size)
                } catch {
                    continue
                }
            }
        }
        
        return nil
    }
    
    private func createNewPool(size: Int, type: BufferType) throws -> PooledBuffer {
        if resourceHeap != nil {
            // TODO: Integrate with resource heap allocation
            // For now, fall back to direct allocation
        }
        
        return try PooledBuffer(device: device, size: size, type: type)
    }
    
    private func performMaintenanceForType(_ type: BufferType) {
        guard var poolsForType = pools[type] else { return }
        
        // Remove empty or underutilized pools
        var keptPools: [PooledBuffer] = []
        var removedMemory = 0
        
        for pool in poolsForType {
            if pool.utilizationRatio < shrinkThreshold && poolsForType.count > 1 {
                removedMemory += pool.totalSize
                logger.debug("Removed underutilized \(String(describing: type)) pool (\(pool.totalSize / 1024)KB, \(String(format: "%.1f", pool.utilizationRatio * 100))% used)")
            } else {
                keptPools.append(pool)
            }
        }
        
        pools[type] = keptPools
        totalMemoryUsage -= removedMemory
        
        if removedMemory > 0 {
            logger.info("Pool maintenance for \(String(describing: type)): removed \(removedMemory / 1024 / 1024)MB")
        }
    }
    
    private func startMaintenanceTimer() {
        Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.performMaintenanceCycle()
        }
    }
}

public struct BufferTypeStatistics {
    public let bufferCount: Int
    public let totalCapacity: Int
    public let usedCapacity: Int
    public let averageUtilization: Double
    
    public var freeCapacity: Int {
        return totalCapacity - usedCapacity
    }
    
    public var utilizationRatio: Double {
        return totalCapacity > 0 ? Double(usedCapacity) / Double(totalCapacity) : 0.0
    }
}

public struct BufferPoolStatistics {
    public let totalMemoryUsage: Int
    public let maxMemoryUsage: Int
    public let activeAllocations: Int
    public let typeStatistics: [BufferType: BufferTypeStatistics]
    
    public var memoryUtilization: Double {
        return maxMemoryUsage > 0 ? Double(totalMemoryUsage) / Double(maxMemoryUsage) : 0.0
    }
    
    public var memoryUsageMB: Double {
        return Double(totalMemoryUsage) / (1024 * 1024)
    }
    
    public var maxMemoryUsageMB: Double {
        return Double(maxMemoryUsage) / (1024 * 1024)
    }
}

// MARK: - Convenience Extensions

extension BufferAllocation {
    public func write<T>(_ data: T, at offset: Int = 0) {
        guard let contents = contents else { return }
        let typedPointer = contents.advanced(by: offset).assumingMemoryBound(to: T.self)
        typedPointer.pointee = data
    }
    
    public func write<T>(_ data: [T], at offset: Int = 0) {
        guard let contents = contents else { return }
        let byteOffset = offset
        let typedPointer = contents.advanced(by: byteOffset).assumingMemoryBound(to: T.self)
        for (index, element) in data.enumerated() {
            typedPointer.advanced(by: index).pointee = element
        }
    }
    
    public func read<T>(_ type: T.Type, at offset: Int = 0) -> T? {
        guard let contents = contents else { return nil }
        let typedPointer = contents.advanced(by: offset).assumingMemoryBound(to: T.self)
        return typedPointer.pointee
    }
}

// MARK: - Utility Functions

private func alignUp(_ value: Int, to alignment: Int) -> Int {
    return (value + alignment - 1) & ~(alignment - 1)
}

extension BufferPool {
    public func printStatistics() {
        let stats = poolStatistics
        logger.info("""
        Buffer Pool Statistics:
          Total Memory Usage: \(String(format: "%.1f", stats.memoryUsageMB)) / \(String(format: "%.1f", stats.maxMemoryUsageMB)) MB (\(String(format: "%.1f", stats.memoryUtilization * 100))%)
          Active Allocations: \(stats.activeAllocations)
        """)
        
        for (type, typeStats) in stats.typeStatistics {
            logger.info("""
            \(String(describing: type)) Buffers:
              Count: \(typeStats.bufferCount)
              Capacity: \(typeStats.totalCapacity / 1024)KB (\(typeStats.usedCapacity / 1024)KB used)
              Utilization: \(String(format: "%.1f", typeStats.utilizationRatio * 100))%
            """)
        }
    }
}