import Metal
import Foundation
import os.log

public enum ResourceHeapError: Error, LocalizedError {
    case heapCreationFailed
    case insufficientSpace
    case invalidResource
    case aliasConflict
    case heapFragmented
    case resourceNotInHeap
    case allocationFailed
    
    public var errorDescription: String? {
        switch self {
        case .heapCreationFailed:
            return "Failed to create resource heap"
        case .insufficientSpace:
            return "Insufficient space in resource heap"
        case .invalidResource:
            return "Invalid resource for heap allocation"
        case .aliasConflict:
            return "Resource aliasing conflict detected"
        case .heapFragmented:
            return "Resource heap is too fragmented"
        case .resourceNotInHeap:
            return "Resource not found in heap"
        case .allocationFailed:
            return "Failed to allocate resource"
        }
    }
}

public struct HeapAllocation {
    public let resource: MTLResource
    public let offset: Int
    public let size: Int
    public let alignment: Int
    public let creationTime: Date
    public var lastAccessTime: Date
    public var isAliased: Bool
    public let aliasGroup: String?
    
    public init(
        resource: MTLResource,
        offset: Int,
        size: Int,
        alignment: Int,
        aliasGroup: String? = nil
    ) {
        self.resource = resource
        self.offset = offset
        self.size = size
        self.alignment = alignment
        self.creationTime = Date()
        self.lastAccessTime = Date()
        self.isAliased = aliasGroup != nil
        self.aliasGroup = aliasGroup
    }
    
    public var endOffset: Int {
        return offset + size
    }
    
    public var ageInSeconds: TimeInterval {
        return Date().timeIntervalSince(creationTime)
    }
    
    public var timeSinceLastAccess: TimeInterval {
        return Date().timeIntervalSince(lastAccessTime)
    }
    
    public mutating func recordAccess() {
        lastAccessTime = Date()
    }
}

public struct HeapFragment {
    public let offset: Int
    public let size: Int
    
    public init(offset: Int, size: Int) {
        self.offset = offset
        self.size = size
    }
    
    public var endOffset: Int {
        return offset + size
    }
    
    public func canFit(size: Int, alignment: Int) -> Bool {
        let alignedOffset = alignUp(offset, to: alignment)
        return alignedOffset + size <= endOffset
    }
    
    public func allocate(size: Int, alignment: Int) -> (allocated: HeapFragment?, remaining: HeapFragment?) {
        let alignedOffset = alignUp(offset, to: alignment)
        
        guard alignedOffset + size <= endOffset else {
            return (nil, nil)
        }
        
        let allocated = HeapFragment(offset: alignedOffset, size: size)
        
        let remainingOffset = alignedOffset + size
        let remainingSize = endOffset - remainingOffset
        
        let remaining = remainingSize > 0 ? HeapFragment(offset: remainingOffset, size: remainingSize) : nil
        
        return (allocated, remaining)
    }
}

public class ResourceHeap {
    private let device: MetalDevice
    private let heap: MTLHeap
    private let logger = Logger(subsystem: "com.metalx.engine", category: "ResourceHeap")
    
    private var allocations: [ObjectIdentifier: HeapAllocation] = [:]
    private var freeFragments: [HeapFragment] = []
    private var aliasGroups: [String: Set<ObjectIdentifier>] = [:]
    private var activeAliasGroups: Set<String> = []
    
    private let accessQueue = DispatchQueue(label: "com.metalx.heap", attributes: .concurrent)
    private var totalAllocatedSize: Int = 0
    private var fragmentationThreshold: Double = 0.3
    private var maxIdleTime: TimeInterval = 300 // 5 minutes
    
    public let heapSize: Int
    public let storageMode: MTLStorageMode
    public let cpuCacheMode: MTLCPUCacheMode
    public let hazardTrackingMode: MTLHazardTrackingMode
    
    public var usedSize: Int {
        return accessQueue.sync { totalAllocatedSize }
    }
    
    public var freeSize: Int {
        return heapSize - usedSize
    }
    
    public var fragmentationRatio: Double {
        return accessQueue.sync {
            guard !freeFragments.isEmpty else { return 0.0 }
            
            let totalFreeSize = freeFragments.reduce(0) { $0 + $1.size }
            let largestFragment = freeFragments.max { $0.size < $1.size }?.size ?? 0
            
            guard totalFreeSize > 0 else { return 0.0 }
            return 1.0 - (Double(largestFragment) / Double(totalFreeSize))
        }
    }
    
