# MetalX Error Handling Guide

## Error Types and Recovery Strategies

### Core Error Types

```swift
// MetalX/Core/Errors/MetalXError.swift

public enum MetalXError: LocalizedError {
    // Resource Errors
    case deviceNotFound
    case outOfMemory(required: Int, available: Int)
    case textureCreationFailed(reason: String)
    case shaderCompilationFailed(shader: String, error: String)
    
    // Layer Errors
    case layerNotFound(id: UUID)
    case invalidLayerHierarchy(reason: String)
    case circularReference(parent: UUID, child: UUID)
    
    // Effect Errors
    case unsupportedEffect(name: String, device: String)
    case invalidParameter(effect: String, parameter: String, value: Any)
    case effectProcessingFailed(reason: String)
    
    // File I/O Errors
    case fileNotFound(path: String)
    case unsupportedFormat(format: String)
    case corruptedFile(path: String, reason: String)
    
    // Timeline Errors
    case invalidTimeRange(start: CMTime, end: CMTime)
    case codecNotSupported(codec: String)
    case audioVideoSyncFailure(drift: TimeInterval)
    
    // Network Errors
    case cloudSyncFailed(reason: String)
    case authenticationRequired
    case quotaExceeded(used: Int, limit: Int)
    
    public var errorDescription: String? {
        switch self {
        case .outOfMemory(let required, let available):
            return "Insufficient memory. Required: \(required.byteSize), Available: \(available.byteSize)"
        // ... other cases
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .outOfMemory:
            return "Try closing other apps or reducing the project complexity"
        case .shaderCompilationFailed:
            return "This effect may not be supported on your device. Try updating iOS."
        // ... other cases
        }
    }
}
```

### Error Recovery Patterns

```swift
// Graceful Degradation
class EffectProcessor {
    func applyEffect(_ effect: Effect, to texture: MTLTexture) throws -> MTLTexture {
        do {
            return try applyOptimalEffect(effect, to: texture)
        } catch MetalXError.unsupportedEffect {
            // Try fallback implementation
            return try applyFallbackEffect(effect, to: texture)
        } catch MetalXError.outOfMemory {
            // Reduce quality and retry
            let reduced = reduceTextureQuality(texture)
            return try applyEffect(effect, to: reduced)
        }
    }
}

// Retry with Backoff
class CloudSync {
    func syncWithRetry<T>(_ operation: () async throws -> T) async throws -> T {
        var lastError: Error?
        
        for attempt in 1...3 {
            do {
                return try await operation()
            } catch {
                lastError = error
                let delay = TimeInterval(attempt * 2) // Exponential backoff
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        throw lastError ?? MetalXError.cloudSyncFailed(reason: "Unknown")
    }
}
```

### User-Friendly Error Handling

```swift
// Error Presentation
extension MetalXError {
    var userAlert: (title: String, message: String, actions: [AlertAction]) {
        switch self {
        case .outOfMemory:
            return (
                title: "Memory Warning",
                message: "Your device is running low on memory.",
                actions: [
                    .init(title: "Reduce Quality", style: .default, handler: .reduceQuality),
                    .init(title: "Clear Cache", style: .default, handler: .clearCache),
                    .init(title: "Continue Anyway", style: .destructive, handler: .continue)
                ]
            )
        // ... other cases
        }
    }
}
```

### Debug-Only Assertions

```swift
// Development assertions that don't crash in production
@inline(__always)
func metalXAssert(_ condition: Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    #if DEBUG
    assert(condition, message, file: file, line: line)
    #else
    if !condition {
        Logger.error("Assertion failed: \(message)", file: file, line: line)
    }
    #endif
}
```

### Error Reporting

```swift
// Crash and Error Analytics
class ErrorReporter {
    static func report(_ error: Error, context: [String: Any] = [:]) {
        #if !DEBUG
        // Send to analytics service
        var errorInfo = [
            "error_type": String(describing: type(of: error)),
            "description": error.localizedDescription,
            "device": UIDevice.current.modelName,
            "ios_version": UIDevice.current.systemVersion,
            "app_version": Bundle.main.appVersion,
            "memory_available": ProcessInfo.processInfo.availableMemory
        ]
        
        errorInfo.merge(context) { _, new in new }
        
        // Log locally
        Logger.error("Error occurred", metadata: errorInfo)
        
        // Send to service (if user consented)
        if UserDefaults.standard.bool(forKey: "analytics_enabled") {
            AnalyticsService.logError(error, metadata: errorInfo)
        }
        #endif
    }
}
```