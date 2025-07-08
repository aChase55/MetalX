import CoreGraphics
import simd
import Foundation

public extension CGRect {
    static var zero: CGRect { CGRect.zero }
    static var unit: CGRect { CGRect(x: 0, y: 0, width: 1, height: 1) }
    
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
    
    var topLeft: CGPoint {
        CGPoint(x: minX, y: minY)
    }
    
    var topRight: CGPoint {
        CGPoint(x: maxX, y: minY)
    }
    
    var bottomLeft: CGPoint {
        CGPoint(x: minX, y: maxY)
    }
    
    var bottomRight: CGPoint {
        CGPoint(x: maxX, y: maxY)
    }
    
    var aspectRatio: CGFloat {
        height != 0 ? width / height : 0
    }
    
    func scaled(by factor: CGFloat) -> CGRect {
        CGRect(
            x: origin.x * factor,
            y: origin.y * factor,
            width: size.width * factor,
            height: size.height * factor
        )
    }
    
    func scaled(by factor: CGSize) -> CGRect {
        CGRect(
            x: origin.x * factor.width,
            y: origin.y * factor.height,
            width: size.width * factor.width,
            height: size.height * factor.height
        )
    }
    
    func insetBy(dx: CGFloat, dy: CGFloat) -> CGRect {
        insetBy(dx: dx, dy: dy)
    }
    
    func insetBy(_ insets: UIEdgeInsets) -> CGRect {
        CGRect(
            x: origin.x + insets.left,
            y: origin.y + insets.top,
            width: size.width - insets.left - insets.right,
            height: size.height - insets.top - insets.bottom
        )
    }
    
    func offsetBy(dx: CGFloat, dy: CGFloat) -> CGRect {
        offsetBy(dx: dx, dy: dy)
    }
    
    func offsetBy(_ offset: CGPoint) -> CGRect {
        offsetBy(dx: offset.x, dy: offset.y)
    }
    
    func aspectFit(in container: CGRect) -> CGRect {
        let containerAspect = container.aspectRatio
        let selfAspect = aspectRatio
        
        let scale: CGFloat
        if selfAspect > containerAspect {
            scale = container.width / width
        } else {
            scale = container.height / height
        }
        
        let scaledSize = CGSize(width: width * scale, height: height * scale)
        let origin = CGPoint(
            x: container.midX - scaledSize.width * 0.5,
            y: container.midY - scaledSize.height * 0.5
        )
        
        return CGRect(origin: origin, size: scaledSize)
    }
    
    func aspectFill(in container: CGRect) -> CGRect {
        let containerAspect = container.aspectRatio
        let selfAspect = aspectRatio
        
        let scale: CGFloat
        if selfAspect > containerAspect {
            scale = container.height / height
        } else {
            scale = container.width / width
        }
        
        let scaledSize = CGSize(width: width * scale, height: height * scale)
        let origin = CGPoint(
            x: container.midX - scaledSize.width * 0.5,
            y: container.midY - scaledSize.height * 0.5
        )
        
        return CGRect(origin: origin, size: scaledSize)
    }
    
    func constrainedTo(_ container: CGRect) -> CGRect {
        var result = self
        
        if result.minX < container.minX {
            result.origin.x = container.minX
        } else if result.maxX > container.maxX {
            result.origin.x = container.maxX - result.width
        }
        
        if result.minY < container.minY {
            result.origin.y = container.minY
        } else if result.maxY > container.maxY {
            result.origin.y = container.maxY - result.height
        }
        
        return result
    }
    
    func normalized(in container: CGRect) -> CGRect {
        CGRect(
            x: (origin.x - container.origin.x) / container.width,
            y: (origin.y - container.origin.y) / container.height,
            width: size.width / container.width,
            height: size.height / container.height
        )
    }
    
    func denormalized(in container: CGRect) -> CGRect {
        CGRect(
            x: container.origin.x + origin.x * container.width,
            y: container.origin.y + origin.y * container.height,
            width: size.width * container.width,
            height: size.height * container.height
        )
    }
    
    func lerp(to target: CGRect, t: CGFloat) -> CGRect {
        CGRect(
            x: origin.x + (target.origin.x - origin.x) * t,
            y: origin.y + (target.origin.y - origin.y) * t,
            width: size.width + (target.size.width - size.width) * t,
            height: size.height + (target.size.height - size.height) * t
        )
    }
}

public extension CGSize {
    static var zero: CGSize { CGSize.zero }
    static var one: CGSize { CGSize(width: 1, height: 1) }
    
    var aspectRatio: CGFloat {
        height != 0 ? width / height : 0
    }
    
    func scaled(by factor: CGFloat) -> CGSize {
        CGSize(width: width * factor, height: height * factor)
    }
    
    func scaled(by factor: CGSize) -> CGSize {
        CGSize(width: width * factor.width, height: height * factor.height)
    }
    
    func aspectFit(in container: CGSize) -> CGSize {
        let containerAspect = container.aspectRatio
        let selfAspect = aspectRatio
        
        if selfAspect > containerAspect {
            return CGSize(width: container.width, height: container.width / selfAspect)
        } else {
            return CGSize(width: container.height * selfAspect, height: container.height)
        }
    }
    
