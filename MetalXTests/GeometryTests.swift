import XCTest
import CoreGraphics
@testable import MetalX

final class GeometryTests: XCTestCase {
    
    func testCGRectExtensions() {
        let rect = CGRect(x: 10, y: 20, width: 100, height: 50)
        
        XCTAssertEqual(rect.center.x, 60, accuracy: 0.001)
        XCTAssertEqual(rect.center.y, 45, accuracy: 0.001)
        
        XCTAssertEqual(rect.topLeft.x, 10, accuracy: 0.001)
        XCTAssertEqual(rect.topLeft.y, 20, accuracy: 0.001)
        
        XCTAssertEqual(rect.bottomRight.x, 110, accuracy: 0.001)
        XCTAssertEqual(rect.bottomRight.y, 70, accuracy: 0.001)
        
        XCTAssertEqual(rect.aspectRatio, 2.0, accuracy: 0.001)
        
        let scaled = rect.scaled(by: 2.0)
        XCTAssertEqual(scaled.width, 200, accuracy: 0.001)
        XCTAssertEqual(scaled.height, 100, accuracy: 0.001)
    }
    
    func testCGRectAspectFit() {
        let content = CGRect(x: 0, y: 0, width: 200, height: 100)
        let container = CGRect(x: 0, y: 0, width: 100, height: 100)
        
        let fitted = content.aspectFit(in: container)
        
        XCTAssertEqual(fitted.width, 100, accuracy: 0.001)
        XCTAssertEqual(fitted.height, 50, accuracy: 0.001)
        XCTAssertEqual(fitted.origin.x, 0, accuracy: 0.001)
        XCTAssertEqual(fitted.origin.y, 25, accuracy: 0.001)
    }
    
    func testCGRectAspectFill() {
        let content = CGRect(x: 0, y: 0, width: 100, height: 200)
        let container = CGRect(x: 0, y: 0, width: 100, height: 100)
        
        let filled = content.aspectFill(in: container)
        
        XCTAssertEqual(filled.width, 200, accuracy: 0.001)
        XCTAssertEqual(filled.height, 100, accuracy: 0.001)
        XCTAssertEqual(filled.origin.x, -50, accuracy: 0.001)
        XCTAssertEqual(filled.origin.y, 0, accuracy: 0.001)
    }
    
    func testCGRectNormalization() {
        let rect = CGRect(x: 25, y: 50, width: 50, height: 25)
        let container = CGRect(x: 0, y: 0, width: 100, height: 100)
        
        let normalized = rect.normalized(in: container)
        XCTAssertEqual(normalized.x, 0.25, accuracy: 0.001)
        XCTAssertEqual(normalized.y, 0.5, accuracy: 0.001)
        XCTAssertEqual(normalized.width, 0.5, accuracy: 0.001)
        XCTAssertEqual(normalized.height, 0.25, accuracy: 0.001)
        
        let denormalized = normalized.denormalized(in: container)
        XCTAssertEqual(denormalized.x, rect.x, accuracy: 0.001)
        XCTAssertEqual(denormalized.y, rect.y, accuracy: 0.001)
        XCTAssertEqual(denormalized.width, rect.width, accuracy: 0.001)
        XCTAssertEqual(denormalized.height, rect.height, accuracy: 0.001)
    }
    
    func testCGRectLerp() {
        let rect1 = CGRect(x: 0, y: 0, width: 100, height: 100)
        let rect2 = CGRect(x: 100, y: 100, width: 200, height: 200)
        
        let lerped = rect1.lerp(to: rect2, t: 0.5)
        XCTAssertEqual(lerped.x, 50, accuracy: 0.001)
        XCTAssertEqual(lerped.y, 50, accuracy: 0.001)
        XCTAssertEqual(lerped.width, 150, accuracy: 0.001)
        XCTAssertEqual(lerped.height, 150, accuracy: 0.001)
    }
    
