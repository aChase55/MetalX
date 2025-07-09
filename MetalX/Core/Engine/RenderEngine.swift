import Metal
import Foundation
import CoreGraphics
import UIKit
import simd
import os.log

public enum RenderEngineError: Error, LocalizedError {
    case deviceInitializationFailed
    case renderContextCreationFailed
    case textureAllocationFailed
    case renderPassSetupFailed
    case shaderCompilationFailed
    case invalidRenderState
    case memoryPressureCritical
    case thermalStateUnsupported
    case renderTimeoutExpired
    case resourceNotFound(String)
    
    public var errorDescription: String? {
        switch self {
        case .deviceInitializationFailed:
            return "Failed to initialize Metal device"
        case .renderContextCreationFailed:
            return "Failed to create render context"
        case .textureAllocationFailed:
            return "Failed to allocate texture memory"
        case .renderPassSetupFailed:
            return "Failed to setup render pass"
        case .shaderCompilationFailed:
            return "Shader compilation failed"
        case .invalidRenderState:
            return "Invalid rendering state"
        case .memoryPressureCritical:
            return "Critical memory pressure, cannot render"
        case .thermalStateUnsupported:
            return "Device thermal state too high for rendering"
        case .renderTimeoutExpired:
            return "Render operation timed out"
        case .resourceNotFound(let resource):
            return "Resource not found: \(resource)"
        }
    }
}

public struct RenderEngineStatistics {
    public let framesRendered: Int
    public let averageFrameTime: TimeInterval
    public let currentFrameRate: Double
    public let memoryUsage: Int
    public let gpuUtilization: Double
    public let thermalState: ProcessInfo.ThermalState
    public let memoryPressure: MemoryPressure
    public let droppedFrames: Int
    public let renderErrors: Int
    
    public var isPerformingWell: Bool {
        return currentFrameRate >= 30.0 && 
               thermalState.rawValue <= ProcessInfo.ThermalState.fair.rawValue &&
               memoryPressure.rawValue <= MemoryPressure.warning.rawValue
    }
}

public protocol RenderEngineDelegate: AnyObject {
    func renderEngine(_ engine: RenderEngine, didEncounterError error: Error)
    func renderEngine(_ engine: RenderEngine, didUpdateStatistics statistics: RenderEngineStatistics)
    func renderEngine(_ engine: RenderEngine, willBeginRenderPass pass: String)
    func renderEngine(_ engine: RenderEngine, didCompleteRenderPass pass: String, duration: TimeInterval)
    func renderEngine(_ engine: RenderEngine, didDetectMemoryPressure pressure: MemoryPressure)
}

public extension RenderEngineDelegate {
    func renderEngine(_ engine: RenderEngine, didEncounterError error: Error) {}
    func renderEngine(_ engine: RenderEngine, didUpdateStatistics statistics: RenderEngineStatistics) {}
    func renderEngine(_ engine: RenderEngine, willBeginRenderPass pass: String) {}
    func renderEngine(_ engine: RenderEngine, didCompleteRenderPass pass: String, duration: TimeInterval) {}
    func renderEngine(_ engine: RenderEngine, didDetectMemoryPressure pressure: MemoryPressure) {}
}

public class RenderEngine {
    // Core components
    public let device: MetalDevice
    private let renderContext: RenderContext
    private let textureCache: TextureCache
    private let textureLoader: TextureLoader
    private let texturePool: TexturePool
    private let commandBuilder: CommandBuilder
    private let shaderLibrary: ShaderLibrary
    private let pipelineStateCache: PipelineStateCache
    
    // Engine state
    public weak var delegate: RenderEngineDelegate?
    private let logger = Logger(subsystem: "com.metalx.engine", category: "RenderEngine")
    private let engineQueue = DispatchQueue(label: "com.metalx.engine.render", qos: .userInteractive)
    
    // Performance tracking
    private var statistics = RenderEngineStatistics(
        framesRendered: 0,
        averageFrameTime: 0.0,
        currentFrameRate: 0.0,
        memoryUsage: 0,
        gpuUtilization: 0.0,
        thermalState: .nominal,
        memoryPressure: .normal,
        droppedFrames: 0,
        renderErrors: 0
    )
    
