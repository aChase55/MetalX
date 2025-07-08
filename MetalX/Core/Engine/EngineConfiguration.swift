import Metal
import Foundation

public enum QualityLevel: Int, CaseIterable {
    case low = 0
    case medium = 1
    case high = 2
    case ultra = 3
    
    public var description: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .ultra: return "Ultra"
        }
    }
    
    public var maxTextureSize: Int {
        switch self {
        case .low: return 2048
        case .medium: return 4096
        case .high: return 8192
        case .ultra: return 16384
        }
    }
    
    public var maxLayers: Int {
        switch self {
        case .low: return 25
        case .medium: return 50
        case .high: return 100
        case .ultra: return 200
        }
    }
    
    public var enableMipmaps: Bool {
        switch self {
        case .low: return false
        case .medium: return true
        case .high: return true
        case .ultra: return true
        }
    }
    
    public var maxSampleCount: Int {
        switch self {
        case .low: return 1
        case .medium: return 2
        case .high: return 4
        case .ultra: return 8
        }
    }
}

public enum ThermalState: Int {
    case nominal = 0
    case fair = 1
    case serious = 2
    case critical = 3
    
    public var qualityReduction: Float {
        switch self {
        case .nominal: return 1.0
        case .fair: return 0.8
        case .serious: return 0.6
        case .critical: return 0.4
        }
    }
}

public enum MemoryPressure: Int {
    case normal = 0
    case warning = 1
    case urgent = 2
    case critical = 3
    
    public var cacheReduction: Float {
        switch self {
        case .normal: return 1.0
        case .warning: return 0.7
        case .urgent: return 0.4
        case .critical: return 0.2
        }
    }
}

public enum ProcessingMode {
    case realtime
    case highQuality
    case export
    case background
    
    public var prioritizeFramerate: Bool {
        switch self {
        case .realtime: return true
        case .highQuality: return false
        case .export: return false
        case .background: return false
        }
    }
    
    public var maxFrameTime: TimeInterval {
        switch self {
        case .realtime: return 1.0 / 60.0
        case .highQuality: return 1.0 / 30.0
        case .export: return .infinity
        case .background: return 1.0 / 10.0
        }
    }
}

public struct EngineConfiguration {
    public var qualityLevel: QualityLevel
    public var processingMode: ProcessingMode
    public var enableDebugCapture: Bool
    public var enableValidation: Bool
    public var enableShaderDebugging: Bool
    public var enableTiming: Bool
    public var enableMemoryTracking: Bool
    public var maxMemoryUsage: Int
    public var textureCompressionEnabled: Bool
    public var multipleCommandQueues: Bool
    public var adaptiveQuality: Bool
    public var thermalThrottling: Bool
    public var memoryPressureHandling: Bool
    public var backgroundProcessing: Bool
    public var preferenceLowPower: Bool
    public var enableAsyncShaderCompilation: Bool
    public var cachePipelineStates: Bool
    public var enableMTLHeaps: Bool
    public var useUnifiedMemory: Bool
    public var maxConcurrentOperations: Int
    public var preferredPixelFormat: MTLPixelFormat
    public var enableHDR: Bool
    public var colorSpace: String
    
    public init() {
        self.qualityLevel = .medium
        self.processingMode = .realtime
        self.enableDebugCapture = false
        self.enableValidation = false
        self.enableShaderDebugging = false
        self.enableTiming = false
        self.enableMemoryTracking = false
        self.maxMemoryUsage = 512 * 1024 * 1024 // 512 MB default
        self.textureCompressionEnabled = true
        self.multipleCommandQueues = true
        self.adaptiveQuality = true
        self.thermalThrottling = true
        self.memoryPressureHandling = true
        self.backgroundProcessing = false
        self.preferenceLowPower = false
        self.enableAsyncShaderCompilation = true
        self.cachePipelineStates = true
        self.enableMTLHeaps = true
        self.useUnifiedMemory = true
        self.maxConcurrentOperations = 4
        self.preferredPixelFormat = .bgra8Unorm
        self.enableHDR = false
        self.colorSpace = "sRGB"
    }
    
    public static func preset(for device: MTLDevice) -> EngineConfiguration {
        var config = EngineConfiguration()
        
        if device.supportsFamily(.apple8) {
            config.qualityLevel = .ultra
            config.maxMemoryUsage = 2 * 1024 * 1024 * 1024 // 2GB
            config.maxConcurrentOperations = 8
            config.enableHDR = true
        } else if device.supportsFamily(.apple7) {
            config.qualityLevel = .high
            config.maxMemoryUsage = 1536 * 1024 * 1024 // 1.5GB
            config.maxConcurrentOperations = 6
        } else if device.supportsFamily(.apple6) {
            config.qualityLevel = .high
            config.maxMemoryUsage = 1024 * 1024 * 1024 // 1GB
            config.maxConcurrentOperations = 4
        } else if device.supportsFamily(.apple5) {
            config.qualityLevel = .medium
            config.maxMemoryUsage = 768 * 1024 * 1024 // 768MB
            config.maxConcurrentOperations = 4
        } else if device.supportsFamily(.apple4) {
            config.qualityLevel = .medium
            config.maxMemoryUsage = 512 * 1024 * 1024 // 512MB
            config.maxConcurrentOperations = 2
            config.textureCompressionEnabled = true
        } else {
            config.qualityLevel = .low
            config.maxMemoryUsage = 256 * 1024 * 1024 // 256MB
            config.maxConcurrentOperations = 2
            config.textureCompressionEnabled = true
            config.adaptiveQuality = true
        }
        
        if device.isLowPower {
            config.preferenceLowPower = true
            config.thermalThrottling = true
            config.qualityLevel = QualityLevel(rawValue: max(0, config.qualityLevel.rawValue - 1)) ?? .low
        }
        
        #if targetEnvironment(simulator)
        config.qualityLevel = .low
        config.maxMemoryUsage = 128 * 1024 * 1024 // 128MB
        config.enableValidation = true
        config.textureCompressionEnabled = false
        config.enableMTLHeaps = false
        #endif
        
        #if DEBUG
        config.enableValidation = true
        config.enableTiming = true
        config.enableMemoryTracking = true
        #endif
        
        return config
    }
    