    func testCGSizeExtensions() {
        let size1 = CGSize(width: 100, height: 50)
        let size2 = CGSize(width: 50, height: 100)
        
        XCTAssertEqual(size1.aspectRatio, 2.0, accuracy: 0.001)
        XCTAssertEqual(size2.aspectRatio, 0.5, accuracy: 0.001)
        
        let scaled = size1.scaled(by: 2.0)
        XCTAssertEqual(scaled.width, 200, accuracy: 0.001)
        XCTAssertEqual(scaled.height, 100, accuracy: 0.001)
        
        let lerped = size1.lerp(to: size2, t: 0.5)
        XCTAssertEqual(lerped.width, 75, accuracy: 0.001)
        XCTAssertEqual(lerped.height, 75, accuracy: 0.001)
    }
    
    func testCGSizeAspectFit() {
        let content = CGSize(width: 200, height: 100)
        let container = CGSize(width: 100, height: 100)
        
        let fitted = content.aspectFit(in: container)
        XCTAssertEqual(fitted.width, 100, accuracy: 0.001)
        XCTAssertEqual(fitted.height, 50, accuracy: 0.001)
    }
    
    func testCGPointExtensions() {
        let point1 = CGPoint(x: 3, y: 4)
        let point2 = CGPoint(x: 0, y: 0)
        
        XCTAssertEqual(point1.length, 5.0, accuracy: 0.001)
        XCTAssertEqual(point1.lengthSquared, 25.0, accuracy: 0.001)
        
        let normalized = point1.normalized()
        XCTAssertEqual(normalized.length, 1.0, accuracy: 0.001)
        
        XCTAssertEqual(point1.distance(to: point2), 5.0, accuracy: 0.001)
        
        let lerped = point1.lerp(to: point2, t: 0.5)
        XCTAssertEqual(lerped.x, 1.5, accuracy: 0.001)
        XCTAssertEqual(lerped.y, 2.0, accuracy: 0.001)
    }
    
    func testCGPointRotation() {
        let point = CGPoint(x: 1, y: 0)
        let center = CGPoint.zero
        let rotated = point.rotated(around: center, by: .pi / 2)
        
        XCTAssertEqual(rotated.x, 0, accuracy: 0.001)
        XCTAssertEqual(rotated.y, 1, accuracy: 0.001)
    }
    
    func testCGPointOperators() {
        let point1 = CGPoint(x: 1, y: 2)
        let point2 = CGPoint(x: 3, y: 4)
        
        let sum = point1 + point2
        XCTAssertEqual(sum.x, 4, accuracy: 0.001)
        XCTAssertEqual(sum.y, 6, accuracy: 0.001)
        
        let diff = point2 - point1
        XCTAssertEqual(diff.x, 2, accuracy: 0.001)
        XCTAssertEqual(diff.y, 2, accuracy: 0.001)
        
        let scaled = point1 * 2
        XCTAssertEqual(scaled.x, 2, accuracy: 0.001)
        XCTAssertEqual(scaled.y, 4, accuracy: 0.001)
    }
    
    func testTransform2D() {
        let transform = Transform2D(
            translation: SIMD2<Float>(10, 20),
            rotation: .pi / 4,
            scale: SIMD2<Float>(2, 2),
            anchor: SIMD2<Float>(0.5, 0.5)
        )
        
        let point = SIMD2<Float>(0, 0)
        let transformed = transform.applying(to: point)
        
        XCTAssertTrue(transformed.x > 0)
        XCTAssertTrue(transformed.y > 0)
        
        let identity = Transform2D.identity
        let identityPoint = identity.applying(to: point)
        XCTAssertEqual(identityPoint.x, 0, accuracy: 0.001)
        XCTAssertEqual(identityPoint.y, 0, accuracy: 0.001)
    }
    
