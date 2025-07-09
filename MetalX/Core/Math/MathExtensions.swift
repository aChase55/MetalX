import simd
import Foundation
import Metal

public extension SIMD2 where Scalar == Float {
    static var zero: SIMD2<Float> { SIMD2<Float>(0, 0) }
    static var one: SIMD2<Float> { SIMD2<Float>(1, 1) }
    
    var length: Float { sqrt(x*x + y*y) }
    var lengthSquared: Float { x*x + y*y }
    
    func normalized() -> SIMD2<Float> {
        let len = length
        return len > 0 ? self / len : .zero
    }
    
    func distance(to other: SIMD2<Float>) -> Float {
        (self - other).length
    }
    
    func dot(_ other: SIMD2<Float>) -> Float {
        x * other.x + y * other.y
    }
    
    func lerp(to target: SIMD2<Float>, t: Float) -> SIMD2<Float> {
        self + (target - self) * t
    }
}

public extension SIMD3 where Scalar == Float {
    static var zero: SIMD3<Float> { SIMD3<Float>(0, 0, 0) }
    static var one: SIMD3<Float> { SIMD3<Float>(1, 1, 1) }
    static var right: SIMD3<Float> { SIMD3<Float>(1, 0, 0) }
    static var up: SIMD3<Float> { SIMD3<Float>(0, 1, 0) }
    static var forward: SIMD3<Float> { SIMD3<Float>(0, 0, 1) }
    
    var length: Float { sqrt(x*x + y*y + z*z) }
    var lengthSquared: Float { x*x + y*y + z*z }
    
    func normalized() -> SIMD3<Float> {
        let len = length
        return len > 0 ? self / len : .zero
    }
    
    func distance(to other: SIMD3<Float>) -> Float {
        (self - other).length
    }
    
    func dot(_ other: SIMD3<Float>) -> Float {
        x * other.x + y * other.y + z * other.z
    }
    
    func cross(_ other: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(
            y * other.z - z * other.y,
            z * other.x - x * other.z,
            x * other.y - y * other.x
        )
    }
    
    func lerp(to target: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        self + (target - self) * t
    }
    
    var xy: SIMD2<Float> { SIMD2<Float>(x, y) }
    var xz: SIMD2<Float> { SIMD2<Float>(x, z) }
    var yz: SIMD2<Float> { SIMD2<Float>(y, z) }
}

public extension SIMD4 where Scalar == Float {
    static var zero: SIMD4<Float> { SIMD4<Float>(0, 0, 0, 0) }
    static var one: SIMD4<Float> { SIMD4<Float>(1, 1, 1, 1) }
    
    var xyz: SIMD3<Float> { SIMD3<Float>(x, y, z) }
    var xy: SIMD2<Float> { SIMD2<Float>(x, y) }
    
    func lerp(to target: SIMD4<Float>, t: Float) -> SIMD4<Float> {
        self + (target - self) * t
    }
}

public extension simd_float4x4 {
    static var identity: simd_float4x4 {
        matrix_identity_float4x4
    }
    
    init(translation: SIMD3<Float>) {
        self = matrix_identity_float4x4
        self.columns.3 = SIMD4<Float>(translation, 1)
    }
    
    init(scale: SIMD3<Float>) {
        self = matrix_identity_float4x4
        self.columns.0.x = scale.x
        self.columns.1.y = scale.y
        self.columns.2.z = scale.z
    }
    
    init(scale: Float) {
        self.init(scale: SIMD3<Float>(scale, scale, scale))
    }
    
    init(rotationX angle: Float) {
        let c = cos(angle)
        let s = sin(angle)
        self = matrix_identity_float4x4
        self.columns.1.y = c
        self.columns.1.z = s
        self.columns.2.y = -s
        self.columns.2.z = c
    }
    
