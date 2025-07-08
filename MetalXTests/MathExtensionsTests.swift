import XCTest
import simd
@testable import MetalX

final class MathExtensionsTests: XCTestCase {
    
    func testSIMD2Extensions() {
        let vec1 = SIMD2<Float>(3, 4)
        let vec2 = SIMD2<Float>(1, 2)
        
        XCTAssertEqual(vec1.length, 5.0, accuracy: 0.001)
        XCTAssertEqual(vec1.lengthSquared, 25.0, accuracy: 0.001)
        
        let normalized = vec1.normalized()
        XCTAssertEqual(normalized.length, 1.0, accuracy: 0.001)
        
        XCTAssertEqual(vec1.distance(to: vec2), sqrt(8), accuracy: 0.001)
        XCTAssertEqual(vec1.dot(vec2), 11.0, accuracy: 0.001)
        
        let lerped = vec1.lerp(to: vec2, t: 0.5)
        XCTAssertEqual(lerped.x, 2.0, accuracy: 0.001)
        XCTAssertEqual(lerped.y, 3.0, accuracy: 0.001)
    }
    
    func testSIMD3Extensions() {
        let vec1 = SIMD3<Float>(1, 0, 0)
        let vec2 = SIMD3<Float>(0, 1, 0)
        
        let cross = vec1.cross(vec2)
        XCTAssertEqual(cross.x, 0.0, accuracy: 0.001)
        XCTAssertEqual(cross.y, 0.0, accuracy: 0.001)
        XCTAssertEqual(cross.z, 1.0, accuracy: 0.001)
        
        XCTAssertEqual(vec1.dot(vec2), 0.0, accuracy: 0.001)
        
        let up = SIMD3<Float>.up
        XCTAssertEqual(up.y, 1.0)
        XCTAssertEqual(up.x, 0.0)
        XCTAssertEqual(up.z, 0.0)
    }
    
    func testMatrix4x4() {
        let identity = simd_float4x4.identity
        let translation = simd_float4x4(translation: SIMD3<Float>(1, 2, 3))
        
        XCTAssertEqual(translation.translation.x, 1.0, accuracy: 0.001)
        XCTAssertEqual(translation.translation.y, 2.0, accuracy: 0.001)
        XCTAssertEqual(translation.translation.z, 3.0, accuracy: 0.001)
        
        let scale = simd_float4x4(scale: 2.0)
        let scaled = scale.scale
        XCTAssertEqual(scaled.x, 2.0, accuracy: 0.001)
        XCTAssertEqual(scaled.y, 2.0, accuracy: 0.001)
        XCTAssertEqual(scaled.z, 2.0, accuracy: 0.001)
        
        let rotationX = simd_float4x4(rotationX: .pi / 2)
        let testVec = SIMD4<Float>(0, 1, 0, 1)
        let rotated = rotationX * testVec
        XCTAssertEqual(rotated.x, 0.0, accuracy: 0.001)
        XCTAssertEqual(rotated.y, 0.0, accuracy: 0.001)
        XCTAssertEqual(rotated.z, 1.0, accuracy: 0.001)
    }
    
    func testQuaternion() {
        let identity = Quaternion.identity
        XCTAssertEqual(identity.w, 1.0, accuracy: 0.001)
        XCTAssertEqual(identity.x, 0.0, accuracy: 0.001)
        
        let rotX = Quaternion(axis: SIMD3<Float>(1, 0, 0), angle: .pi / 2)
        let normalized = rotX.normalized()
        XCTAssertEqual(normalized.length, 1.0, accuracy: 0.001)
        
        let conjugate = rotX.conjugate()
        XCTAssertEqual(conjugate.x, -rotX.x, accuracy: 0.001)
        XCTAssertEqual(conjugate.w, rotX.w, accuracy: 0.001)
        
        let slerped = identity.slerp(to: rotX, t: 0.5)
        XCTAssertTrue(slerped.length > 0.99)
    }
    
    func testBezierCurve() {
        let curve = BezierCurve(
            p0: SIMD2<Float>(0, 0),
            p1: SIMD2<Float>(1, 0),
            p2: SIMD2<Float>(1, 1),
            p3: SIMD2<Float>(0, 1)
        )
        
        let start = curve.point(at: 0)
        XCTAssertEqual(start.x, 0.0, accuracy: 0.001)
        XCTAssertEqual(start.y, 0.0, accuracy: 0.001)
        
        let end = curve.point(at: 1)
        XCTAssertEqual(end.x, 0.0, accuracy: 0.001)
        XCTAssertEqual(end.y, 1.0, accuracy: 0.001)
        
        let middle = curve.point(at: 0.5)
        XCTAssertTrue(middle.x > 0)
        XCTAssertTrue(middle.y > 0)
        
        let (left, right) = curve.subdivide(at: 0.5)
        let leftEnd = left.point(at: 1)
        let rightStart = right.point(at: 0)
        XCTAssertEqual(leftEnd.x, rightStart.x, accuracy: 0.001)
        XCTAssertEqual(leftEnd.y, rightStart.y, accuracy: 0.001)
    }
    