    private var frameTimeHistory: [TimeInterval] = []
    private var lastFrameTime: CFTimeInterval = 0
    private var lastStatisticsUpdate: CFTimeInterval = 0
    private let maxFrameTimeHistory = 60
    private let statisticsUpdateInterval: CFTimeInterval = 1.0
    
    // Resource management
    private var activeRenderPasses: Set<String> = []
    private var isRendering: Bool = false
    private var renderTimeoutTimer: Timer?
    private let maxRenderTimeout: TimeInterval = 5.0
    
    public var isInitialized: Bool {
        return true // For now, assume initialized if constructor succeeded
    }
    
    public var currentStatistics: RenderEngineStatistics {
        return statistics
    }
    
    // MARK: - Initialization
    
    public init(configuration: EngineConfiguration = EngineConfiguration()) throws {
        logger.info("Initializing MetalX RenderEngine")
        
        // Initialize core Metal device
        do {
            self.device = try MetalDevice()
        } catch {
            logger.error("Failed to initialize Metal device: \(error.localizedDescription)")
            throw RenderEngineError.deviceInitializationFailed
        }
        
        // Initialize resource management
        let heapSize = 256 * 1024 * 1024 // 256MB heap
        
        // Heaps must use .private storage mode
        let resourceHeap = try ResourceHeap(device: device, size: heapSize, storageMode: .private)
        
        // On simulator, don't use heap for texture allocation
        #if targetEnvironment(simulator)
        self.texturePool = TexturePool(device: device, resourceHeap: nil)
        #else
        self.texturePool = TexturePool(device: device, resourceHeap: resourceHeap)
        #endif
        
        // Initialize pipeline components
        self.shaderLibrary = ShaderLibrary(device: device)
        self.pipelineStateCache = PipelineStateCache(device: device)
        
        // Initialize texture management
        self.textureLoader = TextureLoader(device: device, texturePool: texturePool)
        self.textureCache = TextureCache(device: device, textureLoader: textureLoader)
        
        // Initialize command management
        self.commandBuilder = CommandBuilder(device: device)
        
        // Initialize render context
        self.renderContext = RenderContext(device: device)
        
        // Setup monitoring - disabled, causing crashes
        // setupPerformanceMonitoring()
        // setupMemoryPressureMonitoring()
        
        logger.info("RenderEngine initialized successfully")
        logSystemCapabilities()
    }
    
    deinit {
        cleanup()
        logger.info("RenderEngine deinitialized")
    }
    
    // MARK: - Core Rendering Methods
    
    public func render(texture: MTLTexture, to destination: MTLTexture) async throws {
        try await performRender(passName: "TextureCopy") {
            try await self.renderTexture(texture, to: destination)
        }
    }
    
    public func render(texture: MTLTexture, to destination: MTLTexture, transform: simd_float4x4) async throws {
        try await performRender(passName: "TextureTransform") {
            try await self.renderTextureWithTransform(texture, to: destination, transform: transform)
        }
    }
    
    public func processImage(from sourceTexture: MTLTexture, operations: [RenderOperation]) async throws -> MTLTexture {
        return try await performRender(passName: "ImageProcessing") {
            return try await self.executeRenderOperations(sourceTexture, operations: operations)
        }
    }
    
    public func createRenderTexture(width: Int, height: Int, pixelFormat: MTLPixelFormat = .rgba8Unorm) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = device.optimalStorageMode(for: [.read, .write])
        
