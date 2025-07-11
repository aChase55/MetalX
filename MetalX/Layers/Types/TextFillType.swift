import UIKit

enum TextFillType {
    case solid(UIColor)
    case gradient(colors: [UIColor], startPoint: CGPoint, endPoint: CGPoint)
    case image(UIImage)
    case none // For outline-only text
}