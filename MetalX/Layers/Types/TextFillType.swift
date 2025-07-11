import UIKit

enum TextFillType: Codable {
    case solid(UIColor)
    case gradient(colors: [UIColor], startPoint: CGPoint, endPoint: CGPoint)
    case image(UIImage)
    case none // For outline-only text
    
    enum CodingKeys: String, CodingKey {
        case type
        case color
        case colors
        case startPoint
        case endPoint
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
            let colorsData = try container.decode([Data].self, forKey: .colors)
            let colors = colorsData.compactMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: $0) }
            let startPoint = try container.decode(CGPoint.self, forKey: .startPoint)
            let endPoint = try container.decode(CGPoint.self, forKey: .endPoint)
            self = .gradient(colors: colors, startPoint: startPoint, endPoint: endPoint)
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
        case .gradient(let colors, let startPoint, let endPoint):
            try container.encode("gradient", forKey: .type)
            let colorsData = try colors.map { try NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: false) }
            try container.encode(colorsData, forKey: .colors)
            try container.encode(startPoint, forKey: .startPoint)
            try container.encode(endPoint, forKey: .endPoint)
        case .image(let image):
            try container.encode("image", forKey: .type)
            let imageData = image.pngData() ?? Data()
            try container.encode(imageData, forKey: .imageData)
        case .none:
            try container.encode("none", forKey: .type)
        }
    }
}