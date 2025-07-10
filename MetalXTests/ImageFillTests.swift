import XCTest
@testable import MetalX
import UIKit
import MetalKit

class ImageFillTests: XCTestCase {
    
    var testCanvas: Canvas!
    var testImage: UIImage!
    
    override func setUp() {
        super.setUp()
        testCanvas = Canvas()
        testImage = createTestImage()
    }
    
    override func tearDown() {
        testCanvas = nil
        testImage = nil
        super.tearDown()
    }
    
    // MARK: - Image Fill Creation Tests
    
    func testImageFillCreation() {
        // Create a shape with image fill
        let shapeLayer = VectorShapeLayer.rectangle(size: CGSize(width: 100, height: 100))
        
        // Convert image to texture
        guard let device = MTLCreateSystemDefaultDevice(),
              let cgImage = testImage.cgImage else {
            XCTFail("Failed to get Metal device or CGImage")
            return
        }
        
        let loader = MTKTextureLoader(device: device)
        do {
            let texture = try loader.newTexture(cgImage: cgImage, options: [
                .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
                .SRGB: false
            ])
            
            // Set image fill
            shapeLayer.fillType = .pattern(texture)
            
            // Verify fill type
            if case .pattern(let resultTexture) = shapeLayer.fillType {
                XCTAssertEqual(resultTexture.width, texture.width)
                XCTAssertEqual(resultTexture.height, texture.height)
            } else {
                XCTFail("Expected pattern fill type")
            }
            
        } catch {
            XCTFail("Failed to create texture: \(error)")
        }
    }
    
    func testImageFillRendering() {
        // Create a shape with image fill
        let shapeLayer = VectorShapeLayer.ellipse(size: CGSize(width: 80, height: 80))
        
        // Convert image to texture
        guard let device = MTLCreateSystemDefaultDevice(),
              let cgImage = testImage.cgImage else {
            XCTFail("Failed to get Metal device or CGImage")
            return
        }
        
        let loader = MTKTextureLoader(device: device)
        do {
            let texture = try loader.newTexture(cgImage: cgImage, options: [:])
            shapeLayer.fillType = .pattern(texture)
            
            // Test rendering (this mainly verifies no crashes occur)
            do {
                let metalDevice = try MetalDevice(preferredDevice: device)
                let context = RenderContext(device: metalDevice)
                let renderedTexture = shapeLayer.render(context: context)
                
                XCTAssertNotNil(renderedTexture, "Shape should render successfully with image fill")
                XCTAssertGreaterThan(renderedTexture?.width ?? 0, 0)
                XCTAssertGreaterThan(renderedTexture?.height ?? 0, 0)
                
            } catch {
                XCTFail("Failed to create render context: \(error)")
            }
            
        } catch {
            XCTFail("Failed to create texture: \(error)")
        }
    }
    
    // MARK: - Serialization Tests
    
    func testImageFillSerialization() {
        // Create a shape with image fill
        let shapeLayer = VectorShapeLayer.rectangle(size: CGSize(width: 50, height: 50))
        shapeLayer.name = "Test Image Fill Shape"
        
        // Convert image to texture
        guard let device = MTLCreateSystemDefaultDevice(),
              let cgImage = testImage.cgImage else {
            XCTFail("Failed to get Metal device or CGImage")
            return
        }
        
        let loader = MTKTextureLoader(device: device)
        do {
            let texture = try loader.newTexture(cgImage: cgImage, options: [:])
            shapeLayer.fillType = .pattern(texture)
            
            // Add to canvas and serialize
            testCanvas.addLayer(shapeLayer)
            let project = testCanvas.toProject(name: "Test_ImageFill")
            
            // Load into new canvas
            let newCanvas = Canvas()
            newCanvas.loadFromProject(project)
            
            // Verify the layer was loaded with image fill
            XCTAssertEqual(newCanvas.layers.count, 1)
            let loadedLayer = newCanvas.layers.first as? VectorShapeLayer
            XCTAssertNotNil(loadedLayer)
            XCTAssertEqual(loadedLayer?.name, "Test Image Fill Shape")
            
            // Verify fill type is pattern
            if case .pattern(let loadedTexture) = loadedLayer?.fillType {
                XCTAssertNotNil(loadedTexture)
                XCTAssertGreaterThan(loadedTexture.width, 0)
                XCTAssertGreaterThan(loadedTexture.height, 0)
            } else {
                XCTFail("Expected pattern fill type after loading")
            }
            
        } catch {
            XCTFail("Failed to create texture: \(error)")
        }
    }
    
