import Metal
import Foundation
import os.log

public struct DeviceCapabilities {
    public let supportsNonUniformThreadgroups: Bool
    public let supportsReadWriteTextures: Bool
    public let supportsArgumentBuffers: Bool
    public let supportsProgrammableBlending: Bool
    public let supportsFloat32Atomics: Bool
    public let supportsQueryableSetSize: Bool
    public let supportsSIMDReduction: Bool
    public let supportsShaderDebugging: Bool
    public let supports32BitFloatFiltering: Bool
    public let supportsBCTextureCompression: Bool
    public let supportsASTCTextureCompression: Bool
    public let supportsPullModelInterpolation: Bool
    public let supportsInt64: Bool
    public let maxThreadsPerThreadgroup: MTLSize
    public let maxBufferLength: Int
    public let maxTextureSize2D: Int
    public let maxTextureSize3D: Int
    public let maxTextureCubeSize: Int
    public let recommendedMaxWorkingSetSize: Int
    public let maxArgumentBufferSamplerCount: Int
    public let maxComputeWorkgroupMemory: Int
    public let registryID: UInt64
    public let isLowPower: Bool
    public let isRemovable: Bool
    public let hasUnifiedMemory: Bool
    public let recommendedMaxWorkgroupLength: Int
    public let maxTransferRate: UInt64
    public let metalFamily: MTLGPUFamily
    
    public var memoryBandwidth: UInt64 {
        maxTransferRate
    }
    
    public var isAppleGPU: Bool {
        !isRemovable && hasUnifiedMemory
    }
    
    public var isTBDR: Bool {
        isAppleGPU
    }
    
    public var maxSimultaneousRenderTargets: Int {
        8
    }
}

public enum MetalDeviceError: Error, LocalizedError {
    case noMetalSupport
    case deviceCreationFailed
    case commandQueueCreationFailed
    case insufficientCapabilities(String)
    case deviceLost
    
    public var errorDescription: String? {
        switch self {
        case .noMetalSupport:
            return "Metal is not supported on this device"
        case .deviceCreationFailed:
            return "Failed to create Metal device"
        case .commandQueueCreationFailed:
            return "Failed to create command queue"
        case .insufficientCapabilities(let capability):
            return "Device lacks required capability: \(capability)"
        case .deviceLost:
            return "Metal device was lost"
        }
    }
}

public class MetalDevice {
    public let device: MTLDevice
    public let capabilities: DeviceCapabilities
    public let commandQueue: MTLCommandQueue
    private let logger = Logger(subsystem: "com.metalx.engine", category: "MetalDevice")
    
    private static var _shared: MetalDevice?
    private static let lock = NSLock()
    
    public static func createShared() throws -> MetalDevice {
        lock.lock()
        defer { lock.unlock() }
        
        if let shared = _shared {
            return shared
        }
        
        let device = try MetalDevice()
        _shared = device
        return device
    }
    
    public static var shared: MetalDevice? {
        lock.lock()
        defer { lock.unlock() }
        return _shared
    }
    
    public init(preferredDevice: MTLDevice? = nil) throws {
        guard let selectedDevice = preferredDevice ?? Self.selectBestDevice() else {
            logger.error("No suitable Metal device found")
            throw MetalDeviceError.noMetalSupport
        }
        
        self.device = selectedDevice
        self.capabilities = Self.detectCapabilities(for: selectedDevice)
        
        guard let queue = selectedDevice.makeCommandQueue() else {
            logger.error("Failed to create command queue for device: \(selectedDevice.name)")
            throw MetalDeviceError.commandQueueCreationFailed
        }
        
        self.commandQueue = queue
        commandQueue.label = "MetalX Main Command Queue"
        
        try validateMinimumRequirements()
        
        logger.info("Initialized Metal device: \(selectedDevice.name)")
        logger.info("Registry ID: \(selectedDevice.registryID)")
        logger.info("Has unified memory: \(selectedDevice.hasUnifiedMemory)")
        logger.info("Is low power: \(selectedDevice.isLowPower)")
        logger.info("Max working set size: \(capabilities.recommendedMaxWorkingSetSize / 1024 / 1024) MB")
    }
    
    private static func selectBestDevice() -> MTLDevice? {
        #if targetEnvironment(simulator)
        return MTLCreateSystemDefaultDevice()
        #else
        let devices = MTLCopyAllDevices()
        
        if devices.isEmpty {
            return MTLCreateSystemDefaultDevice()
        }
        
        let rankedDevices = devices.sorted { device1, device2 in
            let score1 = scoreDevice(device1)
            let score2 = scoreDevice(device2)
            return score1 > score2
        }
        
        return rankedDevices.first
        #endif
    }
    