        return try texturePool.acquireTexture(descriptor: descriptor, priority: .high)
    }
    
    // MARK: - Texture Management
    
    public func loadTexture(from url: URL, options: TextureLoadOptions = .default) async throws -> MTLTexture {
        return try await textureCache.getTexture(from: url, options: options)
    }
    
    public func loadTexture(from data: Data, identifier: String, options: TextureLoadOptions = .default) async throws -> MTLTexture {
        return try await textureCache.getTexture(from: data, identifier: identifier, options: options)
    }
    
    public func preloadTextures(urls: [URL], priority: TexturePriority = .normal) {
        for url in urls {
            textureCache.preloadTexture(from: url, priority: priority)
        }
    }
    
    public func clearTextureCache(priority: TexturePriority? = nil) {
        textureCache.clearCache(priority: priority)
    }
    
    // MARK: - Performance and Diagnostics
    
    public func setMemoryPressure(_ pressure: MemoryPressure) {
        textureCache.setMemoryPressure(pressure)
        texturePool.setMemoryPressure(pressure)
        
        if pressure.rawValue > MemoryPressure.warning.rawValue {
            delegate?.renderEngine(self, didDetectMemoryPressure: pressure)
        }
    }
    
    public func performMaintenanceCleanup() {
        engineQueue.async {
            self.logger.debug("Performing maintenance cleanup")
            
            // Cleanup unused resources
            self.texturePool.performMaintenance()
            self.pipelineStateCache.performMaintenance()
            
            // Memory pressure tracking removed - was causing crashes
        }
    }
    
    public func captureGPUFrame(label: String = "MetalX Capture") throws {
        guard device.capabilities.supportsGPUCapture else {
            logger.warning("GPU capture not supported on this device")
            return
        }
        
        let captureManager = MTLCaptureManager.shared()
        let captureDescriptor = MTLCaptureDescriptor()
        captureDescriptor.captureObject = device.device
        captureDescriptor.destination = .developerTools
        
        try captureManager.startCapture(with: captureDescriptor)
        logger.info("Started GPU frame capture: \(label)")
    }
    
    // MARK: - Private Implementation
    
    private func performRender<T>(passName: String, operation: () async throws -> T) async throws -> T {
        let startTime = CACurrentMediaTime()
        
        // Check system state
        try validateRenderingState()
        
        // Setup render timeout
        setupRenderTimeout()
        
        // Track active render pass
        activeRenderPasses.insert(passName)
        isRendering = true
        
        delegate?.renderEngine(self, willBeginRenderPass: passName)
        
        defer {
            // Cleanup
            activeRenderPasses.remove(passName)
            isRendering = activeRenderPasses.count > 0
            cancelRenderTimeout()
            
            let duration = CACurrentMediaTime() - startTime
            delegate?.renderEngine(self, didCompleteRenderPass: passName, duration: duration)
            updateFrameStatistics(frameTime: duration)
        }
        
        do {
            let result = try await operation()
            return result
        } catch {
            logger.error("Render pass \(passName) failed: \(error.localizedDescription)")
            updateErrorStatistics()
            delegate?.renderEngine(self, didEncounterError: error)
            throw error
        }
    }
    
    private func renderTexture(_ source: MTLTexture, to destination: MTLTexture) async throws {
        // TODO: Implement texture copy using correct RenderContext API
        logger.warning("Texture copy not yet implemented")
    }
    
    private func renderTextureWithTransform(_ source: MTLTexture, to destination: MTLTexture, transform: simd_float4x4) async throws {
        // TODO: Implement texture transform using correct RenderContext API
        logger.warning("Texture transform not yet implemented")
    }
    
    private func executeRenderOperations(_ sourceTexture: MTLTexture, operations: [RenderOperation]) async throws -> MTLTexture {
        guard !operations.isEmpty else {
            return sourceTexture
        }
        
        var currentTexture = sourceTexture
        let needsIntermediateTexture = operations.count > 1
        
        for (index, operation) in operations.enumerated() {
            let isLastOperation = index == operations.count - 1
            
            let outputTexture: MTLTexture
            if isLastOperation && !needsIntermediateTexture {
                outputTexture = currentTexture
            } else {
                outputTexture = try createRenderTexture(
                    width: currentTexture.width,
                    height: currentTexture.height,
                    pixelFormat: currentTexture.pixelFormat
                )
            }
            
            try await executeRenderOperation(operation, input: currentTexture, output: outputTexture)
            
            if ObjectIdentifier(currentTexture) != ObjectIdentifier(sourceTexture) {
                texturePool.returnTexture(currentTexture)
            }
            
            currentTexture = outputTexture
        }
        
        return currentTexture
    }
    
    private func executeRenderOperation(_ operation: RenderOperation, input: MTLTexture, output: MTLTexture) async throws {
        switch operation {
        case .colorAdjustments(let params):
            try await applyColorAdjustments(input: input, output: output, parameters: params)
        case .blur(let radius):
            try await applyBlur(input: input, output: output, radius: radius)
        case .blend(let overlay, let mode, let opacity):
            try await applyBlend(base: input, overlay: overlay, output: output, mode: mode, opacity: opacity)
        }
    }
    
    private func applyColorAdjustments(input: MTLTexture, output: MTLTexture, parameters: ColorAdjustmentParams) async throws {
        // TODO: Implement color adjustments using correct RenderContext API
        logger.warning("Color adjustments not yet implemented")
    }
    
    private func applyBlur(input: MTLTexture, output: MTLTexture, radius: Float) async throws {
        // TODO: Implement blur using correct RenderContext API
        logger.warning("Blur not yet implemented")
    }
    
    private func applyBlend(base: MTLTexture, overlay: MTLTexture, output: MTLTexture, mode: BlendMode, opacity: Float) async throws {
        // TODO: Implement blend using correct RenderContext API
        logger.warning("Blend not yet implemented")
    }
    
    // MARK: - System State Validation
    
    private func validateRenderingState() throws {
        // Check thermal state
        let thermalState = ProcessInfo.processInfo.thermalState
        if thermalState.rawValue > ProcessInfo.ThermalState.serious.rawValue {
            throw RenderEngineError.thermalStateUnsupported
        }
        
        // Check memory pressure
        if statistics.memoryPressure == .critical {
            throw RenderEngineError.memoryPressureCritical
        }
        
        // Basic device validation
        // For now, assume devices are properly initialized
    }
    
    private func setupRenderTimeout() {
        renderTimeoutTimer = Timer.scheduledTimer(withTimeInterval: maxRenderTimeout, repeats: false) { [weak self] _ in
            self?.handleRenderTimeout()
        }
    }
    
    private func cancelRenderTimeout() {
        renderTimeoutTimer?.invalidate()
        renderTimeoutTimer = nil
    }
    
    private func handleRenderTimeout() {
        logger.error("Render operation timed out after \(self.maxRenderTimeout)s")
        delegate?.renderEngine(self, didEncounterError: RenderEngineError.renderTimeoutExpired)
    }
    
    // MARK: - Performance Monitoring
    
    private func setupPerformanceMonitoring() {
        Timer.scheduledTimer(withTimeInterval: statisticsUpdateInterval, repeats: true) { [weak self] _ in
            self?.updateStatistics()
        }
    }
    
    private func setupMemoryPressureMonitoring() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryWarning()
        }
    }
    
    private func updateFrameStatistics(frameTime: TimeInterval) {
        frameTimeHistory.append(frameTime)
        if frameTimeHistory.count > maxFrameTimeHistory {
            frameTimeHistory.removeFirst()
        }
        
        lastFrameTime = CACurrentMediaTime()
    }
    
    private func updateErrorStatistics() {
        statistics = RenderEngineStatistics(
            framesRendered: statistics.framesRendered,
            averageFrameTime: statistics.averageFrameTime,
            currentFrameRate: statistics.currentFrameRate,
            memoryUsage: statistics.memoryUsage,
            gpuUtilization: statistics.gpuUtilization,
            thermalState: statistics.thermalState,
            memoryPressure: statistics.memoryPressure,
            droppedFrames: statistics.droppedFrames,
            renderErrors: statistics.renderErrors + 1
        )
    }
    
    private func updateStatistics() {
        let now = CACurrentMediaTime()
        if now - lastStatisticsUpdate < statisticsUpdateInterval {
            return
        }
        
        let averageFrameTime = frameTimeHistory.isEmpty ? 0 : frameTimeHistory.reduce(0, +) / Double(frameTimeHistory.count)
        let currentFrameRate = averageFrameTime > 0 ? 1.0 / averageFrameTime : 0
        let memoryUsage = textureCache.memoryUsage + texturePool.memoryUsage
        let thermalState = ProcessInfo.processInfo.thermalState
        let memoryPressure = calculateMemoryPressure(usage: memoryUsage, total: Int(ProcessInfo.processInfo.physicalMemory))
        
        statistics = RenderEngineStatistics(
            framesRendered: statistics.framesRendered + frameTimeHistory.count,
            averageFrameTime: averageFrameTime,
            currentFrameRate: currentFrameRate,
            memoryUsage: memoryUsage,
            gpuUtilization: 0.0, // Would need Metal Performance Shaders to calculate
            thermalState: thermalState,
            memoryPressure: memoryPressure,
            droppedFrames: statistics.droppedFrames,
            renderErrors: statistics.renderErrors
        )
        
        frameTimeHistory.removeAll()
        lastStatisticsUpdate = now
        
        delegate?.renderEngine(self, didUpdateStatistics: statistics)
    }
    
    private func calculateMemoryPressure(usage: Int, total: Int) -> MemoryPressure {
        let utilization = Double(usage) / Double(total)
        
        if utilization > 0.9 { return .critical }
        if utilization > 0.75 { return .urgent }
        if utilization > 0.6 { return .warning }
        return .normal
    }
    
    private func handleMemoryWarning() {
        logger.warning("Received memory warning")
        setMemoryPressure(.urgent)
        
        // Aggressive cleanup
        clearTextureCache(priority: .low)
        clearTextureCache(priority: .normal)
        texturePool.performMaintenance()
        pipelineStateCache.performMaintenance()
    }
    
    private func cleanup() {
        cancelRenderTimeout()
        NotificationCenter.default.removeObserver(self)
    }
    
    private func logSystemCapabilities() {
        let caps = device.capabilities
        let message = """
        System Capabilities:
          GPU: \(caps.metalFamily)
          Max Texture Size: \(caps.maxTextureSize)
          Supports Compute: \(caps.supportsCompute)
          Supports TBDR: \(caps.supportsTileBasedDeferredRendering)
          Max Working Set: \(caps.recommendedMaxWorkingSetSize / 1024 / 1024)MB
          Supports GPU Capture: \(caps.supportsGPUCapture)
        """
        logger.info("\(message)")
    }
}

