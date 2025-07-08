import Metal
import Foundation
import os.log

public enum CommandBuilderError: Error, LocalizedError {
    case commandBufferCreationFailed
    case invalidCommandBuffer
    case encoderCreationFailed
    case resourceNotReady
    case bufferPoolExhausted
    
    public var errorDescription: String? {
        switch self {
        case .commandBufferCreationFailed:
            return "Failed to create command buffer"
        case .invalidCommandBuffer:
            return "Command buffer is invalid or has been committed"
        case .encoderCreationFailed:
            return "Failed to create command encoder"
        case .resourceNotReady:
            return "Required resource is not ready"
        case .bufferPoolExhausted:
            return "Command buffer pool is exhausted"
        }
    }
}

public struct DrawCall {
    public let primitiveType: MTLPrimitiveType
    public let vertexStart: Int
    public let vertexCount: Int
    public let instanceCount: Int
    public let indexBuffer: MTLBuffer?
    public let indexCount: Int
    public let indexType: MTLIndexType
    public let indexBufferOffset: Int
    
    public init(
        primitiveType: MTLPrimitiveType,
        vertexStart: Int = 0,
        vertexCount: Int,
        instanceCount: Int = 1,
        indexBuffer: MTLBuffer? = nil,
        indexCount: Int = 0,
        indexType: MTLIndexType = .uint16,
        indexBufferOffset: Int = 0
    ) {
        self.primitiveType = primitiveType
        self.vertexStart = vertexStart
        self.vertexCount = vertexCount
        self.instanceCount = instanceCount
        self.indexBuffer = indexBuffer
        self.indexCount = indexCount
        self.indexType = indexType
        self.indexBufferOffset = indexBufferOffset
    }
    
    public var isIndexed: Bool {
        return indexBuffer != nil && indexCount > 0
    }
}

public struct BatchedDrawCall {
    public let drawCalls: [DrawCall]
    public let totalVertices: Int
    public let totalInstances: Int
    
    public init(drawCalls: [DrawCall]) {
        self.drawCalls = drawCalls
        self.totalVertices = drawCalls.reduce(0) { $0 + $1.vertexCount }
        self.totalInstances = drawCalls.reduce(0) { $0 + $1.instanceCount }
    }
    
    public var canBatch: Bool {
        guard !drawCalls.isEmpty else { return false }
        
        let firstCall = drawCalls[0]
        return drawCalls.allSatisfy { call in
            call.primitiveType == firstCall.primitiveType &&
            call.isIndexed == firstCall.isIndexed &&
            (call.indexBuffer === firstCall.indexBuffer || (!call.isIndexed && !firstCall.isIndexed))
        }
    }
}

public class CommandBufferPool {
    private let device: MetalDevice
    private let maxPoolSize: Int
    private var availableBuffers: [MTLCommandBuffer] = []
    private var activeBuffers: Set<ObjectIdentifier> = []
    private let poolQueue = DispatchQueue(label: "com.metalx.commandpool", attributes: .concurrent)
    private let logger = Logger(subsystem: "com.metalx.engine", category: "CommandPool")
    
    public init(device: MetalDevice, maxPoolSize: Int = 16) {
        self.device = device
        self.maxPoolSize = maxPoolSize
        prewarmPool()
    }
    
    public func acquireCommandBuffer(label: String? = nil) throws -> MTLCommandBuffer {
        return try poolQueue.sync(flags: .barrier) {
            let buffer: MTLCommandBuffer
            
            if let availableBuffer = availableBuffers.popLast() {
                buffer = availableBuffer
            } else {
                guard let newBuffer = device.makeCommandBuffer() else {
                    throw CommandBuilderError.commandBufferCreationFailed
                }
                buffer = newBuffer
            }
            
            buffer.label = label
            activeBuffers.insert(ObjectIdentifier(buffer))
            
            // Add completion handler to return buffer to pool
            buffer.addCompletedHandler { [weak self] completedBuffer in
                self?.returnBufferToPool(completedBuffer)
            }
            
            return buffer
        }
    }
    
