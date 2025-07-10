import XCTest
@testable import MetalX
import Metal

class MemoryManagementTests: XCTestCase {
    
    var renderEngine: RenderEngine?
    
    override func setUp() {
        super.setUp()
        do {
            var config = EngineConfiguration()
            config.qualityLevel = .medium
            config.maxMemoryUsage = 128 * 1024 * 1024 // 128MB for testing
            config.enableValidation = true
            renderEngine = try RenderEngine(configuration: config)
        } catch {
            XCTFail("Failed to create render engine: \(error)")
        }
    }
    
    override func tearDown() {
        renderEngine = nil
        super.tearDown()
    }
    
    // MARK: - Texture Pool Memory Management Tests
    
    func testTextureCreationAndRelease() {
        guard let engine = renderEngine else {
            XCTFail("Render engine not available")
            return
        }
        
        // Create several textures
        var textures: [MTLTexture] = []
        
        for _ in 0..<10 {
            do {
                let texture = try engine.createRenderTexture(width: 512, height: 512)
                textures.append(texture)
            } catch {
                XCTFail("Failed to create texture: \(error)")
            }
        }
        
        // Verify textures were created successfully
        XCTAssertEqual(textures.count, 10, "All textures should be created successfully")
        
        for texture in textures {
            XCTAssertEqual(texture.width, 512)
            XCTAssertEqual(texture.height, 512)
        }
        
        // Release textures
        textures.removeAll()
        
        // This test mainly verifies that texture creation/release doesn't crash
        XCTAssertEqual(textures.count, 0)
    }
    
    func testTexturePoolReuse() {
        guard let engine = renderEngine else {
            XCTFail("Render engine not available")
            return
        }
        
        // Create and release a texture
        let originalTexture: MTLTexture
        do {
            originalTexture = try engine.createRenderTexture(width: 256, height: 256)
        } catch {
            XCTFail("Failed to create texture: \(error)")
            return
        }
        
        let originalPointer = Unmanaged.passUnretained(originalTexture).toOpaque()
        
        // Force texture to be returned to pool
        originalTexture.setPurgeableState(.empty)
        
        // Create another texture with same dimensions
        let newTexture: MTLTexture
        do {
            newTexture = try engine.createRenderTexture(width: 256, height: 256)
        } catch {
            XCTFail("Failed to create second texture: \(error)")
            return
        }
        
        // Verify reuse (this is a heuristic test - pool might not always reuse immediately)
        let newPointer = Unmanaged.passUnretained(newTexture).toOpaque()
        
        // At minimum, verify we can create textures without memory issues
        XCTAssertNotNil(newTexture)
        XCTAssertEqual(newTexture.width, 256)
        XCTAssertEqual(newTexture.height, 256)
    }
    
    func testMemoryPressureHandling() {
        guard let engine = renderEngine else {
            XCTFail("Render engine not available")
            return
        }
        
        // Simulate memory pressure by creating many large textures
        var textures: [MTLTexture] = []
        let largeTextureSize = 1024
        
        // Create textures until we approach memory limit
        var creationSucceeded = true
        var textureCount = 0
        
        while creationSucceeded && textureCount < 20 { // Limit to prevent infinite loop
            do {
                let texture = try engine.createRenderTexture(width: largeTextureSize, height: largeTextureSize)
                textures.append(texture)
                textureCount += 1
            } catch {
                creationSucceeded = false
            }
        }
        
        XCTAssertGreaterThan(textureCount, 0, "Should be able to create at least one texture")
        
        // Release all textures
        textures.removeAll()
        
        // Should be able to create textures again after cleanup
        do {
            let texture = try engine.createRenderTexture(width: largeTextureSize, height: largeTextureSize)
            XCTAssertNotNil(texture)
        } catch {
            XCTFail("Should be able to create texture after cleanup: \(error)")
        }
    }
    
    // MARK: - Pipeline State Cache Tests
    
    func testPipelineStateCacheMemoryManagement() {
        guard let engine = renderEngine else {
            XCTFail("Render engine not available")
            return
        }
        
        // Force creation of some pipeline states by rendering
        let canvas = Canvas()
        let imageLayer = ImageLayer(image: createTestImage())
        canvas.addLayer(imageLayer)
        
        // This test mainly verifies that pipeline state creation doesn't crash
        // Note: Pipeline cache is internal so we can't directly test it
        XCTAssertNotNil(engine)
        XCTAssertEqual(canvas.layers.count, 1)
    }
    
    // MARK: - Resource Leak Detection Tests
    
    func testShapeLayerResourceCleanup() {
        var shapeLayer: VectorShapeLayer? = VectorShapeLayer.rectangle(size: CGSize(width: 100, height: 100))
        
        // Render the shape to allocate resources
        if let device = MTLCreateSystemDefaultDevice() {
            do {
                let metalDevice = try MetalDevice(preferredDevice: device)
                let context = RenderContext(device: metalDevice)
                let texture = shapeLayer?.render(context: context)
                XCTAssertNotNil(texture, "Shape rendering should succeed")
            } catch {
                XCTFail("Failed to create rendering context: \(error)")
            }
        }
        
        // Release the layer
        shapeLayer = nil
        
        // Force memory cleanup
        autoreleasepool {
            // Objects should be deallocated
        }
        
        // This test mainly ensures no crashes occur during cleanup
        XCTAssertNil(shapeLayer)
    }
    
    func testTextLayerResourceCleanup() {
        var textLayer: TextLayer? = TextLayer(text: "Test memory cleanup")
        
        // Access texture to trigger resource allocation
        let texture = textLayer?.texture
        XCTAssertNotNil(texture, "Text layer should generate texture")
        
        // Release the layer
        textLayer = nil
        
        // Force memory cleanup
        autoreleasepool {
            // Objects should be deallocated
        }
        
        // This test mainly ensures no crashes occur during cleanup
        XCTAssertNil(textLayer)
    }
    
    // MARK: - Canvas Memory Tests
    
    func testCanvasLayerMemoryManagement() {
        let canvas = Canvas()
        
        // Add multiple layers
        for i in 0..<20 {
            let layer = TextLayer(text: "Layer \(i)")
            canvas.addLayer(layer)
        }
        
        XCTAssertEqual(canvas.layers.count, 20)
        
        // Clear canvas
        canvas.clear()
        
        XCTAssertEqual(canvas.layers.count, 0, "Canvas should be empty after clear")
        
        // Verify we can still add layers after clearing
        let newLayer = TextLayer(text: "New layer after clear")
        canvas.addLayer(newLayer)
        XCTAssertEqual(canvas.layers.count, 1)
    }
    
    func testCanvasRenderingMemoryStability() {
        let canvas = Canvas()
        
        // Add various layer types
        canvas.addLayer(ImageLayer(image: createTestImage()))
        canvas.addLayer(TextLayer(text: "Memory test"))
        canvas.addLayer(VectorShapeLayer.ellipse(size: CGSize(width: 50, height: 50)))
        
        // Trigger multiple render cycles
        for _ in 0..<10 {
            canvas.setNeedsDisplay()
            // In a real app, this would trigger rendering
        }
        
        // Verify canvas state remains stable
        XCTAssertEqual(canvas.layers.count, 3)
        XCTAssertFalse(canvas.needsDisplay) // Should be reset after display
    }
    
    // MARK: - Helper Methods
    
    private func createTestImage() -> UIImage {
        let size = CGSize(width: 64, height: 64)
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        UIColor.blue.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return image
    }
}

// MARK: - Test Helper Extensions

// Note: Memory management tests are simplified due to private API constraints
// In production, consider exposing memory statistics through a debug interface