    public static var preview: EngineConfiguration {
        var config = EngineConfiguration()
        config.processingMode = .realtime
        config.qualityLevel = .medium
        config.adaptiveQuality = true
        config.thermalThrottling = true
        config.backgroundProcessing = false
        return config
    }
    
    public static var export: EngineConfiguration {
        var config = EngineConfiguration()
        config.processingMode = .export
        config.qualityLevel = .ultra
        config.adaptiveQuality = false
        config.thermalThrottling = false
        config.backgroundProcessing = true
        config.maxConcurrentOperations = 1 // Single threaded for deterministic results
        return config
    }
    
    public static var lowPower: EngineConfiguration {
        var config = EngineConfiguration()
        config.qualityLevel = .low
        config.processingMode = .background
        config.preferenceLowPower = true
        config.thermalThrottling = true
        config.adaptiveQuality = true
        config.maxMemoryUsage = 128 * 1024 * 1024 // 128MB
        return config
    }
    
    public mutating func adaptToThermalState(_ thermalState: ThermalState) {
        guard thermalThrottling else { return }
        
        let reduction = thermalState.qualityReduction
        if reduction < 1.0 {
            let currentLevel = qualityLevel.rawValue
            let newLevel = max(0, Int(Float(currentLevel) * reduction))
            qualityLevel = QualityLevel(rawValue: newLevel) ?? .low
            
            if thermalState == .critical {
                processingMode = .background
                maxConcurrentOperations = 1
            } else if thermalState == .serious {
                maxConcurrentOperations = max(1, maxConcurrentOperations / 2)
            }
        }
    }
    
    public mutating func adaptToMemoryPressure(_ pressure: MemoryPressure) {
        guard memoryPressureHandling else { return }
        
        let reduction = pressure.cacheReduction
        if reduction < 1.0 {
            maxMemoryUsage = Int(Float(maxMemoryUsage) * reduction)
            
            if pressure == .critical {
                qualityLevel = .low
                enableMTLHeaps = false
                cachePipelineStates = false
            } else if pressure == .urgent {
                let currentLevel = qualityLevel.rawValue
                let newLevel = max(0, currentLevel - 1)
                qualityLevel = QualityLevel(rawValue: newLevel) ?? .low
            }
        }
    }
    
    public func validate() -> [String] {
        var warnings: [String] = []
        
        if maxMemoryUsage < 64 * 1024 * 1024 {
            warnings.append("Memory usage is very low (\(maxMemoryUsage / 1024 / 1024)MB), may cause performance issues")
        }
        
        if maxConcurrentOperations > 8 {
            warnings.append("High concurrent operation count (\(maxConcurrentOperations)) may cause context switching overhead")
        }
        
        if qualityLevel == .ultra && processingMode == .realtime {
            warnings.append("Ultra quality with realtime mode may not maintain 60fps")
        }
        
        if enableValidation && !enableDebugCapture {
            warnings.append("Validation is enabled but debug capture is disabled")
        }
        
        return warnings
    }
    
    public var effectiveQualityLevel: QualityLevel {
        if adaptiveQuality {
            return qualityLevel
        } else {
            return qualityLevel
        }
    }
    
    public var shouldUseTextureCompression: Bool {
        return textureCompressionEnabled && qualityLevel != .ultra
    }
    
    public var optimalSampleCount: Int {
        let maxSamples = qualityLevel.maxSampleCount
        return processingMode.prioritizeFramerate ? min(2, maxSamples) : maxSamples
    }
    
    public var targetFrameTime: TimeInterval {
        return processingMode.maxFrameTime
    }
    
    public var memoryBudgetMB: Int {
        return maxMemoryUsage / 1024 / 1024
    }
    
    public func description() -> String {
        return """
        Engine Configuration:
          Quality Level: \(qualityLevel.description)
          Processing Mode: \(processingMode)
          Memory Budget: \(memoryBudgetMB)MB
          Max Texture Size: \(qualityLevel.maxTextureSize)px
          Max Layers: \(qualityLevel.maxLayers)
          Sample Count: \(optimalSampleCount)
          Adaptive Quality: \(adaptiveQuality)
          Thermal Throttling: \(thermalThrottling)
          Debug Features: Validation=\(enableValidation), Timing=\(enableTiming)
        """
    }
}

public extension EngineConfiguration {
    mutating func enableDevelopmentMode() {
        enableDebugCapture = true
        enableValidation = true
        enableShaderDebugging = true
        enableTiming = true
        enableMemoryTracking = true
        cachePipelineStates = false
    }
    
    mutating func enableProductionMode() {
        enableDebugCapture = false
        enableValidation = false
        enableShaderDebugging = false
        enableTiming = false
        enableMemoryTracking = false
        cachePipelineStates = true
        enableAsyncShaderCompilation = true
    }
    
    mutating func optimizeForBattery() {
        preferenceLowPower = true
        thermalThrottling = true
        adaptiveQuality = true
        qualityLevel = QualityLevel(rawValue: max(0, qualityLevel.rawValue - 1)) ?? .low
        processingMode = .background
    }
    
    mutating func optimizeForPerformance() {
        preferenceLowPower = false
        thermalThrottling = false
        adaptiveQuality = false
        qualityLevel = .ultra
        processingMode = .realtime
        maxConcurrentOperations = 8
    }
}