    init(rotationY angle: Float) {
        let c = cos(angle)
        let s = sin(angle)
        self = matrix_identity_float4x4
        self.columns.0.x = c
        self.columns.0.z = -s
        self.columns.2.x = s
        self.columns.2.z = c
    }
    
    init(rotationZ angle: Float) {
        let c = cos(angle)
        let s = sin(angle)
        self = matrix_identity_float4x4
        self.columns.0.x = c
        self.columns.0.y = s
        self.columns.1.x = -s
        self.columns.1.y = c
    }
    
    init(rotation axis: SIMD3<Float>, angle: Float) {
        let normalized = axis.normalized()
        let c = cos(angle)
        let s = sin(angle)
        let t = 1 - c
        
        let x = normalized.x
        let y = normalized.y
        let z = normalized.z
        
        self.init(
            SIMD4<Float>(t*x*x + c,    t*x*y + s*z,  t*x*z - s*y,  0),
            SIMD4<Float>(t*x*y - s*z,  t*y*y + c,    t*y*z + s*x,  0),
            SIMD4<Float>(t*x*z + s*y,  t*y*z - s*x,  t*z*z + c,    0),
            SIMD4<Float>(0,            0,            0,            1)
        )
    }
    
    static func perspective(fovRadians: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let ys = 1 / tan(fovRadians * 0.5)
        let xs = ys / aspect
        let zs = far / (near - far)
        
        return simd_float4x4(
            SIMD4<Float>(xs, 0,  0,          0),
            SIMD4<Float>(0,  ys, 0,          0),
            SIMD4<Float>(0,  0,  zs,         -1),
            SIMD4<Float>(0,  0,  zs * near,  0)
        )
    }
    
    static func orthographic(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) -> simd_float4x4 {
        let sx = 2 / (right - left)
        let sy = 2 / (top - bottom)
        let sz = 1 / (near - far)
        let tx = (left + right) / (left - right)
        let ty = (bottom + top) / (bottom - top)
        let tz = near / (near - far)
        
        return simd_float4x4(
            SIMD4<Float>(sx, 0,  0,  0),
            SIMD4<Float>(0,  sy, 0,  0),
            SIMD4<Float>(0,  0,  sz, 0),
            SIMD4<Float>(tx, ty, tz, 1)
        )
    }
    
    static func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let z = (eye - target).normalized()
        let x = up.cross(z).normalized()
        let y = z.cross(x)
        
        return simd_float4x4(
            SIMD4<Float>(x.x, y.x, z.x, 0),
            SIMD4<Float>(x.y, y.y, z.y, 0),
            SIMD4<Float>(x.z, y.z, z.z, 0),
            SIMD4<Float>(-x.dot(eye), -y.dot(eye), -z.dot(eye), 1)
        )
    }
    
    var translation: SIMD3<Float> {
        get { columns.3.xyz }
        set { columns.3 = SIMD4<Float>(newValue, 1) }
    }
    
    var scale: SIMD3<Float> {
        SIMD3<Float>(
            columns.0.xyz.length,
            columns.1.xyz.length,
            columns.2.xyz.length
        )
    }
    
    func translated(by offset: SIMD3<Float>) -> simd_float4x4 {
        var result = self
        result.translation += offset
        return result
    }
    
    func scaled(by factor: SIMD3<Float>) -> simd_float4x4 {
        self * simd_float4x4(scale: factor)
    }
    
    func scaled(by factor: Float) -> simd_float4x4 {
        scaled(by: SIMD3<Float>(factor, factor, factor))
    }
}

public struct Quaternion {
    public var x: Float
    public var y: Float
    public var z: Float
    public var w: Float
    
