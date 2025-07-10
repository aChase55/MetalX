import XCTest
@testable import MetalX
import CoreGraphics
import UIKit

class SerializationTests: XCTestCase {
    
    var projectListModel: ProjectListModel!
    var testCanvas: Canvas!
    
    override func setUp() {
        super.setUp()
        projectListModel = ProjectListModel()
        testCanvas = Canvas()
    }
    
    override func tearDown() {
        // Clean up any test projects
        for project in projectListModel.projects {
            if project.name.hasPrefix("Test_") {
                projectListModel.deleteProject(project)
            }
        }
        super.tearDown()
    }
    
    // MARK: - Basic Project Save/Load Tests
    
    func testBasicProjectSaveLoad() {
        // Create a test project
        let project = projectListModel.createNewProject(name: "Test_BasicSaveLoad")
        
        // Verify project was created
        XCTAssertTrue(projectListModel.projects.contains { $0.id == project.id })
        
        // Load projects and verify persistence
        projectListModel.loadProjects()
        XCTAssertTrue(projectListModel.projects.contains { $0.id == project.id })
    }
    
    func testProjectNamePersistence() {
        let testName = "Test_NamePersistence_\(UUID().uuidString)"
        let project = projectListModel.createNewProject(name: testName)
        
        // Reload and verify name persisted
        projectListModel.loadProjects()
        let loadedProject = projectListModel.projects.first { $0.id == project.id }
        XCTAssertEqual(loadedProject?.name, testName)
    }
    
    func testCanvasSizePersistence() {
        let customSize = CGSize(width: 1920, height: 1080)
        testCanvas.size = customSize
        
        let project = testCanvas.toProject(name: "Test_CanvasSize")
        projectListModel.saveProject(project)
        
        // Load and verify canvas size
        let newCanvas = Canvas()
        newCanvas.loadFromProject(project)
        XCTAssertEqual(newCanvas.size, customSize)
    }
    
    // MARK: - Layer Serialization Tests
    
    func testImageLayerSerialization() {
        // Create test image
        let testImage = createTestImage()
        let imageLayer = ImageLayer(image: testImage)
        imageLayer.name = "Test Image Layer"
        imageLayer.transform.position = CGPoint(x: 100, y: 200)
        imageLayer.transform.scale = 1.5
        imageLayer.opacity = 0.8
        
        testCanvas.addLayer(imageLayer)
        
        // Save and load
        let project = testCanvas.toProject(name: "Test_ImageLayer")
        let newCanvas = Canvas()
        newCanvas.loadFromProject(project)
        
        // Verify layer was loaded correctly
        XCTAssertEqual(newCanvas.layers.count, 1)
        let loadedLayer = newCanvas.layers.first as? ImageLayer
        XCTAssertNotNil(loadedLayer)
        XCTAssertEqual(loadedLayer?.name, "Test Image Layer")
        XCTAssertEqual(loadedLayer?.transform.position.x, 100, accuracy: 0.1)
        XCTAssertEqual(loadedLayer?.transform.position.y, 200, accuracy: 0.1)
        XCTAssertEqual(loadedLayer?.transform.scale, 1.5, accuracy: 0.01)
        XCTAssertEqual(loadedLayer?.opacity, 0.8, accuracy: 0.01)
    }
    
    func testTextLayerSerialization() {
        let textLayer = TextLayer(text: "Test Text")
        textLayer.name = "Test Text Layer"
        textLayer.font = UIFont.systemFont(ofSize: 24)
        textLayer.textColor = UIColor.red
        textLayer.transform.position = CGPoint(x: 50, y: 75)
        
        testCanvas.addLayer(textLayer)
        
        // Save and load
        let project = testCanvas.toProject(name: "Test_TextLayer")
        let newCanvas = Canvas()
        newCanvas.loadFromProject(project)
        
        // Verify layer was loaded correctly
        XCTAssertEqual(newCanvas.layers.count, 1)
        let loadedLayer = newCanvas.layers.first as? TextLayer
        XCTAssertNotNil(loadedLayer)
        XCTAssertEqual(loadedLayer?.text, "Test Text")
        XCTAssertEqual(loadedLayer?.name, "Test Text Layer")
        XCTAssertEqual(loadedLayer?.font.pointSize, 24)
        XCTAssertEqual(loadedLayer?.transform.position.x, 50, accuracy: 0.1)
        XCTAssertEqual(loadedLayer?.transform.position.y, 75, accuracy: 0.1)
    }
    