    func aspectFill(in container: CGSize) -> CGSize {
        let containerAspect = container.aspectRatio
        let selfAspect = aspectRatio
        
        if selfAspect > containerAspect {
            return CGSize(width: container.height * selfAspect, height: container.height)
        } else {
            return CGSize(width: container.width, height: container.width / selfAspect)
        }
    }
    
    func lerp(to target: CGSize, t: CGFloat) -> CGSize {
        CGSize(
            width: width + (target.width - width) * t,
            height: height + (target.height - height) * t
        )
    }
}

public extension CGPoint {
    static var zero: CGPoint { CGPoint.zero }
    static var one: CGPoint { CGPoint(x: 1, y: 1) }
    
    var length: CGFloat {
        sqrt(x * x + y * y)
    }
    
    var lengthSquared: CGFloat {
        x * x + y * y
    }
    
    func normalized() -> CGPoint {
        let len = length
        return len > 0 ? CGPoint(x: x / len, y: y / len) : .zero
    }
    
    func distance(to other: CGPoint) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return sqrt(dx * dx + dy * dy)
    }
    
    func dot(_ other: CGPoint) -> CGFloat {
        x * other.x + y * other.y
    }
    
    func lerp(to target: CGPoint, t: CGFloat) -> CGPoint {
        CGPoint(
            x: x + (target.x - x) * t,
            y: y + (target.y - y) * t
        )
    }
    
    func rotated(around center: CGPoint, by angle: CGFloat) -> CGPoint {
        let cos_a = cos(angle)
        let sin_a = sin(angle)
        let dx = x - center.x
        let dy = y - center.y
        
        return CGPoint(
            x: center.x + dx * cos_a - dy * sin_a,
            y: center.y + dx * sin_a + dy * cos_a
        )
    }
    
    func scaled(by factor: CGFloat) -> CGPoint {
        CGPoint(x: x * factor, y: y * factor)
    }
    
    func scaled(by factor: CGSize) -> CGPoint {
        CGPoint(x: x * factor.width, y: y * factor.height)
    }
    
    static func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }
    
    static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }
    
    static func * (lhs: CGPoint, rhs: CGFloat) -> CGPoint {
        CGPoint(x: lhs.x * rhs, y: lhs.y * rhs)
    }
    
    static func / (lhs: CGPoint, rhs: CGFloat) -> CGPoint {
        CGPoint(x: lhs.x / rhs, y: lhs.y / rhs)
    }
}

public struct Transform2D {
    public var translation: SIMD2<Float>
    public var rotation: Float
    public var scale: SIMD2<Float>
    public var anchor: SIMD2<Float>
    
    public init(
        translation: SIMD2<Float> = .zero,
        rotation: Float = 0,
        scale: SIMD2<Float> = .one,
        anchor: SIMD2<Float> = SIMD2<Float>(0.5, 0.5)
    ) {
        self.translation = translation
        self.rotation = rotation
        self.scale = scale
        self.anchor = anchor
    }
    
    public static var identity: Transform2D {
        Transform2D()
    }
    
    public var matrix: simd_float3x3 {
        let cos_r = cos(rotation)
        let sin_r = sin(rotation)
        
        let t = translation
        let s = scale
        let a = anchor
        
        let scaledAnchor = a * s
        let rotatedAnchor = SIMD2<Float>(
            scaledAnchor.x * cos_r - scaledAnchor.y * sin_r,
            scaledAnchor.x * sin_r + scaledAnchor.y * cos_r
        )
        
        let finalTranslation = t + a - rotatedAnchor
        
        return simd_float3x3(
            SIMD3<Float>(s.x * cos_r, s.x * sin_r, 0),
            SIMD3<Float>(-s.y * sin_r, s.y * cos_r, 0),
            SIMD3<Float>(finalTranslation.x, finalTranslation.y, 1)
        )
    }
    
    public func combined(with other: Transform2D) -> Transform2D {
        let m1 = self.matrix
        let m2 = other.matrix
        let result = m1 * m2
        
        let newScale = SIMD2<Float>(
            sqrt(result.columns.0.x * result.columns.0.x + result.columns.0.y * result.columns.0.y),
            sqrt(result.columns.1.x * result.columns.1.x + result.columns.1.y * result.columns.1.y)
        )
        
        let newRotation = atan2(result.columns.0.y / newScale.x, result.columns.0.x / newScale.x)
        let newTranslation = SIMD2<Float>(result.columns.2.x, result.columns.2.y)
        
        return Transform2D(
            translation: newTranslation,
            rotation: newRotation,
            scale: newScale,
            anchor: anchor
        )
    }
    
    public func applying(to point: SIMD2<Float>) -> SIMD2<Float> {
        let m = matrix
        let homogeneous = SIMD3<Float>(point.x, point.y, 1)
        let transformed = m * homogeneous
        return SIMD2<Float>(transformed.x, transformed.y)
    }
    