    private static func scoreDevice(_ device: MTLDevice) -> Int {
        var score = 0
        
        if device.hasUnifiedMemory {
            score += 1000
        }
        
        if !device.isLowPower {
            score += 500
        }
        
        if !device.isRemovable {
            score += 200
        }
        
        if device.supportsFamily(.apple7) {
            score += 100
        } else if device.supportsFamily(.apple6) {
            score += 80
        } else if device.supportsFamily(.apple5) {
            score += 60
        } else if device.supportsFamily(.apple4) {
            score += 40
        }
        
        if device.supportsFeatureSet(.iOS_GPUFamily5_v1) {
            score += 50
        }
        
        if device.argumentBuffersSupport == .tier2 {
            score += 30
        } else if device.argumentBuffersSupport == .tier1 {
            score += 15
        }
        
        score += Int(device.recommendedMaxWorkingSetSize / (1024 * 1024))
        
        return score
    }
    
    private static func detectCapabilities(for device: MTLDevice) -> DeviceCapabilities {
        let metalFamily: MTLGPUFamily
        if device.supportsFamily(.apple8) {
            metalFamily = .apple8
        } else if device.supportsFamily(.apple7) {
            metalFamily = .apple7
        } else if device.supportsFamily(.apple6) {
            metalFamily = .apple6
        } else if device.supportsFamily(.apple5) {
            metalFamily = .apple5
        } else if device.supportsFamily(.apple4) {
            metalFamily = .apple4
        } else if device.supportsFamily(.apple3) {
            metalFamily = .apple3
        } else if device.supportsFamily(.apple2) {
            metalFamily = .apple2
        } else {
            metalFamily = .apple1
        }
        
        return DeviceCapabilities(
            supportsNonUniformThreadgroups: device.supportsFamily(.apple6) || device.supportsFamily(.mac2),
            supportsReadWriteTextures: device.readWriteTextureSupport != .tier1,
            supportsArgumentBuffers: device.argumentBuffersSupport != .tier1,
            supportsProgrammableBlending: device.supportsFamily(.apple6),
            supportsFloat32Atomics: device.supportsFamily(.apple8),
            supportsQueryableSetSize: device.supportsFamily(.apple6),
            supportsSIMDReduction: device.supportsFamily(.apple7),
            supportsShaderDebugging: device.supportsFamily(.apple6),
            supports32BitFloatFiltering: device.supports32BitFloatFiltering,
            supportsBCTextureCompression: device.supportsBCTextureCompression,
            supportsASTCTextureCompression: !device.supportsFamily(.mac1) && !device.supportsFamily(.mac2),
            supportsPullModelInterpolation: device.supportsFamily(.apple6),
            supportsInt64: device.supportsFamily(.apple6),
            maxThreadsPerThreadgroup: device.maxThreadsPerThreadgroup,
            maxBufferLength: device.maxBufferLength,
            maxTextureSize2D: 16384,
            maxTextureSize3D: 2048,
            maxTextureCubeSize: 16384,
            recommendedMaxWorkingSetSize: Int(device.recommendedMaxWorkingSetSize),
            maxArgumentBufferSamplerCount: device.argumentBuffersSupport == .tier2 ? 96 : 16,
            maxComputeWorkgroupMemory: 32768,
            registryID: device.registryID,
            isLowPower: device.isLowPower,
            isRemovable: device.isRemovable,
            hasUnifiedMemory: device.hasUnifiedMemory,
            recommendedMaxWorkgroupLength: Int(device.maxThreadsPerThreadgroup.width),
            maxTransferRate: device.maxTransferRate,
            metalFamily: metalFamily
        )
    }
    
    private func validateMinimumRequirements() throws {
        guard device.supportsFamily(.apple3) || device.supportsFamily(.mac1) else {
            throw MetalDeviceError.insufficientCapabilities("Requires Apple A10 GPU or equivalent")
        }
        
        guard capabilities.recommendedMaxWorkingSetSize >= 256 * 1024 * 1024 else {
            throw MetalDeviceError.insufficientCapabilities("Requires at least 256MB working set size")
        }
        
        guard capabilities.maxThreadsPerThreadgroup.width >= 32 else {
            throw MetalDeviceError.insufficientCapabilities("Requires at least 32 threads per threadgroup")
        }
    }
    
    public func makeCommandBuffer(label: String? = nil) -> MTLCommandBuffer? {
        let buffer = commandQueue.makeCommandBuffer()
        buffer?.label = label
        return buffer
    }
    
