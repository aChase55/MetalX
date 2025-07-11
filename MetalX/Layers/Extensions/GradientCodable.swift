import Foundation
import CoreGraphics
import UIKit

// Make Gradient conform to Codable
extension MetalX.Gradient: Codable {
    enum CodingKeys: String, CodingKey {
        case type
        case colorStops
        case startPoint
        case endPoint
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode type
        let typeString = try container.decode(String.self, forKey: .type)
        switch typeString {
        case "linear":
            self.type = .linear
        case "radial":
            self.type = .radial
        case "angular":
            self.type = .angular
        default:
            self.type = .linear
        }
        
        // Decode color stops
        let colorStopData = try container.decode([ColorStopData].self, forKey: .colorStops)
        self.colorStops = colorStopData.map { data in
            ColorStop(
                color: UIColor(red: CGFloat(data.color.red),
                             green: CGFloat(data.color.green),
                             blue: CGFloat(data.color.blue),
                             alpha: CGFloat(data.color.alpha)).cgColor,
                location: data.location
            )
        }
        
        // Decode points
        self.startPoint = try container.decode(CGPoint.self, forKey: .startPoint)
        self.endPoint = try container.decode(CGPoint.self, forKey: .endPoint)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        // Encode type
        let typeString: String
        switch type {
        case .linear:
            typeString = "linear"
        case .radial:
            typeString = "radial"
        case .angular:
            typeString = "angular"
        }
        try container.encode(typeString, forKey: .type)
        
        // Encode color stops
        let colorStopData = colorStops.map { stop in
            let uiColor = UIColor(cgColor: stop.color)
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            
            return ColorStopData(
                color: CodableColor(
                    red: red,
                    green: green,
                    blue: blue,
                    alpha: alpha
                ),
                location: stop.location
            )
        }
        try container.encode(colorStopData, forKey: .colorStops)
        
        // Encode points
        try container.encode(startPoint, forKey: .startPoint)
        try container.encode(endPoint, forKey: .endPoint)
    }
}

// GradientType already conforms to Codable through raw values

// Make ColorStop conform to Codable
extension MetalX.Gradient.ColorStop: Codable {
    enum CodingKeys: String, CodingKey {
        case color
        case location
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let colorData = try container.decode(CodableColor.self, forKey: .color)
        self.color = UIColor(
            red: CGFloat(colorData.red),
            green: CGFloat(colorData.green),
            blue: CGFloat(colorData.blue),
            alpha: CGFloat(colorData.alpha)
        ).cgColor
        self.location = try container.decode(Float.self, forKey: .location)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        let uiColor = UIColor(cgColor: color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        let colorData = CodableColor(
            red: red,
            green: green,
            blue: blue,
            alpha: alpha
        )
        try container.encode(colorData, forKey: .color)
        try container.encode(location, forKey: .location)
    }
}