    public func returnBufferToPool(_ buffer: MTLCommandBuffer) {
        poolQueue.async(flags: .barrier) {
            let identifier = ObjectIdentifier(buffer)
            self.activeBuffers.remove(identifier)
            
            // Only return to pool if not at capacity and buffer is reusable
            if self.availableBuffers.count < self.maxPoolSize && buffer.status == .completed {
                self.availableBuffers.append(buffer)
            }
        }
    }
    
    public var poolStatistics: (available: Int, active: Int) {
        return poolQueue.sync {
            (available: availableBuffers.count, active: activeBuffers.count)
        }
    }
    
    private func prewarmPool() {
        poolQueue.async(flags: .barrier) {
            let prewarmCount = min(4, self.maxPoolSize)
            for _ in 0..<prewarmCount {
                if let buffer = self.device.makeCommandBuffer() {
                    self.availableBuffers.append(buffer)
                }
            }
            self.logger.info("Prewarmed command buffer pool with \(self.availableBuffers.count) buffers")
        }
    }
    
    public func drainPool() {
        poolQueue.async(flags: .barrier) {
            self.availableBuffers.removeAll()
            self.activeBuffers.removeAll()
        }
    }
}

public class GPUTimer {
    private let device: MetalDevice
    private var timingBuffers: [MTLBuffer] = []
    private var currentTimingIndex = 0
    private let maxTimings = 1000
    private let logger = Logger(subsystem: "com.metalx.engine", category: "GPUTimer")
    
    public struct TimingResult {
        public let label: String
        public let gpuTime: TimeInterval
        public let cpuTime: TimeInterval
        public let timestamp: Date
        
        public var totalTime: TimeInterval {
            return gpuTime + cpuTime
        }
    }
    
    private var pendingTimings: [String: (start: Date, commandBuffer: MTLCommandBuffer)] = [:]
    private var completedTimings: [TimingResult] = []
    
    public init(device: MetalDevice) {
        self.device = device
        setupTimingBuffers()
    }
    
    public func beginTiming(_ label: String, commandBuffer: MTLCommandBuffer) {
        let startTime = Date()
        pendingTimings[label] = (start: startTime, commandBuffer: commandBuffer)
        
        commandBuffer.addCompletedHandler { [weak self] buffer in
            self?.endTiming(label, buffer: buffer)
        }
    }
    
    private func endTiming(_ label: String, buffer: MTLCommandBuffer) {
        guard let pending = pendingTimings.removeValue(forKey: label) else { return }
        
        let endTime = Date()
        let cpuTime = endTime.timeIntervalSince(pending.start)
        
        // GPU time measurement would require more complex Metal performance counter integration
        // For now, we'll estimate based on command buffer execution time
        let gpuTime = buffer.gpuEndTime - buffer.gpuStartTime
        
        let result = TimingResult(
            label: label,
            gpuTime: gpuTime,
            cpuTime: cpuTime,
            timestamp: pending.start
        )
        
        completedTimings.append(result)
        
        // Keep only recent timings
        if completedTimings.count > maxTimings {
            completedTimings.removeFirst(completedTimings.count - maxTimings)
        }
        
        logger.debug("Timing [\(label)]: GPU=\(Int(gpuTime * 1000))ms, CPU=\(Int(cpuTime * 1000))ms")
    }
    
    public func getTimingResults(since: Date? = nil) -> [TimingResult] {
        if let since = since {
            return completedTimings.filter { $0.timestamp >= since }
        }
        return completedTimings
    }
    
    public func getAverageTime(for label: String) -> TimeInterval? {
        let matchingTimings = completedTimings.filter { $0.label == label }
        guard !matchingTimings.isEmpty else { return nil }
        
        let totalTime = matchingTimings.reduce(0) { $0 + $1.totalTime }
        return totalTime / Double(matchingTimings.count)
    }
    
    private func setupTimingBuffers() {
        // Setup for more sophisticated GPU timing if needed
        logger.info("GPU timer initialized")
    }
}

public class CommandBuilder {
    private let device: MetalDevice
    private let commandPool: CommandBufferPool
    private let timer: GPUTimer
    private let logger = Logger(subsystem: "com.metalx.engine", category: "CommandBuilder")
    