    public func applying(to rect: CGRect) -> CGRect {
        let corners = [
            SIMD2<Float>(Float(rect.minX), Float(rect.minY)),
            SIMD2<Float>(Float(rect.maxX), Float(rect.minY)),
            SIMD2<Float>(Float(rect.maxX), Float(rect.maxY)),
            SIMD2<Float>(Float(rect.minX), Float(rect.maxY))
        ]
        
        let transformedCorners = corners.map { applying(to: $0) }
        
        let minX = transformedCorners.map { $0.x }.min() ?? 0
        let maxX = transformedCorners.map { $0.x }.max() ?? 0
        let minY = transformedCorners.map { $0.y }.min() ?? 0
        let maxY = transformedCorners.map { $0.y }.max() ?? 0
        
        return CGRect(
            x: CGFloat(minX),
            y: CGFloat(minY),
            width: CGFloat(maxX - minX),
            height: CGFloat(maxY - minY)
        )
    }
    
    public func lerp(to target: Transform2D, t: Float) -> Transform2D {
        Transform2D(
            translation: translation.lerp(to: target.translation, t: t),
            rotation: rotation.lerp(to: target.rotation, t: t),
            scale: scale.lerp(to: target.scale, t: t),
            anchor: anchor.lerp(to: target.anchor, t: t)
        )
    }
}

public extension SIMD2 where Scalar == Float {
    init(_ point: CGPoint) {
        self.init(Float(point.x), Float(point.y))
    }
    
    init(_ size: CGSize) {
        self.init(Float(size.width), Float(size.height))
    }
    
    var cgPoint: CGPoint {
        CGPoint(x: CGFloat(x), y: CGFloat(y))
    }
    
    var cgSize: CGSize {
        CGSize(width: CGFloat(x), height: CGFloat(y))
    }
}

public extension SIMD3 where Scalar == Float {
    init(_ point: CGPoint, z: Float = 0) {
        self.init(Float(point.x), Float(point.y), z)
    }
}

public extension SIMD4 where Scalar == Float {
    init(_ rect: CGRect) {
        self.init(
            Float(rect.origin.x),
            Float(rect.origin.y),
            Float(rect.size.width),
            Float(rect.size.height)
        )
    }
    
    var cgRect: CGRect {
        CGRect(
            x: CGFloat(x),
            y: CGFloat(y),
            width: CGFloat(z),
            height: CGFloat(w)
        )
    }
}

public struct Bounds {
    public var min: SIMD3<Float>
    public var max: SIMD3<Float>
    
    public init(min: SIMD3<Float> = SIMD3<Float>(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude),
                max: SIMD3<Float> = SIMD3<Float>(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)) {
        self.min = min
        self.max = max
    }
    
    public static var empty: Bounds {
        Bounds()
    }
    
    public var center: SIMD3<Float> {
        (min + max) * 0.5
    }
    
    public var size: SIMD3<Float> {
        max - min
    }
    
    public var isEmpty: Bool {
        min.x > max.x || min.y > max.y || min.z > max.z
    }
    
    public mutating func expand(by point: SIMD3<Float>) {
        if isEmpty {
            min = point
            max = point
        } else {
            min = simd_min(min, point)
            max = simd_max(max, point)
        }
    }
    
    public mutating func expand(by bounds: Bounds) {
        if !bounds.isEmpty {
            expand(by: bounds.min)
            expand(by: bounds.max)
        }
    }
    
    public func contains(_ point: SIMD3<Float>) -> Bool {
        !isEmpty &&
        point.x >= min.x && point.x <= max.x &&
        point.y >= min.y && point.y <= max.y &&
        point.z >= min.z && point.z <= max.z
    }
    
    public func intersects(_ other: Bounds) -> Bool {
        !isEmpty && !other.isEmpty &&
        min.x <= other.max.x && max.x >= other.min.x &&
        min.y <= other.max.y && max.y >= other.min.y &&
        min.z <= other.max.z && max.z >= other.min.z
    }
    
    public func union(with other: Bounds) -> Bounds {
        var result = self
        result.expand(by: other)
        return result
    }
    
    public func transformed(by matrix: simd_float4x4) -> Bounds {
        if isEmpty { return .empty }
        
        let corners = [
            SIMD4<Float>(min.x, min.y, min.z, 1),
            SIMD4<Float>(max.x, min.y, min.z, 1),
            SIMD4<Float>(min.x, max.y, min.z, 1),
            SIMD4<Float>(max.x, max.y, min.z, 1),
            SIMD4<Float>(min.x, min.y, max.z, 1),
            SIMD4<Float>(max.x, min.y, max.z, 1),
            SIMD4<Float>(min.x, max.y, max.z, 1),
            SIMD4<Float>(max.x, max.y, max.z, 1)
        ]
        
        var result = Bounds.empty
        for corner in corners {
            let transformed = matrix * corner
            let point = SIMD3<Float>(transformed.x / transformed.w, transformed.y / transformed.w, transformed.z / transformed.w)
            result.expand(by: point)
        }
        
        return result
    }
}