    public init(x: Float = 0, y: Float = 0, z: Float = 0, w: Float = 1) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }
    
    public init(axis: SIMD3<Float>, angle: Float) {
        let halfAngle = angle * 0.5
        let s = sin(halfAngle)
        let normalized = axis.normalized()
        
        self.x = normalized.x * s
        self.y = normalized.y * s
        self.z = normalized.z * s
        self.w = cos(halfAngle)
    }
    
    public static var identity: Quaternion {
        Quaternion(x: 0, y: 0, z: 0, w: 1)
    }
    
    public var length: Float {
        sqrt(x*x + y*y + z*z + w*w)
    }
    
    public func normalized() -> Quaternion {
        let len = length
        return len > 0 ? Quaternion(x: x/len, y: y/len, z: z/len, w: w/len) : .identity
    }
    
    public func conjugate() -> Quaternion {
        Quaternion(x: -x, y: -y, z: -z, w: w)
    }
    
    public func multiply(_ other: Quaternion) -> Quaternion {
        Quaternion(
            x: w * other.x + x * other.w + y * other.z - z * other.y,
            y: w * other.y - x * other.z + y * other.w + z * other.x,
            z: w * other.z + x * other.y - y * other.x + z * other.w,
            w: w * other.w - x * other.x - y * other.y - z * other.z
        )
    }
    
    public var matrix: simd_float4x4 {
        let xx = x * x
        let yy = y * y
        let zz = z * z
        let xy = x * y
        let xz = x * z
        let yz = y * z
        let wx = w * x
        let wy = w * y
        let wz = w * z
        
        return simd_float4x4(
            SIMD4<Float>(1 - 2*(yy + zz), 2*(xy + wz),     2*(xz - wy),     0),
            SIMD4<Float>(2*(xy - wz),     1 - 2*(xx + zz), 2*(yz + wx),     0),
            SIMD4<Float>(2*(xz + wy),     2*(yz - wx),     1 - 2*(xx + yy), 0),
            SIMD4<Float>(0,               0,               0,               1)
        )
    }
    
    public func slerp(to target: Quaternion, t: Float) -> Quaternion {
        let dot = x * target.x + y * target.y + z * target.z + w * target.w
        let adjustedTarget = dot < 0 ? Quaternion(x: -target.x, y: -target.y, z: -target.z, w: -target.w) : target
        let adjustedDot = abs(dot)
        
        if adjustedDot > 0.9995 {
            return Quaternion(
                x: x + t * (adjustedTarget.x - x),
                y: y + t * (adjustedTarget.y - y),
                z: z + t * (adjustedTarget.z - z),
                w: w + t * (adjustedTarget.w - w)
            ).normalized()
        }
        
        let theta = acos(adjustedDot)
        let sinTheta = sin(theta)
        let a = sin((1 - t) * theta) / sinTheta
        let b = sin(t * theta) / sinTheta
        
        return Quaternion(
            x: a * x + b * adjustedTarget.x,
            y: a * y + b * adjustedTarget.y,
            z: a * z + b * adjustedTarget.z,
            w: a * w + b * adjustedTarget.w
        )
    }
}

public struct BezierCurve {
    public let p0: SIMD2<Float>
    public let p1: SIMD2<Float>
    public let p2: SIMD2<Float>
    public let p3: SIMD2<Float>
    
    public init(p0: SIMD2<Float>, p1: SIMD2<Float>, p2: SIMD2<Float>, p3: SIMD2<Float>) {
        self.p0 = p0
        self.p1 = p1
        self.p2 = p2
        self.p3 = p3
    }
    
    public func point(at t: Float) -> SIMD2<Float> {
        let u = 1 - t
        let tt = t * t
        let uu = u * u
        let uuu = uu * u
        let ttt = tt * t
        
        return uuu * p0 + 3 * uu * t * p1 + 3 * u * tt * p2 + ttt * p3
    }
    
    public func tangent(at t: Float) -> SIMD2<Float> {
        let u = 1 - t
        let tt = t * t
        let uu = u * u
        
        let term1 = 3 * uu * (p1 - p0)
        let term2 = 6 * u * t * (p2 - p1)
        let term3 = 3 * tt * (p3 - p2)
        
        return term1 + term2 + term3
    }
    