    private var currentCommandBuffer: MTLCommandBuffer?
    private var pendingDrawCalls: [DrawCall] = []
    private var batchingEnabled: Bool = true
    private var maxBatchSize: Int = 1000
    
    public var enableTiming: Bool = false
    public var enableDrawCallBatching: Bool = true {
        didSet {
            batchingEnabled = enableDrawCallBatching
        }
    }
    
    public init(device: MetalDevice) {
        self.device = device
        self.commandPool = CommandBufferPool(device: device)
        self.timer = GPUTimer(device: device)
    }
    
    public func beginCommandBuffer(label: String? = nil) throws -> MTLCommandBuffer {
        if let existing = currentCommandBuffer {
            logger.warning("Beginning new command buffer while one is active. Committing existing buffer.")
            existing.commit()
        }
        
        let buffer = try commandPool.acquireCommandBuffer(label: label)
        currentCommandBuffer = buffer
        
        if enableTiming, let label = label {
            timer.beginTiming(label, commandBuffer: buffer)
        }
        
        return buffer
    }
    
    public func commitCommandBuffer() throws {
        guard let buffer = currentCommandBuffer else {
            throw CommandBuilderError.invalidCommandBuffer
        }
        
        // Flush any pending batched draw calls
        flushPendingDrawCalls()
        
        buffer.commit()
        currentCommandBuffer = nil
        
        logger.debug("Committed command buffer: \(buffer.label ?? "unlabeled")")
    }
    
    public func addDrawCall(_ drawCall: DrawCall) {
        if batchingEnabled && pendingDrawCalls.count < maxBatchSize {
            pendingDrawCalls.append(drawCall)
        } else {
            flushPendingDrawCalls()
            pendingDrawCalls.append(drawCall)
        }
    }
    
    public func flushPendingDrawCalls() {
        guard !pendingDrawCalls.isEmpty else { return }
        
        let batch = BatchedDrawCall(drawCalls: pendingDrawCalls)
        
        if batch.canBatch && pendingDrawCalls.count > 1 {
            executeBatchedDrawCalls(batch)
            logger.debug("Executed batched draw calls: \(pendingDrawCalls.count) calls, \(batch.totalVertices) vertices")
        } else {
            for drawCall in pendingDrawCalls {
                executeDrawCall(drawCall)
            }
        }
        
        pendingDrawCalls.removeAll()
    }
    
    private func executeDrawCall(_ drawCall: DrawCall) {
        // This would be called from a render encoder context
        // Implementation would depend on the active render encoder
        logger.debug("Executing draw call: \(drawCall.vertexCount) vertices")
    }
    
    private func executeBatchedDrawCalls(_ batch: BatchedDrawCall) {
        // Implementation for batched execution
        // This would involve combining draw calls into instanced draws where possible
        logger.debug("Executing batched draw calls: \(batch.drawCalls.count) calls")
    }
    
    public func createRenderCommandEncoder(
        descriptor: MTLRenderPassDescriptor,
        label: String? = nil
    ) throws -> MTLRenderCommandEncoder {
        guard let buffer = currentCommandBuffer else {
            throw CommandBuilderError.invalidCommandBuffer
        }
        
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            throw CommandBuilderError.encoderCreationFailed
        }
        