    func testShapeLayerSerialization() {
        let shapeLayer = VectorShapeLayer.rectangle(size: CGSize(width: 100, height: 80))
        shapeLayer.name = "Test Rectangle"
        shapeLayer.fillType = .solid(UIColor.blue.cgColor)
        shapeLayer.strokeColor = UIColor.black.cgColor
        shapeLayer.strokeWidth = 2.0
        shapeLayer.transform.position = CGPoint(x: 150, y: 250)
        
        testCanvas.addLayer(shapeLayer)
        
        // Save and load
        let project = testCanvas.toProject(name: "Test_ShapeLayer")
        let newCanvas = Canvas()
        newCanvas.loadFromProject(project)
        
        // Verify layer was loaded correctly
        XCTAssertEqual(newCanvas.layers.count, 1)
        let loadedLayer = newCanvas.layers.first as? VectorShapeLayer
        XCTAssertNotNil(loadedLayer)
        XCTAssertEqual(loadedLayer?.name, "Test Rectangle")
        XCTAssertEqual(loadedLayer?.strokeWidth, 2.0)
        XCTAssertEqual(loadedLayer?.transform.position.x, 150, accuracy: 0.1)
        XCTAssertEqual(loadedLayer?.transform.position.y, 250, accuracy: 0.1)
        
        // Verify fill type
        if case .solid(let color) = loadedLayer?.fillType {
            XCTAssertTrue(color.isApproximatelyEqual(to: UIColor.blue.cgColor))
        } else {
            XCTFail("Expected solid fill type")
        }
    }
    
    // MARK: - Gradient Serialization Tests
    
    func testLinearGradientSerialization() {
        let gradient = Gradient(
            type: .linear,
            colorStops: [
                Gradient.ColorStop(color: UIColor.red.cgColor, location: 0.0),
                Gradient.ColorStop(color: UIColor.blue.cgColor, location: 1.0)
            ],
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 1, y: 1)
        )
        
        let shapeLayer = VectorShapeLayer.ellipse(size: CGSize(width: 100, height: 100))
        shapeLayer.fillType = .gradient(gradient)
        shapeLayer.name = "Test Linear Gradient"
        
        testCanvas.addLayer(shapeLayer)
        
        // Save and load
        let project = testCanvas.toProject(name: "Test_LinearGradient")
        let newCanvas = Canvas()
        newCanvas.loadFromProject(project)
        
        // Verify gradient was loaded correctly
        let loadedLayer = newCanvas.layers.first as? VectorShapeLayer
        XCTAssertNotNil(loadedLayer)
        
