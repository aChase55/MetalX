import Foundation
import CoreGraphics
import UIKit

// MARK: - Project Model

struct MetalXProject: Codable, Hashable, Equatable {
    var id: UUID
    var name: String
    var createdDate: Date
    var modifiedDate: Date
    var canvasSize: CGSize
    var backgroundColor: CodableColor
    var layers: [LayerData]
    
    // Version for future migration support
    let formatVersion: String = "1.0"
    
    init(name: String, canvasSize: CGSize = CGSize(width: 1024, height: 1024)) {
        self.id = UUID()
        self.name = name
        self.createdDate = Date()
        self.modifiedDate = Date()
        self.canvasSize = canvasSize
        self.backgroundColor = CodableColor(red: 0, green: 0, blue: 0, alpha: 1)
        self.layers = []
    }
}

// MARK: - Layer Data for Serialization

struct LayerData: Codable, Hashable, Equatable {
    let id: UUID
    var name: String
    var type: LayerType
    var transform: LayerTransformData
    var opacity: Float
    var isVisible: Bool
    var isLocked: Bool
    var blendMode: String
    var bounds: CGRect
    var dropShadow: DropShadowData?
    
    // Type-specific data
    var imageData: ImageLayerData?
    var textData: TextLayerData?
    var shapeData: ShapeLayerData?
    
    enum LayerType: String, Codable {
        case image
        case text
        case shape
    }
}

struct DropShadowData: Codable, Hashable, Equatable {
    var isEnabled: Bool
    var offset: CGSize
    var blur: CGFloat
    var color: CodableColor
    var opacity: Float
}

struct LayerTransformData: Codable, Hashable, Equatable {
    var position: CGPoint
    var scale: CGFloat
    var rotation: CGFloat
}

struct ImageLayerData: Codable, Hashable, Equatable {
    var imageData: Data  // PNG or JPEG data
    var originalSize: CGSize
}

struct TextLayerData: Codable, Hashable, Equatable {
    var text: String
    var fontSize: CGFloat
    var fontName: String
    var textColor: CodableColor
    var alignment: String
}

struct ShapeLayerData: Codable, Hashable, Equatable {
    var shapeType: String  // "rectangle", "ellipse", "polygon"
    var fillColor: CodableColor?
    var gradientData: GradientSerializationData?
    var imageData: Data?  // PNG/JPEG data for image fills
    var strokeColor: CodableColor?
    var strokeWidth: Float
    var size: CGSize
    var sides: Int?  // For polygons
}

struct GradientSerializationData: Codable, Hashable, Equatable {
    var type: String // "linear", "radial", "angular"
    var colorStops: [ColorStopData]
    var startPoint: CGPoint
    var endPoint: CGPoint
}

struct ColorStopData: Codable, Hashable, Equatable {
    var color: CodableColor
    var location: Float
}

// MARK: - Helper Types

struct CodableColor: Codable, Hashable, Equatable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat
    
    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
    
    init(cgColor: CGColor) {
        // Convert to RGB color space first to ensure consistent component layout
        guard let rgbColor = cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil) else {
            // Fallback if conversion fails
            let components = cgColor.components ?? [0, 0, 0, 1]
            self.red = components.count > 0 ? components[0] : 0
            self.green = components.count > 1 ? components[1] : 0
            self.blue = components.count > 2 ? components[2] : 0
            self.alpha = components.count > 3 ? components[3] : 1
            return
        }
        
        let components = rgbColor.components ?? [0, 0, 0, 1]
        self.red = components.count > 0 ? components[0] : 0
        self.green = components.count > 1 ? components[1] : 0
        self.blue = components.count > 2 ? components[2] : 0
        self.alpha = components.count > 3 ? components[3] : 1
    }
    
    var cgColor: CGColor {
        return CGColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

// MARK: - Project List Model

class ProjectListModel: ObservableObject {
    @Published var projects: [MetalXProject] = []
    
    private let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    private let projectsDirectory: URL
    
    init() {
        projectsDirectory = documentsDirectory.appendingPathComponent("MetalXProjects")
        createProjectsDirectoryIfNeeded()
        loadProjects()
    }
    
    private func createProjectsDirectoryIfNeeded() {
        try? FileManager.default.createDirectory(at: projectsDirectory, withIntermediateDirectories: true)
    }
    
    func loadProjects() {
        do {
            let projectURLs = try FileManager.default.contentsOfDirectory(
                at: projectsDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles
            ).filter { $0.pathExtension == "metalx" }
            
            projects = projectURLs.compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let project = try? JSONDecoder().decode(MetalXProject.self, from: data) else {
                    return nil
                }
                return project
            }.sorted { $0.modifiedDate > $1.modifiedDate }
        } catch {
            print("Error loading projects: \(error)")
        }
    }
    
    func createNewProject(name: String, preset: CanvasPreset? = nil) -> MetalXProject {
        // Use preset size or default
        var canvasSize = preset?.defaultEditingSize ?? CanvasPreset.defaultPreset.defaultEditingSize
        
        // Ensure canvas size doesn't exceed safe limits
        let maxDimension: CGFloat = 4096
        if canvasSize.width > maxDimension || canvasSize.height > maxDimension {
            let scale = min(maxDimension / canvasSize.width, maxDimension / canvasSize.height)
            canvasSize = CGSize(
                width: canvasSize.width * scale,
                height: canvasSize.height * scale
            )
        }
        
        let project = MetalXProject(name: name, canvasSize: canvasSize)
        saveProject(project)
        loadProjects()
        return project
    }
    
    func saveProject(_ project: MetalXProject) {
        var updatedProject = project
        updatedProject.modifiedDate = Date()
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(updatedProject)
            
            let url = projectsDirectory.appendingPathComponent("\(project.id.uuidString).metalx")
            try data.write(to: url)
        } catch {
            print("Error saving project: \(error)")
        }
    }
    
    func deleteProject(_ project: MetalXProject) {
        let url = projectsDirectory.appendingPathComponent("\(project.id.uuidString).metalx")
        try? FileManager.default.removeItem(at: url)
        loadProjects()
    }
    
    func projectURL(for project: MetalXProject) -> URL {
        return projectsDirectory.appendingPathComponent("\(project.id.uuidString).metalx")
    }
}