    public func subdivide(at t: Float) -> (BezierCurve, BezierCurve) {
        let q0 = p0.lerp(to: p1, t: t)
        let q1 = p1.lerp(to: p2, t: t)
        let q2 = p2.lerp(to: p3, t: t)
        
        let r0 = q0.lerp(to: q1, t: t)
        let r1 = q1.lerp(to: q2, t: t)
        
        let s = r0.lerp(to: r1, t: t)
        
        let left = BezierCurve(p0: p0, p1: q0, p2: r0, p3: s)
        let right = BezierCurve(p0: s, p1: r1, p2: q2, p3: p3)
        
        return (left, right)
    }
}

public extension SIMD3 where Scalar == Float {
    func toRGB() -> SIMD3<Float> {
        self
    }
    
    func toHSV() -> SIMD3<Float> {
        let r = x
        let g = y
        let b = z
        
        let maxVal = max(r, max(g, b))
        let minVal = min(r, min(g, b))
        let diff = maxVal - minVal
        
        var h: Float = 0
        let s: Float = maxVal == 0 ? 0 : diff / maxVal
        let v: Float = maxVal
        
        if diff != 0 {
            if maxVal == r {
                h = (g - b) / diff + (g < b ? 6 : 0)
            } else if maxVal == g {
                h = (b - r) / diff + 2
            } else {
                h = (r - g) / diff + 4
            }
            h /= 6
        }
        
        return SIMD3<Float>(h, s, v)
    }
    
    func fromHSV() -> SIMD3<Float> {
        let h = x * 6
        let s = y
        let v = z
        
        let c = v * s
        let x_val = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = v - c
        
        var rgb: SIMD3<Float>
        
        if h < 1 {
            rgb = SIMD3<Float>(c, x_val, 0)
        } else if h < 2 {
            rgb = SIMD3<Float>(x_val, c, 0)
        } else if h < 3 {
            rgb = SIMD3<Float>(0, c, x_val)
        } else if h < 4 {
            rgb = SIMD3<Float>(0, x_val, c)
        } else if h < 5 {
            rgb = SIMD3<Float>(x_val, 0, c)
        } else {
            rgb = SIMD3<Float>(c, 0, x_val)
        }
        
        return rgb + SIMD3<Float>(m, m, m)
    }
    
    func toSRGB() -> SIMD3<Float> {
        func linearToSRGB(_ linear: Float) -> Float {
            return linear <= 0.0031308 ? 12.92 * linear : 1.055 * pow(linear, 1.0/2.4) - 0.055
        }
        return SIMD3<Float>(linearToSRGB(x), linearToSRGB(y), linearToSRGB(z))
    }
    
    func fromSRGB() -> SIMD3<Float> {
        func sRGBToLinear(_ srgb: Float) -> Float {
            return srgb <= 0.04045 ? srgb / 12.92 : pow((srgb + 0.055) / 1.055, 2.4)
        }
        return SIMD3<Float>(sRGBToLinear(x), sRGBToLinear(y), sRGBToLinear(z))
    }
}

public extension Float {
    func lerp(to target: Float, t: Float) -> Float {
        self + (target - self) * t
    }
    
    func clamp(min: Float, max: Float) -> Float {
        Swift.max(min, Swift.min(max, self))
    }
    
    func smoothstep(edge0: Float, edge1: Float) -> Float {
        let t = ((self - edge0) / (edge1 - edge0)).clamp(min: 0, max: 1)
        return t * t * (3 - 2 * t)
    }
    
    var radians: Float { self * .pi / 180 }
    var degrees: Float { self * 180 / .pi }
}

public extension Double {
    func lerp(to target: Double, t: Double) -> Double {
        self + (target - self) * t
    }
    
    func clamp(min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, self))
    }
    
    var radians: Double { self * .pi / 180 }
    var degrees: Double { self * 180 / .pi }
}