    public func makeBuffer(length: Int, options: MTLResourceOptions = []) -> MTLBuffer? {
        return device.makeBuffer(length: length, options: options)
    }
    
    public func makeBuffer<T>(array: [T], options: MTLResourceOptions = []) -> MTLBuffer? {
        return device.makeBuffer(bytes: array, length: MemoryLayout<T>.stride * array.count, options: options)
    }
    
    public func makeTexture(descriptor: MTLTextureDescriptor) -> MTLTexture? {
        return device.makeTexture(descriptor: descriptor)
    }
    
    public func makeLibrary(source: String, options: MTLCompileOptions? = nil) throws -> MTLLibrary {
        return try device.makeLibrary(source: source, options: options)
    }
    
    public func makeDefaultLibrary() -> MTLLibrary? {
        return device.makeDefaultLibrary()
    }
    
    public func makeRenderPipelineState(descriptor: MTLRenderPipelineDescriptor) throws -> MTLRenderPipelineState {
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    public func makeComputePipelineState(function: MTLFunction) throws -> MTLComputePipelineState {
        return try device.makeComputePipelineState(function: function)
    }
    
    public func makeSamplerState(descriptor: MTLSamplerDescriptor) -> MTLSamplerState? {
        return device.makeSamplerState(descriptor: descriptor)
    }
    
    public func supportsTexture(format: MTLPixelFormat, usage: MTLTextureUsage = []) -> Bool {
        guard format != .invalid else { return false }
        
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format,
            width: 1,
            height: 1,
            mipmapped: false
        )
        descriptor.usage = usage
        
        return device.makeTexture(descriptor: descriptor) != nil
    }
    
    public func optimalStorageMode(for usage: MTLResourceUsage) -> MTLStorageMode {
        #if targetEnvironment(macCatalyst) || os(macOS)
        return .managed
        #else
        if capabilities.hasUnifiedMemory {
            return .shared
        } else {
            return usage.contains(.read) ? .shared : .private
        }
        #endif
    }
    
    public func optimalResourceOptions(for usage: MTLResourceUsage) -> MTLResourceOptions {
        let storageMode = optimalStorageMode(for: usage)
        
        #if targetEnvironment(macCatalyst) || os(macOS)
        return [storageMode.resourceOptions]
        #else
        if capabilities.hasUnifiedMemory && usage.contains(.write) {
            return [storageMode.resourceOptions, .hazardTrackingModeUntracked]
        } else {
            return [storageMode.resourceOptions]
        }
        #endif
    }
    
    public var isDeviceLost: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return device.makeCommandQueue() == nil
        #endif
    }
    
    public func printCapabilities() {
        logger.info("Metal Device Capabilities:")
        logger.info("  Device: \(device.name)")
        logger.info("  Metal Family: \(capabilities.metalFamily)")
        logger.info("  Non-uniform threadgroups: \(capabilities.supportsNonUniformThreadgroups)")
        logger.info("  Read-write textures: \(capabilities.supportsReadWriteTextures)")
        logger.info("  Argument buffers: \(capabilities.supportsArgumentBuffers)")
        logger.info("  Programmable blending: \(capabilities.supportsProgrammableBlending)")
        logger.info("  32-bit float filtering: \(capabilities.supports32BitFloatFiltering)")
        logger.info("  BC texture compression: \(capabilities.supportsBCTextureCompression)")
        logger.info("  ASTC texture compression: \(capabilities.supportsASTCTextureCompression)")
        logger.info("  Max threads per threadgroup: \(capabilities.maxThreadsPerThreadgroup)")
        logger.info("  Max buffer length: \(capabilities.maxBufferLength / 1024 / 1024) MB")
        logger.info("  Working set size: \(capabilities.recommendedMaxWorkingSetSize / 1024 / 1024) MB")
        logger.info("  Is TBDR: \(capabilities.isTBDR)")
        logger.info("  Has unified memory: \(capabilities.hasUnifiedMemory)")
    }
}

extension MTLStorageMode {
    var resourceOptions: MTLResourceOptions {
        switch self {
        case .shared:
            return .storageModeShared
        case .managed:
            return .storageModeManaged
        case .private:
            return .storageModePrivate
        case .memoryless:
            return .storageModeMemoryless
        @unknown default:
            return .storageModeShared
        }
    }
}

extension MTLResourceUsage {
    static let read: MTLResourceUsage = [.read]
    static let write: MTLResourceUsage = [.write]
    static let sample: MTLResourceUsage = [.sample]
}