// MARK: - Supporting Types

public enum RenderOperation {
    case colorAdjustments(ColorAdjustmentParams)
    case blur(radius: Float)
    case blend(overlay: MTLTexture, mode: BlendMode, opacity: Float)
}

public enum BlendMode: String, CaseIterable {
    case normal
    case multiply
    case screen
    case overlay
    case softLight = "soft_light"
    case hardLight = "hard_light"
    case colorDodge = "color_dodge"
    case colorBurn = "color_burn"
    case darken
    case lighten
    case difference
    case exclusion
}

public struct ColorAdjustmentParams {
    public var brightness: Float = 0.0
    public var contrast: Float = 1.0
    public var saturation: Float = 1.0
    public var hue: Float = 0.0
    public var gamma: Float = 1.0
    public var exposure: Float = 0.0
    public var highlights: Float = 1.0
    public var shadows: Float = 1.0
    public var whites: Float = 0.0
    public var blacks: Float = 0.0
    public var clarity: Float = 0.0
    public var vibrance: Float = 1.0
    
    public init() {}
}

public struct TransformParams {
    public var scale: SIMD2<Float>
    public var translate: SIMD2<Float>
    public var rotation: Float
    public var anchor: SIMD2<Float>
    public var skew: SIMD2<Float>
    
    public init(scale: SIMD2<Float>, translate: SIMD2<Float>, rotation: Float, anchor: SIMD2<Float>, skew: SIMD2<Float>) {
        self.scale = scale
        self.translate = translate
        self.rotation = rotation
        self.anchor = anchor
        self.skew = skew
    }
}