    func testTransform2DCombination() {
        let transform1 = Transform2D(translation: SIMD2<Float>(10, 0))
        let transform2 = Transform2D(scale: SIMD2<Float>(2, 2))
        
        let combined = transform1.combined(with: transform2)
        
        let point = SIMD2<Float>(1, 1)
        let result1 = transform2.applying(to: transform1.applying(to: point))
        let result2 = combined.applying(to: point)
        
        XCTAssertEqual(result1.x, result2.x, accuracy: 0.1)
        XCTAssertEqual(result1.y, result2.y, accuracy: 0.1)
    }
    
    func testSIMDCGConversions() {
        let point = CGPoint(x: 10, y: 20)
        let simd2 = SIMD2<Float>(point)
        
        XCTAssertEqual(simd2.x, 10, accuracy: 0.001)
        XCTAssertEqual(simd2.y, 20, accuracy: 0.001)
        
        let backToPoint = simd2.cgPoint
        XCTAssertEqual(backToPoint.x, point.x, accuracy: 0.001)
        XCTAssertEqual(backToPoint.y, point.y, accuracy: 0.001)
        
        let rect = CGRect(x: 1, y: 2, width: 3, height: 4)
        let simd4 = SIMD4<Float>(rect)
        let backToRect = simd4.cgRect
        
        XCTAssertEqual(backToRect.x, rect.x, accuracy: 0.001)
        XCTAssertEqual(backToRect.y, rect.y, accuracy: 0.001)
        XCTAssertEqual(backToRect.width, rect.width, accuracy: 0.001)
        XCTAssertEqual(backToRect.height, rect.height, accuracy: 0.001)
    }
    
    func testBounds() {
        var bounds = Bounds.empty
        XCTAssertTrue(bounds.isEmpty)
        
        bounds.expand(by: SIMD3<Float>(1, 2, 3))
        XCTAssertFalse(bounds.isEmpty)
        XCTAssertEqual(bounds.min.x, 1, accuracy: 0.001)
        XCTAssertEqual(bounds.min.y, 2, accuracy: 0.001)
        XCTAssertEqual(bounds.min.z, 3, accuracy: 0.001)
        
        bounds.expand(by: SIMD3<Float>(-1, -2, -3))
        XCTAssertEqual(bounds.size.x, 2, accuracy: 0.001)
        XCTAssertEqual(bounds.size.y, 4, accuracy: 0.001)
        XCTAssertEqual(bounds.size.z, 6, accuracy: 0.001)
        
        let center = bounds.center
        XCTAssertEqual(center.x, 0, accuracy: 0.001)
        XCTAssertEqual(center.y, 0, accuracy: 0.001)
        XCTAssertEqual(center.z, 0, accuracy: 0.001)
    }
    
    func testBoundsTransformation() {
        var bounds = Bounds.empty
        bounds.expand(by: SIMD3<Float>(-1, -1, -1))
        bounds.expand(by: SIMD3<Float>(1, 1, 1))
        
        let transform = simd_float4x4(scale: 2.0)
        let transformed = bounds.transformed(by: transform)
        
        XCTAssertEqual(transformed.size.x, 4, accuracy: 0.001)
        XCTAssertEqual(transformed.size.y, 4, accuracy: 0.001)
        XCTAssertEqual(transformed.size.z, 4, accuracy: 0.001)
    }
    
    func testBoundsIntersection() {
        var bounds1 = Bounds.empty
        bounds1.expand(by: SIMD3<Float>(0, 0, 0))
        bounds1.expand(by: SIMD3<Float>(2, 2, 2))
        
        var bounds2 = Bounds.empty
        bounds2.expand(by: SIMD3<Float>(1, 1, 1))
        bounds2.expand(by: SIMD3<Float>(3, 3, 3))
        
        XCTAssertTrue(bounds1.intersects(bounds2))
        
        let point = SIMD3<Float>(1.5, 1.5, 1.5)
        XCTAssertTrue(bounds1.contains(point))
        XCTAssertTrue(bounds2.contains(point))
        
        let union = bounds1.union(with: bounds2)
        XCTAssertEqual(union.min.x, 0, accuracy: 0.001)
        XCTAssertEqual(union.max.x, 3, accuracy: 0.001)
    }
}