        if case .gradient(let loadedGradient) = loadedLayer?.fillType {
            XCTAssertEqual(loadedGradient.type, .linear)
            XCTAssertEqual(loadedGradient.colorStops.count, 2)
            XCTAssertEqual(loadedGradient.colorStops[0].location, 0.0)
            XCTAssertEqual(loadedGradient.colorStops[1].location, 1.0)
            XCTAssertEqual(loadedGradient.startPoint, CGPoint(x: 0, y: 0))
            XCTAssertEqual(loadedGradient.endPoint, CGPoint(x: 1, y: 1))
        } else {
            XCTFail("Expected gradient fill type")
        }
    }
    
    func testAngularGradientSerialization() {
        let gradient = Gradient(
            type: .angular,
            colorStops: [
                Gradient.ColorStop(color: UIColor.yellow.cgColor, location: 0.0),
                Gradient.ColorStop(color: UIColor.purple.cgColor, location: 0.5),
                Gradient.ColorStop(color: UIColor.yellow.cgColor, location: 1.0)
            ],
            startPoint: CGPoint(x: 0.5, y: 0.5),
            endPoint: CGPoint(x: 0.5, y: 0.5)
        )
        
        let shapeLayer = VectorShapeLayer.polygon(sides: 6, radius: 50)
        shapeLayer.fillType = .gradient(gradient)
        shapeLayer.name = "Test Angular Gradient"
        
        testCanvas.addLayer(shapeLayer)
        
        // Save and load
        let project = testCanvas.toProject(name: "Test_AngularGradient")
        let newCanvas = Canvas()
        newCanvas.loadFromProject(project)
        
        // Verify angular gradient was loaded correctly
        let loadedLayer = newCanvas.layers.first as? VectorShapeLayer
        XCTAssertNotNil(loadedLayer)
        
        if case .gradient(let loadedGradient) = loadedLayer?.fillType {
            XCTAssertEqual(loadedGradient.type, .angular)
            XCTAssertEqual(loadedGradient.colorStops.count, 3)
            XCTAssertEqual(loadedGradient.startPoint, CGPoint(x: 0.5, y: 0.5))
            XCTAssertEqual(loadedGradient.endPoint, CGPoint(x: 0.5, y: 0.5))
        } else {
            XCTFail("Expected gradient fill type")
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testCorruptedProjectHandling() {
        // Create a corrupted JSON file
        let corruptedData = "{ invalid json".data(using: .utf8)!
        let testURL = projectListModel.projectURL(for: MetalXProject(name: "corrupt"))
        
        try? corruptedData.write(to: testURL)
        
        // Verify loading doesn't crash and handles corruption gracefully
        projectListModel.loadProjects()
        
        // Should not contain the corrupted project
        XCTAssertFalse(projectListModel.projects.contains { $0.name == "corrupt" })
    }
    
    func testLargeCanvasSizeValidation() {
        // Test canvas size clamping
        let oversizedCanvas = Canvas()
        oversizedCanvas.size = CGSize(width: 10000, height: 10000) // Exceeds Metal limits
        
        let project = oversizedCanvas.toProject(name: "Test_OversizedCanvas")
        let newCanvas = Canvas()
        newCanvas.loadFromProject(project)
        
        // Verify size was clamped to safe limits
        XCTAssertLessThanOrEqual(newCanvas.size.width, 4096)
        XCTAssertLessThanOrEqual(newCanvas.size.height, 4096)
    }
    
    func testMultipleLayerSerialization() {
        // Create multiple layers of different types
        let imageLayer = ImageLayer(image: createTestImage())
        imageLayer.name = "Test Image"
        
        let textLayer = TextLayer(text: "Multi-layer test")
        textLayer.name = "Test Text"
        
        let shapeLayer = VectorShapeLayer.rectangle(size: CGSize(width: 50, height: 50))
        shapeLayer.name = "Test Shape"
        
        testCanvas.addLayer(imageLayer)
        testCanvas.addLayer(textLayer)
        testCanvas.addLayer(shapeLayer)
        
        // Save and load
        let project = testCanvas.toProject(name: "Test_MultiLayer")
        let newCanvas = Canvas()
        newCanvas.loadFromProject(project)
        
        // Verify all layers were preserved
        XCTAssertEqual(newCanvas.layers.count, 3)
        XCTAssertTrue(newCanvas.layers.contains { $0.name == "Test Image" })
        XCTAssertTrue(newCanvas.layers.contains { $0.name == "Test Text" })
        XCTAssertTrue(newCanvas.layers.contains { $0.name == "Test Shape" })
    }
    
    // MARK: - Helper Methods
    
    private func createTestImage() -> UIImage {
        let size = CGSize(width: 100, height: 100)
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        UIColor.red.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return image
    }
}

// MARK: - CGColor Comparison Extension

extension CGColor {
    func isApproximatelyEqual(to other: CGColor, tolerance: CGFloat = 0.01) -> Bool {
        guard let components1 = self.components,
              let components2 = other.components,
              components1.count == components2.count else {
            return false
        }
        
        for (c1, c2) in zip(components1, components2) {
            if abs(c1 - c2) > tolerance {
                return false
            }
        }
        return true
    }
}