    public var isFragmented: Bool {
        return fragmentationRatio > fragmentationThreshold
    }
    
    public init(
        device: MetalDevice,
        size: Int,
        storageMode: MTLStorageMode = .private,
        cpuCacheMode: MTLCPUCacheMode = .defaultCache,
        hazardTrackingMode: MTLHazardTrackingMode = .tracked
    ) throws {
        self.device = device
        self.heapSize = size
        self.storageMode = storageMode
        self.cpuCacheMode = cpuCacheMode
        self.hazardTrackingMode = hazardTrackingMode
        
        let descriptor = MTLHeapDescriptor()
        descriptor.size = size
        descriptor.storageMode = storageMode
        descriptor.cpuCacheMode = cpuCacheMode
        descriptor.hazardTrackingMode = hazardTrackingMode
        
        guard let heap = device.device.makeHeap(descriptor: descriptor) else {
            throw ResourceHeapError.heapCreationFailed
        }
        
        self.heap = heap
        self.freeFragments = [HeapFragment(offset: 0, size: size)]
        
        logger.info("Created resource heap: \(size / 1024 / 1024)MB")
    }
    
    public func allocateTexture(descriptor: MTLTextureDescriptor, aliasGroup: String? = nil) throws -> MTLTexture {
        guard let texture = heap.makeTexture(descriptor: descriptor) else {
            throw ResourceHeapError.allocationFailed
        }
        
        return texture
    }
    
    public func allocateBuffer(length: Int, options: MTLResourceOptions = [], aliasGroup: String? = nil) throws -> MTLBuffer {
        guard let buffer = heap.makeBuffer(length: length, options: options) else {
            throw ResourceHeapError.allocationFailed
        }
        
        return buffer
    }
    
    private func allocateResource<T: MTLResource>(
        size: Int,
        alignment: Int,
        aliasGroup: String?,
        factory: (Int) -> T?
    ) throws -> T {
        return try accessQueue.sync(flags: .barrier) {
            // Check for alias conflicts
            if let aliasGroup = aliasGroup {
                try validateAliasGroup(aliasGroup, size: size)
            }
            
            // Find suitable fragment
            guard let (fragmentIndex, fragment) = findSuitableFragment(size: size, alignment: alignment) else {
                throw ResourceHeapError.insufficientSpace
            }
            
            // Allocate from fragment
            let (allocated, remaining) = fragment.allocate(size: size, alignment: alignment)
            guard let allocatedFragment = allocated else {
                throw ResourceHeapError.insufficientSpace
            }
            
            // Create resource
            guard let resource = factory(allocatedFragment.offset) else {
                throw ResourceHeapError.invalidResource
            }
            
            // Update fragment list
            freeFragments.remove(at: fragmentIndex)
            if let remaining = remaining {
                freeFragments.append(remaining)
                sortFragmentsByOffset()
            }
            
            // Record allocation
            let allocation = HeapAllocation(
                resource: resource,
                offset: allocatedFragment.offset,
                size: allocatedFragment.size,
                alignment: alignment,
                aliasGroup: aliasGroup
            )
            
            allocations[ObjectIdentifier(resource)] = allocation
            totalAllocatedSize += allocatedFragment.size
            
            // Handle alias groups
            if let aliasGroup = aliasGroup {
                aliasGroups[aliasGroup, default: Set()].insert(ObjectIdentifier(resource))
                activeAliasGroups.insert(aliasGroup)
            }
            
            logger.debug("Allocated \(size) bytes at offset \(allocatedFragment.offset)")
            return resource
        }
    }
    
    public func deallocateResource(_ resource: MTLResource) throws {
        try accessQueue.sync(flags: .barrier) {
            let identifier = ObjectIdentifier(resource)
            
            guard let allocation = allocations.removeValue(forKey: identifier) else {
                throw ResourceHeapError.resourceNotInHeap
            }
            
            // Handle alias groups
            if let aliasGroup = allocation.aliasGroup {
                aliasGroups[aliasGroup]?.remove(identifier)
                if aliasGroups[aliasGroup]?.isEmpty == true {
                    aliasGroups.removeValue(forKey: aliasGroup)
                    activeAliasGroups.remove(aliasGroup)
                }
            }
            
            // Add back to free fragments
            let fragment = HeapFragment(offset: allocation.offset, size: allocation.size)
            freeFragments.append(fragment)
            totalAllocatedSize -= allocation.size
            
            // Merge adjacent fragments
            mergeAdjacentFragments()
            
            logger.debug("Deallocated \(allocation.size) bytes at offset \(allocation.offset)")
        }
    }
    
