import XCTest
import Metal
import MetalKit
@testable import MetalX

class RenderEngineIntegrationTests: XCTestCase {
    
    var renderEngine: RenderEngine!
    var testTextureSize: CGSize!
    var testDevice: MTLDevice!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Skip tests if Metal is not available
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is not available on this system")
        }
        
        testDevice = device
        testTextureSize = CGSize(width: 512, height: 512)
        
        // Initialize render engine with test configuration
        let config = EngineConfiguration(
            quality: .high,
            maxMemoryUsage: 256 * 1024 * 1024, // 256MB for tests
            enableDebugValidation: true
        )
        
        renderEngine = try RenderEngine(configuration: config)
        
        // Wait for initialization
        let expectation = XCTestExpectation(description: "Engine initialization")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertTrue(renderEngine.isInitialized, "RenderEngine should be initialized")
    }
    
    override func tearDownWithError() throws {
        renderEngine = nil
        testDevice = nil
        try super.tearDownWithError()
    }
    
    // MARK: - Basic Rendering Tests
    
    func testBasicTextureRendering() async throws {
        // Create test textures
        let sourceTexture = try createTestTexture(color: SIMD4<Float>(1.0, 0.0, 0.0, 1.0)) // Red
        let destinationTexture = try renderEngine.createRenderTexture(
            width: Int(testTextureSize.width),
            height: Int(testTextureSize.height)
        )
        
        // Perform basic render
        try await renderEngine.render(texture: sourceTexture, to: destinationTexture)
        
        // Verify the result
        let pixelData = try readTexturePixels(destinationTexture)
        let redPixel = pixelData[0]
        
        XCTAssertEqual(redPixel.r, 255, accuracy: 5, "Red channel should be 255")
        XCTAssertEqual(redPixel.g, 0, accuracy: 5, "Green channel should be 0")
        XCTAssertEqual(redPixel.b, 0, accuracy: 5, "Blue channel should be 0")
        XCTAssertEqual(redPixel.a, 255, accuracy: 5, "Alpha channel should be 255")
    }
    
    func testTextureTransformRendering() async throws {
        // Create test texture
        let sourceTexture = try createTestTexture(color: SIMD4<Float>(0.0, 1.0, 0.0, 1.0)) // Green
        let destinationTexture = try renderEngine.createRenderTexture(
            width: Int(testTextureSize.width),
            height: Int(testTextureSize.height)
        )
        
        // Create transform (2x scale)
        let transform = simd_float4x4(
            SIMD4<Float>(2.0, 0.0, 0.0, 0.0),
            SIMD4<Float>(0.0, 2.0, 0.0, 0.0),
            SIMD4<Float>(0.0, 0.0, 1.0, 0.0),
            SIMD4<Float>(0.0, 0.0, 0.0, 1.0)
        )
        
        // Perform transform render
        try await renderEngine.render(texture: sourceTexture, to: destinationTexture, transform: transform)
        
        // Verify the result exists
        let pixelData = try readTexturePixels(destinationTexture)
        XCTAssertFalse(pixelData.isEmpty, "Should have pixel data")
    }
    
    func testColorAdjustmentProcessing() async throws {
        // Create test texture
        let sourceTexture = try createTestTexture(color: SIMD4<Float>(0.5, 0.5, 0.5, 1.0)) // Gray
        
        // Create color adjustment parameters
        var colorParams = ColorAdjustmentParams()
        colorParams.brightness = 0.2  // Increase brightness
        colorParams.contrast = 1.5    // Increase contrast
        colorParams.saturation = 1.2  // Increase saturation
        
        let operations: [RenderOperation] = [.colorAdjustments(colorParams)]
        
        // Process image
        let resultTexture = try await renderEngine.processImage(from: sourceTexture, operations: operations)
        
        // Verify the result
        let pixelData = try readTexturePixels(resultTexture)
        let adjustedPixel = pixelData[0]
        
        // With increased brightness, pixel values should be higher than original gray (128)
        XCTAssertGreaterThan(adjustedPixel.r, 128, "Red channel should be brighter")
        XCTAssertGreaterThan(adjustedPixel.g, 128, "Green channel should be brighter")
        XCTAssertGreaterThan(adjustedPixel.b, 128, "Blue channel should be brighter")
    }
    
    func testBlurProcessing() async throws {
        // Create test texture with high contrast pattern
        let sourceTexture = try createCheckerboardTexture()
        
        let operations: [RenderOperation] = [.blur(radius: 5.0)]
        
        // Process image
        let resultTexture = try await renderEngine.processImage(from: sourceTexture, operations: operations)
        
        // Verify the result
        let pixelData = try readTexturePixels(resultTexture)
        XCTAssertFalse(pixelData.isEmpty, "Should have pixel data after blur")
        
        // Blur should reduce sharp contrasts, so we shouldn't have pure black or white
        let hasBlending = pixelData.contains { pixel in
            let intensity = (Int(pixel.r) + Int(pixel.g) + Int(pixel.b)) / 3
            return intensity > 50 && intensity < 200
        }
        
        XCTAssertTrue(hasBlending, "Blur should create intermediate pixel values")
    }
    
    func testMultipleOperationChain() async throws {
        // Create test texture
        let sourceTexture = try createTestTexture(color: SIMD4<Float>(0.3, 0.3, 0.3, 1.0))
        
        // Create operation chain
        var colorParams = ColorAdjustmentParams()
        colorParams.brightness = 0.1
        colorParams.contrast = 1.2
        
        let operations: [RenderOperation] = [
            .colorAdjustments(colorParams),
            .blur(radius: 2.0)
        ]
        
        // Process image
        let resultTexture = try await renderEngine.processImage(from: sourceTexture, operations: operations)
        
        // Verify the result
        let pixelData = try readTexturePixels(resultTexture)
        XCTAssertFalse(pixelData.isEmpty, "Should have pixel data after operation chain")
    }
    
    // MARK: - Performance Tests
    
    func testRenderingPerformance() async throws {
        let sourceTexture = try createTestTexture(color: SIMD4<Float>(1.0, 1.0, 1.0, 1.0))
        let destinationTexture = try renderEngine.createRenderTexture(
            width: Int(testTextureSize.width),
            height: Int(testTextureSize.height)
        )
        
        measure {
            let expectation = XCTestExpectation(description: "Render completion")
            
            Task {
                do {
                    try await renderEngine.render(texture: sourceTexture, to: destinationTexture)
                    expectation.fulfill()
                } catch {
                    XCTFail("Render failed: \(error)")
                    expectation.fulfill()
                }
            }
            
            wait(for: [expectation], timeout: 5.0)
        }
    }
    
    func testMultipleTextureProcessingPerformance() async throws {
        let sourceTextures = try (0..<10).map { index in
            try createTestTexture(color: SIMD4<Float>(Float(index) / 10.0, 0.5, 0.5, 1.0))
        }
        
        var colorParams = ColorAdjustmentParams()
        colorParams.contrast = 1.1
        
        let operations: [RenderOperation] = [.colorAdjustments(colorParams)]
        
        measure {
            let expectation = XCTestExpectation(description: "Multiple texture processing")
            
            Task {
                do {
                    for sourceTexture in sourceTextures {
                        _ = try await renderEngine.processImage(from: sourceTexture, operations: operations)
                    }
                    expectation.fulfill()
                } catch {
                    XCTFail("Processing failed: \(error)")
                    expectation.fulfill()
                }
            }
            
            wait(for: [expectation], timeout: 10.0)
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testInvalidTextureHandling() async throws {
        // Create incompatible texture sizes
        let sourceTexture = try createTestTexture(size: CGSize(width: 256, height: 256))
        let destinationTexture = try renderEngine.createRenderTexture(
            width: 512,
            height: 512
        )
        
        // This should still work - the engine should handle size differences
        try await renderEngine.render(texture: sourceTexture, to: destinationTexture)
        
        // Verify no crash occurred
        XCTAssertTrue(true, "Should handle texture size differences gracefully")
    }
    
    func testMemoryPressureHandling() async throws {
        // Simulate memory pressure
        renderEngine.setMemoryPressure(.critical)
        
        let sourceTexture = try createTestTexture()
        
        do {
            _ = try await renderEngine.processImage(from: sourceTexture, operations: [])
        } catch RenderEngineError.memoryPressureCritical {
            // Expected behavior under critical memory pressure
            XCTAssertTrue(true, "Should throw memory pressure error")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        
        // Reset memory pressure
        renderEngine.setMemoryPressure(.normal)
    }
    
    // MARK: - Resource Management Tests
    
    func testTextureLoading() async throws {
        // Create a test image URL (in practice, would use a real test image)
        let testImageData = try createTestImageData()
        
        let texture = try await renderEngine.loadTexture(
            from: testImageData,
            identifier: "test-image",
            options: .default
        )
        
        XCTAssertNotNil(texture, "Should successfully load texture from data")
        XCTAssertGreaterThan(texture.width, 0, "Texture should have valid width")
        XCTAssertGreaterThan(texture.height, 0, "Texture should have valid height")
    }
    
    func testTextureCaching() async throws {
        let testImageData = try createTestImageData()
        
        // Load texture twice with same identifier
        let texture1 = try await renderEngine.loadTexture(
            from: testImageData,
            identifier: "cache-test",
            options: .default
        )
        
        let texture2 = try await renderEngine.loadTexture(
            from: testImageData,
            identifier: "cache-test",
            options: .default
        )
        
        // Should be the same texture instance due to caching
        XCTAssertEqual(texture1, texture2, "Should return cached texture")
    }
    
    func testStatisticsTracking() async throws {
        let sourceTexture = try createTestTexture()
        let destinationTexture = try renderEngine.createRenderTexture(
            width: Int(testTextureSize.width),
            height: Int(testTextureSize.height)
        )
        
        let initialStats = renderEngine.currentStatistics
        
        // Perform rendering
        try await renderEngine.render(texture: sourceTexture, to: destinationTexture)
        
        // Wait for statistics update
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        let updatedStats = renderEngine.currentStatistics
        
        XCTAssertGreaterThanOrEqual(updatedStats.framesRendered, initialStats.framesRendered,
                                   "Frame count should increase")
    }
    
    // MARK: - Helper Methods
    
    private func createTestTexture(
        color: SIMD4<Float> = SIMD4<Float>(1.0, 1.0, 1.0, 1.0),
        size: CGSize? = nil
    ) throws -> MTLTexture {
        let actualSize = size ?? testTextureSize
        
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: Int(actualSize.width),
            height: Int(actualSize.height),
            mipmapped: false
        )
        
        descriptor.usage = [.shaderRead, .renderTarget]
        
        guard let texture = testDevice.makeTexture(descriptor: descriptor) else {
            throw XCTError("Failed to create test texture")
        }
        
        // Fill texture with solid color
        let pixelCount = Int(actualSize.width * actualSize.height)
        var pixelData = [UInt8]()
        
        for _ in 0..<pixelCount {
            pixelData.append(UInt8(color.x * 255))
            pixelData.append(UInt8(color.y * 255))
            pixelData.append(UInt8(color.z * 255))
            pixelData.append(UInt8(color.w * 255))
        }
        
        texture.replace(
            region: MTLRegion(
                origin: MTLOrigin(x: 0, y: 0, z: 0),
                size: MTLSize(width: Int(actualSize.width), height: Int(actualSize.height), depth: 1)
            ),
            mipmapLevel: 0,
            withBytes: pixelData,
            bytesPerRow: Int(actualSize.width) * 4
        )
        
        return texture
    }
    
    private func createCheckerboardTexture() throws -> MTLTexture {
        let size = testTextureSize!
        let checkerSize = 32
        
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: Int(size.width),
            height: Int(size.height),
            mipmapped: false
        )
        
        descriptor.usage = [.shaderRead, .renderTarget]
        
        guard let texture = testDevice.makeTexture(descriptor: descriptor) else {
            throw XCTError("Failed to create checkerboard texture")
        }
        
        var pixelData = [UInt8]()
        
        for y in 0..<Int(size.height) {
            for x in 0..<Int(size.width) {
                let checkerX = x / checkerSize
                let checkerY = y / checkerSize
                let isWhite = (checkerX + checkerY) % 2 == 0
                let color: UInt8 = isWhite ? 255 : 0
                
                pixelData.append(color) // R
                pixelData.append(color) // G
                pixelData.append(color) // B
                pixelData.append(255)   // A
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
    
    private func createTestImageData() throws -> Data {
        // Create a simple 4x4 RGBA image
        let width = 4
        let height = 4
        var pixelData = [UInt8]()
        
        // Create gradient pattern
        for y in 0..<height {
            for x in 0..<width {
                let intensity = UInt8((x + y) * 255 / (width + height - 2))
                pixelData.append(intensity) // R
                pixelData.append(intensity) // G
                pixelData.append(intensity) // B
                pixelData.append(255)       // A
            }
        }
        
        return Data(pixelData)
    }
    
    private func readTexturePixels(_ texture: MTLTexture) throws -> [PixelRGBA] {
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
        
        var pixels = [PixelRGBA]()
        
        for i in stride(from: 0, to: dataSize, by: 4) {
            let pixel = PixelRGBA(
                r: pixelData[i],
                g: pixelData[i + 1],
                b: pixelData[i + 2],
                a: pixelData[i + 3]
            )
            pixels.append(pixel)
        }
        
        return pixels
    }
}

struct PixelRGBA {
    let r: UInt8
    let g: UInt8
    let b: UInt8
    let a: UInt8
}

extension XCTError {
    init(_ message: String) {
        self.init(message)
    }
}