    func testColorConversions() {
        let red = SIMD3<Float>(1, 0, 0)
        let hsv = red.toHSV()
        let backToRGB = hsv.fromHSV()
        
        XCTAssertEqual(backToRGB.x, red.x, accuracy: 0.001)
        XCTAssertEqual(backToRGB.y, red.y, accuracy: 0.001)
        XCTAssertEqual(backToRGB.z, red.z, accuracy: 0.001)
        
        let linear = SIMD3<Float>(0.5, 0.5, 0.5)
        let srgb = linear.toSRGB()
        let backToLinear = srgb.fromSRGB()
        
        XCTAssertEqual(backToLinear.x, linear.x, accuracy: 0.01)
        XCTAssertEqual(backToLinear.y, linear.y, accuracy: 0.01)
        XCTAssertEqual(backToLinear.z, linear.z, accuracy: 0.01)
    }
    
    func testFloatExtensions() {
        let value: Float = 0.5
        let lerped = value.lerp(to: 1.0, t: 0.5)
        XCTAssertEqual(lerped, 0.75, accuracy: 0.001)
        
        let clamped = Float(1.5).clamp(min: 0, max: 1)
        XCTAssertEqual(clamped, 1.0, accuracy: 0.001)
        
        let smoothed = Float(0.5).smoothstep(edge0: 0, edge1: 1)
        XCTAssertEqual(smoothed, 0.5, accuracy: 0.001)
        
        let radians = Float(90).radians
        XCTAssertEqual(radians, .pi / 2, accuracy: 0.001)
        
        let degrees = (.pi / 2).degrees
        XCTAssertEqual(degrees, 90, accuracy: 0.001)
    }
    
    func testPerspectiveMatrix() {
        let perspective = simd_float4x4.perspective(
            fovRadians: .pi / 4,
            aspect: 16.0 / 9.0,
            near: 0.1,
            far: 100.0
        )
        
        XCTAssertTrue(perspective.columns.0.x > 0)
        XCTAssertTrue(perspective.columns.1.y > 0)
        XCTAssertTrue(perspective.columns.2.z < 0)
        XCTAssertEqual(perspective.columns.2.w, -1, accuracy: 0.001)
    }
    
    func testOrthographicMatrix() {
        let ortho = simd_float4x4.orthographic(
            left: -1, right: 1,
            bottom: -1, top: 1,
            near: 0.1, far: 100.0
        )
        
        XCTAssertEqual(ortho.columns.0.x, 1.0, accuracy: 0.001)
        XCTAssertEqual(ortho.columns.1.y, 1.0, accuracy: 0.001)
        XCTAssertTrue(ortho.columns.2.z < 0)
        XCTAssertEqual(ortho.columns.3.w, 1.0, accuracy: 0.001)
    }
    
    func testLookAtMatrix() {
        let lookAt = simd_float4x4.lookAt(
            eye: SIMD3<Float>(0, 0, 5),
            target: SIMD3<Float>(0, 0, 0),
            up: SIMD3<Float>(0, 1, 0)
        )
        
        XCTAssertEqual(lookAt.columns.3.z, -5.0, accuracy: 0.001)
        XCTAssertEqual(lookAt.columns.3.w, 1.0, accuracy: 0.001)
    }
    
    func testMatrixTransformations() {
        let base = simd_float4x4.identity
        let translated = base.translated(by: SIMD3<Float>(1, 2, 3))
        
        XCTAssertEqual(translated.translation.x, 1.0, accuracy: 0.001)
        XCTAssertEqual(translated.translation.y, 2.0, accuracy: 0.001)
        XCTAssertEqual(translated.translation.z, 3.0, accuracy: 0.001)
        
        let scaled = base.scaled(by: 2.0)
        let scale = scaled.scale
        XCTAssertEqual(scale.x, 2.0, accuracy: 0.001)
        XCTAssertEqual(scale.y, 2.0, accuracy: 0.001)
        XCTAssertEqual(scale.z, 2.0, accuracy: 0.001)
    }
    
    func testQuaternionMatrix() {
        let quat = Quaternion(axis: SIMD3<Float>(0, 1, 0), angle: .pi / 2)
        let matrix = quat.matrix
        
        let testPoint = SIMD4<Float>(1, 0, 0, 1)
        let rotated = matrix * testPoint
        
        XCTAssertEqual(rotated.x, 0.0, accuracy: 0.001)
        XCTAssertEqual(rotated.y, 0.0, accuracy: 0.001)
        XCTAssertEqual(rotated.z, -1.0, accuracy: 0.001)
    }
}