    public func makeAliasable(resources: [MTLResource], aliasGroup: String) throws {
        try accessQueue.sync(flags: .barrier) {
            // Validate all resources are in this heap
            for resource in resources {
                let identifier = ObjectIdentifier(resource)
                guard var allocation = allocations[identifier] else {
                    throw ResourceHeapError.resourceNotInHeap
                }
                
                allocation.isAliased = true
                allocation = HeapAllocation(
                    resource: allocation.resource,
                    offset: allocation.offset,
                    size: allocation.size,
                    alignment: allocation.alignment,
                    aliasGroup: aliasGroup
                )
                allocations[identifier] = allocation
            }
            
            // Update alias group
            let identifiers = resources.map { ObjectIdentifier($0) }
            aliasGroups[aliasGroup] = Set(identifiers)
        }
    }
    
    public func activateAliasGroup(_ aliasGroup: String) {
        accessQueue.async(flags: .barrier) {
            self.activeAliasGroups.insert(aliasGroup)
        }
    }
    
    public func deactivateAliasGroup(_ aliasGroup: String) {
        accessQueue.async(flags: .barrier) {
            self.activeAliasGroups.remove(aliasGroup)
        }
    }
    
    public func recordResourceAccess(_ resource: MTLResource) {
        accessQueue.async(flags: .barrier) {
            let identifier = ObjectIdentifier(resource)
            self.allocations[identifier]?.recordAccess()
        }
    }
    
    public func performGarbageCollection() {
        accessQueue.async(flags: .barrier) {
            let _ = Date()
            var resourcesToRemove: [MTLResource] = []
            
            for (_, allocation) in self.allocations {
                if allocation.timeSinceLastAccess > self.maxIdleTime {
                    resourcesToRemove.append(allocation.resource)
                }
            }
            
            for resource in resourcesToRemove {
                do {
                    try self.deallocateResource(resource)
                    self.logger.debug("Garbage collected idle resource")
                } catch {
                    self.logger.error("Failed to garbage collect resource: \(error.localizedDescription)")
                }
            }
            
            if !resourcesToRemove.isEmpty {
                self.logger.info("Garbage collected \(resourcesToRemove.count) idle resources")
            }
        }
    }
    
    public func defragment() throws {
        // Note: Real defragmentation would require recreating resources
        // This is a simplified version that merges free fragments
        try accessQueue.sync(flags: .barrier) {
            mergeAdjacentFragments()
            
            // Sort fragments by size (largest first) for better allocation
            freeFragments.sort { $0.size > $1.size }
            
            logger.info("Defragmented heap, fragmentation ratio: \(String(format: "%.2f", self.fragmentationRatio), privacy: .public)")
        }
    }
    
    private func findSuitableFragment(size: Int, alignment: Int) -> (index: Int, fragment: HeapFragment)? {
        for (index, fragment) in freeFragments.enumerated() {
            if fragment.canFit(size: size, alignment: alignment) {
                return (index, fragment)
            }
        }
        return nil
    }
    
    private func validateAliasGroup(_ aliasGroup: String, size: Int) throws {
        if activeAliasGroups.contains(aliasGroup) {
            throw ResourceHeapError.aliasConflict
        }
    }
    
    private func mergeAdjacentFragments() {
        freeFragments.sort { $0.offset < $1.offset }
        
        var mergedFragments: [HeapFragment] = []
        var currentFragment: HeapFragment?
        
        for fragment in freeFragments {
            if let current = currentFragment {
                if current.endOffset == fragment.offset {
                    // Merge fragments
                    currentFragment = HeapFragment(
                        offset: current.offset,
                        size: current.size + fragment.size
                    )
                } else {
                    mergedFragments.append(current)
                    currentFragment = fragment
                }
            } else {
                currentFragment = fragment
            }
        }
        
        if let current = currentFragment {
            mergedFragments.append(current)
        }
        
        freeFragments = mergedFragments
    }
    
    private func sortFragmentsByOffset() {
        freeFragments.sort { $0.offset < $1.offset }
    }
    
