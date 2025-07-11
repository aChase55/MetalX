import UIKit
import CoreGraphics

enum TextFillType: Codable {
    case solid(UIColor)
    case gradient(MetalX.Gradient)  // Use MetalX namespace to avoid SwiftUI conflict
    case image(UIImage)
    case none // For outline-only text
    
    enum CodingKeys: String, CodingKey {
        case type
        case color
        case gradient
        case imageData
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "solid":
            let colorData = try container.decode(Data.self, forKey: .color)
            let color = try NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: colorData) ?? .white
            self = .solid(color)
        case "gradient":
            let gradientData = try container.decode(Data.self, forKey: .gradient)
            if let gradient = try? JSONDecoder().decode(MetalX.Gradient.self, from: gradientData) {
                self = .gradient(gradient)
            } else {
                self = .solid(.white)
            }
        case "image":
            let imageData = try container.decode(Data.self, forKey: .imageData)
            let image = UIImage(data: imageData) ?? UIImage()
            self = .image(image)
        case "none":
            self = .none
        default:
            self = .solid(.white)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .solid(let color):
            try container.encode("solid", forKey: .type)
            let colorData = try NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false)
            try container.encode(colorData, forKey: .color)
        case .gradient(let gradient):
            try container.encode("gradient", forKey: .type)
            let gradientData = try JSONEncoder().encode(gradient)
            try container.encode(gradientData, forKey: .gradient)
        case .image(let image):
            try container.encode("image", forKey: .type)
            let imageData = image.pngData() ?? Data()
            try container.encode(imageData, forKey: .imageData)
        case .none:
            try container.encode("none", forKey: .type)
        }
    }
}