import Foundation
import QuartzCore

// Simple performance monitor for tracking FPS and render times
class PerformanceMonitor {
    private var lastFrameTime: CFTimeInterval = 0
    private var frameCount: Int = 0
    private var fpsUpdateTime: CFTimeInterval = 0
    private var currentFPS: Double = 0
    
    // Render statistics
    private(set) var averageRenderTime: Double = 0
    private var renderTimes: [Double] = []
    private let maxSamples = 60
    
    // Callback for FPS updates
    var onFPSUpdate: ((Double) -> Void)?
    
    func frameRendered() {
        let currentTime = CACurrentMediaTime()
        
        if lastFrameTime > 0 {
            let deltaTime = currentTime - lastFrameTime
            let renderTime = deltaTime * 1000 // Convert to milliseconds
            
            // Track render times
            renderTimes.append(renderTime)
            if renderTimes.count > maxSamples {
                renderTimes.removeFirst()
            }
            
            // Calculate average
            averageRenderTime = renderTimes.reduce(0, +) / Double(renderTimes.count)
        }
        
        lastFrameTime = currentTime
        frameCount += 1
        
        // Update FPS every second
        if currentTime - fpsUpdateTime >= 1.0 {
            currentFPS = Double(frameCount) / (currentTime - fpsUpdateTime)
            frameCount = 0
            fpsUpdateTime = currentTime
            
            onFPSUpdate?(currentFPS)
        }
    }
    
    func reset() {
        lastFrameTime = 0
        frameCount = 0
        fpsUpdateTime = CACurrentMediaTime()
        currentFPS = 0
        renderTimes.removeAll()
        averageRenderTime = 0
    }
    
    var fps: Double {
        return currentFPS
    }
    
    var isPerformingWell: Bool {
        // Consider performance good if we're maintaining close to 60 FPS
        // and average render time is under 16ms (for 60fps)
        return currentFPS > 55 && averageRenderTime < 16
    }
}