    public var statistics: HeapStatistics {
        return accessQueue.sync {
            HeapStatistics(
                totalSize: heapSize,
                usedSize: totalAllocatedSize,
                freeSize: heapSize - totalAllocatedSize,
                fragmentCount: freeFragments.count,
                largestFreeFragment: freeFragments.max { $0.size < $1.size }?.size ?? 0,
                allocationCount: allocations.count,
                fragmentationRatio: fragmentationRatio,
                activeAliasGroups: activeAliasGroups.count
            )
        }
    }
}

public struct HeapStatistics {
    public let totalSize: Int
    public let usedSize: Int
    public let freeSize: Int
    public let fragmentCount: Int
    public let largestFreeFragment: Int
    public let allocationCount: Int
    public let fragmentationRatio: Double
    public let activeAliasGroups: Int
    
    public var utilizationRatio: Double {
        return totalSize > 0 ? Double(usedSize) / Double(totalSize) : 0.0
    }
    
    public var isHealthy: Bool {
        return fragmentationRatio < 0.5 && utilizationRatio < 0.9
    }
}

// MARK: - Utility Functions

private func alignUp(_ value: Int, to alignment: Int) -> Int {
    return (value + alignment - 1) & ~(alignment - 1)
}

extension ResourceHeap {
    public func printStatistics() {
        let stats = statistics
        logger.info("""
        Resource Heap Statistics:
          Total Size: \(stats.totalSize / 1024 / 1024) MB
          Used Size: \(stats.usedSize / 1024 / 1024) MB (\(String(format: "%.1f", stats.utilizationRatio * 100))%)
          Free Size: \(stats.freeSize / 1024 / 1024) MB
          Allocations: \(stats.allocationCount)
          Fragments: \(stats.fragmentCount)
          Largest Free Fragment: \(stats.largestFreeFragment / 1024) KB
          Fragmentation: \(String(format: "%.2f", stats.fragmentationRatio))
          Active Alias Groups: \(stats.activeAliasGroups)
          Health: \(stats.isHealthy ? "Good" : "Poor")
        """)
    }
}

// MARK: - ResourceHeap Factory

public class ResourceHeapManager {
    private let device: MetalDevice
    private var heaps: [String: ResourceHeap] = [:]
    private let logger = Logger(subsystem: "com.metalx.engine", category: "HeapManager")
    
    public init(device: MetalDevice) {
        self.device = device
        createDefaultHeaps()
    }
    
    public func getHeap(named name: String) -> ResourceHeap? {
        return heaps[name]
    }
    
    public func createHeap(
        name: String,
        size: Int,
        storageMode: MTLStorageMode = .private
    ) throws -> ResourceHeap {
        let heap = try ResourceHeap(
            device: device,
            size: size,
            storageMode: storageMode
        )
        heaps[name] = heap
        return heap
    }
    
    private func createDefaultHeaps() {
        do {
            // Create default heaps based on device capabilities
            // Use reasonable defaults if recommendedMaxWorkingSetSize is 0
            let memoryBudget = max(device.capabilities.recommendedMaxWorkingSetSize, 512 * 1024 * 1024) // Min 512MB
            
            // Main heap for general resources
            let mainHeapSize = Int(Double(memoryBudget) * 0.6)
            // Transient heap for short-lived resources
            let transientHeapSize = Int(Double(memoryBudget) * 0.2)
            
            // Heaps must use .private storage mode
            let storageMode: MTLStorageMode = .private
            
            let mainHeap = try ResourceHeap(device: device, size: mainHeapSize, storageMode: storageMode)
            heaps["main"] = mainHeap
            
            let transientHeap = try ResourceHeap(device: device, size: transientHeapSize, storageMode: storageMode)
            heaps["transient"] = transientHeap
            
            logger.info("Created default heaps: main=\(mainHeapSize/1024/1024)MB, transient=\(transientHeapSize/1024/1024)MB")
        } catch {
            logger.error("Failed to create default heaps: \(error.localizedDescription)")
        }
    }
    
    public func performGlobalGarbageCollection() {
        for heap in heaps.values {
            heap.performGarbageCollection()
        }
    }
    
    public func printAllHeapStatistics() {
        for (name, heap) in heaps {
            logger.info("Heap '\(name)':")
            heap.printStatistics()
        }
    }
}