    func testImageFillWithOtherFillTypes() {
        let shapeLayer = VectorShapeLayer.polygon(sides: 6, radius: 40)
        
        // Test changing between different fill types
        
        // Start with solid
        shapeLayer.fillType = .solid(UIColor.red.cgColor)
        if case .solid(_) = shapeLayer.fillType {
            // Expected
        } else {
            XCTFail("Expected solid fill")
        }
        
        // Change to gradient
        let gradient = Gradient(
            type: .linear,
            colorStops: [
                Gradient.ColorStop(color: UIColor.blue.cgColor, location: 0.0),
                Gradient.ColorStop(color: UIColor.green.cgColor, location: 1.0)
            ],
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 1, y: 1)
        )
        shapeLayer.fillType = .gradient(gradient)
        if case .gradient(_) = shapeLayer.fillType {
            // Expected
        } else {
            XCTFail("Expected gradient fill")
        }
        
        // Change to image
        guard let device = MTLCreateSystemDefaultDevice(),
              let cgImage = testImage.cgImage else {
            XCTFail("Failed to get Metal device or CGImage")
            return
        }
        
        let loader = MTKTextureLoader(device: device)
        do {
            let texture = try loader.newTexture(cgImage: cgImage, options: [:])
            shapeLayer.fillType = .pattern(texture)
            
            if case .pattern(_) = shapeLayer.fillType {
                // Expected
            } else {
                XCTFail("Expected pattern fill")
            }
            
        } catch {
            XCTFail("Failed to create texture: \(error)")
        }
        
        // Change to none
        shapeLayer.fillType = nil
        XCTAssertNil(shapeLayer.fillType)
    }
    
    // MARK: - Error Handling Tests
    
    func testInvalidImageHandling() {
        // Test with corrupt image data
        let corruptData = Data([0, 1, 2, 3, 4]) // Invalid image data
        
        // This should not crash and should return nil
        let texture = LayerFactory.loadImageTexture(from: corruptData)
        XCTAssertNil(texture, "Should return nil for invalid image data")
    }
    
    // MARK: - Helper Methods
    
    private func createTestImage() -> UIImage {
        let size = CGSize(width: 100, height: 100)
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        
        // Create a simple pattern
        let context = UIGraphicsGetCurrentContext()!
        context.setFillColor(UIColor.blue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 50, height: 50))
        context.setFillColor(UIColor.red.cgColor)
        context.fill(CGRect(x: 50, y: 50, width: 50, height: 50))
        context.setFillColor(UIColor.green.cgColor)
        context.fill(CGRect(x: 0, y: 50, width: 50, height: 50))
        context.setFillColor(UIColor.yellow.cgColor)
        context.fill(CGRect(x: 50, y: 0, width: 50, height: 50))
        
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return image
    }
}

// MARK: - Test Helper Extension

extension LayerFactory {
    static func loadImageTexture(from imageData: Data) -> MTLTexture? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let image = UIImage(data: imageData),
              let cgImage = image.cgImage else {
            return nil
        }
        
        let loader = MTKTextureLoader(device: device)
        do {
            let texture = try loader.newTexture(cgImage: cgImage, options: [
                .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
                .SRGB: false
            ])
            return texture
        } catch {
            return nil
        }
    }
}