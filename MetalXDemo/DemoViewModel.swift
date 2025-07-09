import SwiftUI
import MetalX
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

@MainActor
class DemoViewModel: ObservableObject {
    // Engine and rendering
    private var renderEngine: RenderEngine?
    private var originalTexture: MTLTexture?
    
    // Published properties for UI
    @Published var isEngineReady = false
    @Published var currentTexture: MTLTexture?
    @Published var currentImageURL: URL?
    @Published var lastError: Error?
    @Published var engineStatistics: RenderEngineStatistics?
    
    // Image adjustment parameters
    @Published var brightness: Double = 0.0 {
        didSet { scheduleAdjustmentUpdate() }
    }
    
    @Published var contrast: Double = 1.0 {
        didSet { scheduleAdjustmentUpdate() }
    }
    
    @Published var saturation: Double = 1.0 {
        didSet { scheduleAdjustmentUpdate() }
    }
    
    @Published var exposure: Double = 0.0 {
        didSet { scheduleAdjustmentUpdate() }
    }
    
    // Private state
    private var adjustmentUpdateTask: Task<Void, Never>?
    private var statisticsTimer: Timer?
    private let tempDirectory = FileManager.default.temporaryDirectory
    
    init() {
        setupStatisticsTimer()
    }
    
    deinit {
        statisticsTimer?.invalidate()
        adjustmentUpdateTask?.cancel()
    }
    
    // MARK: - Engine Management
    
    func initializeEngine() async {
        do {
            let config = EngineConfiguration(
                quality: .high,
                maxMemoryUsage: 512 * 1024 * 1024, // 512MB
                enableDebugValidation: false
            )
            
            renderEngine = try RenderEngine(configuration: config)
            isEngineReady = true
            
            print("MetalX RenderEngine initialized successfully")
            
            // Update statistics immediately
            updateStatistics()
            
        } catch {
            print("Failed to initialize RenderEngine: \(error)")
            lastError = error
            isEngineReady = false
        }
    }
    
    // MARK: - Image Loading
    
    func loadImage(from data: Data) async {
        guard let engine = renderEngine else {
            lastError = DemoError.engineNotReady
            return
        }
        
        do {
            let texture = try await engine.loadTexture(
                from: data,
                identifier: "demo-image-\(Date().timeIntervalSince1970)",
                options: .default
            )
            
            originalTexture = texture
            currentTexture = texture
            
            // Save image for display
            let imageURL = await saveTextureAsImage(texture, filename: "current-image.png")
            currentImageURL = imageURL
            
            print("Loaded image: \(texture.width)x\(texture.height)")
            
        } catch {
            print("Failed to load image: \(error)")
            lastError = error
        }
    }
    
    func loadSampleImage() async {
        guard let engine = renderEngine else {
            lastError = DemoError.engineNotReady
            return
        }
        
        do {
            // Create a sample checkerboard texture
            let sampleTexture = try createSampleTexture()
            
            originalTexture = sampleTexture
            currentTexture = sampleTexture
            
            // Save image for display
            let imageURL = await saveTextureAsImage(sampleTexture, filename: "sample-image.png")
            currentImageURL = imageURL
            
            print("Loaded sample image: \(sampleTexture.width)x\(sampleTexture.height)")
            
        } catch {
            print("Failed to create sample image: \(error)")
            lastError = error
        }
    }
    
    // MARK: - Image Processing
    
    func applyAdjustments() async {
        guard let engine = renderEngine,
              let source = originalTexture else {
            return
        }
        
        do {
            var colorParams = ColorAdjustmentParams()
            colorParams.brightness = Float(brightness)
            colorParams.contrast = Float(contrast)
            colorParams.saturation = Float(saturation)
            colorParams.exposure = Float(exposure)
            
            let operations: [RenderOperation] = [.colorAdjustments(colorParams)]
            
            let processedTexture = try await engine.processImage(
                from: source,
                operations: operations
            )
            
            currentTexture = processedTexture
            
            // Update display
            let imageURL = await saveTextureAsImage(processedTexture, filename: "processed-image.png")
            currentImageURL = imageURL
            
        } catch {
            print("Failed to apply adjustments: \(error)")
            lastError = error
        }
    }
    
    func applyBlur() async {
        guard let engine = renderEngine,
              let source = currentTexture else {
            return
        }
        
        do {
            let operations: [RenderOperation] = [.blur(radius: 5.0)]
            
            let blurredTexture = try await engine.processImage(
                from: source,
                operations: operations
            )
            
            currentTexture = blurredTexture
            
            // Update display
            let imageURL = await saveTextureAsImage(blurredTexture, filename: "blurred-image.png")
            currentImageURL = imageURL
            
            print("Applied blur effect")
            
        } catch {
            print("Failed to apply blur: \(error)")
            lastError = error
        }
    }
    