        encoder.label = label
        return encoder
    }
    
    public func createComputeCommandEncoder(label: String? = nil) throws -> MTLComputeCommandEncoder {
        guard let buffer = currentCommandBuffer else {
            throw CommandBuilderError.invalidCommandBuffer
        }
        
        guard let encoder = buffer.makeComputeCommandEncoder() else {
            throw CommandBuilderError.encoderCreationFailed
        }
        
        encoder.label = label
        return encoder
    }
    
    public func createBlitCommandEncoder(label: String? = nil) throws -> MTLBlitCommandEncoder {
        guard let buffer = currentCommandBuffer else {
            throw CommandBuilderError.invalidCommandBuffer
        }
        
        guard let encoder = buffer.makeBlitCommandEncoder() else {
            throw CommandBuilderError.encoderCreationFailed
        }
        
        encoder.label = label
        return encoder
    }
    
    public func insertDebugSignpost(_ label: String) {
        currentCommandBuffer?.pushDebugGroup(label)
        currentCommandBuffer?.popDebugGroup()
    }
    
    public func pushDebugGroup(_ label: String) {
        currentCommandBuffer?.pushDebugGroup(label)
    }
    
    public func popDebugGroup() {
        currentCommandBuffer?.popDebugGroup()
    }
    
    public func addPresentDrawable(_ drawable: MTLDrawable) {
        currentCommandBuffer?.present(drawable)
    }
    
    public func waitUntilCompleted() {
        currentCommandBuffer?.waitUntilCompleted()
    }
    
    public func waitUntilScheduled() {
        currentCommandBuffer?.waitUntilScheduled()
    }
    
    // Performance monitoring
    public func getTimingResults() -> [GPUTimer.TimingResult] {
        return timer.getTimingResults()
    }
    
    public func getAverageExecutionTime(for label: String) -> TimeInterval? {
        return timer.getAverageTime(for: label)
    }
    
    public func getPoolStatistics() -> (available: Int, active: Int) {
        return commandPool.poolStatistics
    }
    
    // Resource synchronization
    public func addResourceFence(_ resource: MTLResource) {
        // Implementation would add appropriate fences for resource synchronization
        logger.debug("Added resource fence for: \(resource)")
    }
    
    public func waitForFence(_ fence: MTLFence, before stage: MTLRenderStages) {
        // Implementation would handle fence synchronization
        logger.debug("Waiting for fence before stage: \(stage)")
    }
}

extension CommandBuilder {
    public func withCommandBuffer<T>(
        label: String? = nil,
        _ block: (MTLCommandBuffer) throws -> T
    ) throws -> T {
        let buffer = try beginCommandBuffer(label: label)
        defer {
            do {
                try commitCommandBuffer()
            } catch {
                logger.error("Failed to commit command buffer: \(error.localizedDescription)")
            }
        }
        return try block(buffer)
    }
    
    public func withRenderEncoder<T>(
        descriptor: MTLRenderPassDescriptor,
        label: String? = nil,
        _ block: (MTLRenderCommandEncoder) throws -> T
    ) throws -> T {
        let encoder = try createRenderCommandEncoder(descriptor: descriptor, label: label)
        defer { encoder.endEncoding() }
        return try block(encoder)
    }
    
    public func withComputeEncoder<T>(
        label: String? = nil,
        _ block: (MTLComputeCommandEncoder) throws -> T
    ) throws -> T {
        let encoder = try createComputeCommandEncoder(label: label)
        defer { encoder.endEncoding() }
        return try block(encoder)
    }
    
    public func withBlitEncoder<T>(
        label: String? = nil,
        _ block: (MTLBlitCommandEncoder) throws -> T
    ) throws -> T {
        let encoder = try createBlitCommandEncoder(label: label)
        defer { encoder.endEncoding() }
        return try block(encoder)
    }
    
    public func withDebugGroup<T>(
        _ label: String,
        _ block: () throws -> T
    ) rethrows -> T {
        pushDebugGroup(label)
        defer { popDebugGroup() }
        return try block()
    }
}

// MARK: - Performance Optimizations

extension CommandBuilder {
    public func optimizeForTBDR() {
        // Optimizations specific to Apple's Tile-Based Deferred Rendering
        maxBatchSize = 2000 // Higher batch sizes work well on TBDR
        batchingEnabled = true
        
        logger.info("Enabled TBDR optimizations")
    }
    
    public func optimizeForLowPower() {
        // Reduce command buffer frequency for better battery life
        maxBatchSize = 5000
        batchingEnabled = true
        enableTiming = false
        
        logger.info("Enabled low power optimizations")
    }
    
    public func setBatchingParameters(maxBatchSize: Int, enabled: Bool) {
        self.maxBatchSize = maxBatchSize
        self.batchingEnabled = enabled
        
        logger.info("Updated batching: enabled=\(enabled), maxSize=\(maxBatchSize)")
    }
}