    func resetAdjustments() {
        brightness = 0.0
        contrast = 1.0
        saturation = 1.0
        exposure = 0.0
        
        guard let original = originalTexture else { return }
        
        Task {
            currentTexture = original
            let imageURL = await saveTextureAsImage(original, filename: "reset-image.png")
            currentImageURL = imageURL
        }
    }
    
    func exportImage() async {
        guard let texture = currentTexture else {
            lastError = DemoError.noImageToExport
            return
        }
        
        do {
            let exportURL = await saveTextureAsImage(texture, filename: "metalx-export-\(Date().timeIntervalSince1970).png")
            
            if let url = exportURL {
                print("Image exported to: \(url)")
                // In a real app, you might save to Photos library or share
            }
            
        } catch {
            print("Failed to export image: \(error)")
            lastError = error
        }
    }
    
    // MARK: - Utility Methods
    
    func clearError() {
        lastError = nil
    }
    
    private func scheduleAdjustmentUpdate() {
        adjustmentUpdateTask?.cancel()
        
        adjustmentUpdateTask = Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms debounce
            
            if !Task.isCancelled {
                await applyAdjustments()
            }
        }
    }
    
    private func setupStatisticsTimer() {
        statisticsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateStatistics()
            }
        }
    }
    
    private func updateStatistics() {
        engineStatistics = renderEngine?.currentStatistics
    }
    
    private func createSampleTexture() throws -> MTLTexture {
        guard let engine = renderEngine else {
            throw DemoError.engineNotReady
        }
        
        let size = CGSize(width: 512, height: 512)
        let checkerSize = 64
        
        let texture = try engine.createRenderTexture(
            width: Int(size.width),
            height: Int(size.height)
        )
        
        // Create checkerboard pattern
        var pixelData = [UInt8]()
        
        for y in 0..<Int(size.height) {
            for x in 0..<Int(size.width) {
                let checkerX = x / checkerSize
                let checkerY = y / checkerSize
                let isEven = (checkerX + checkerY) % 2 == 0
                
                if isEven {
                    // Light gray
                    pixelData.append(200) // R
                    pixelData.append(200) // G
                    pixelData.append(200) // B
                    pixelData.append(255) // A
                } else {
                    // Dark gray
                    pixelData.append(100) // R
                    pixelData.append(100) // G
                    pixelData.append(100) // B
                    pixelData.append(255) // A
                }
            }
        }
        
        texture.replace(
            region: MTLRegion(
                origin: MTLOrigin(x: 0, y: 0, z: 0),
                size: MTLSize(width: Int(size.width), height: Int(size.height), depth: 1)
            ),
            mipmapLevel: 0,
            withBytes: pixelData,
            bytesPerRow: Int(size.width) * 4
        )
        
        return texture
    }
    
    private func saveTextureAsImage(_ texture: MTLTexture, filename: String) async -> URL? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let width = texture.width
                    let height = texture.height
                    let bytesPerRow = width * 4
                    let dataSize = height * bytesPerRow
                    
                    var pixelData = [UInt8](repeating: 0, count: dataSize)
                    
                    texture.getBytes(
                        &pixelData,
                        bytesPerRow: bytesPerRow,
                        from: MTLRegion(
                            origin: MTLOrigin(x: 0, y: 0, z: 0),
                            size: MTLSize(width: width, height: height, depth: 1)
                        ),
                        mipmapLevel: 0
                    )
                    
                    // Create CGImage
                    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
                    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                    
                    guard let context = CGContext(
                        data: &pixelData,
                        width: width,
                        height: height,
                        bitsPerComponent: 8,
                        bytesPerRow: bytesPerRow,
                        space: colorSpace,
                        bitmapInfo: bitmapInfo.rawValue
                    ) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    guard let cgImage = context.makeImage() else {
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    // Save to temporary directory
                    let fileURL = self.tempDirectory.appendingPathComponent(filename)
                    
                    guard let destination = CGImageDestinationCreateWithURL(
                        fileURL as CFURL,
                        UTType.png.identifier as CFString,
                        1,
                        nil
                    ) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    CGImageDestinationAddImage(destination, cgImage, nil)
                    
                    if CGImageDestinationFinalize(destination) {
                        continuation.resume(returning: fileURL)
                    } else {
                        continuation.resume(returning: nil)
                    }
                    
                } catch {
                    print("Failed to save texture as image: \(error)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

enum DemoError: Error, LocalizedError {
    case engineNotReady
    case noImageToExport
    case imageCreationFailed
    
    var errorDescription: String? {
        switch self {
        case .engineNotReady:
            return "Render engine is not ready"
        case .noImageToExport:
            return "No image available to export"
        case .imageCreationFailed:
            return "Failed to create image"
        }
    }
}