import CoreGraphics
import UIKit

struct AlignmentGuide {
    enum Axis {
        case horizontal
        case vertical
    }
    
    let position: CGFloat
    let axis: Axis
    let isCenter: Bool
}

class AlignmentEngine {
    let snapThreshold: CGFloat = 10.0
    
    func findAlignmentGuides(for layer: Layer, in layers: [Layer], canvasSize: CGSize) -> [AlignmentGuide] {
        var guides: [AlignmentGuide] = []
        
        let movingBounds = layer.getBounds(includeEffects: false)
        let movingCenter = CGPoint(
            x: movingBounds.midX,
            y: movingBounds.midY
        )
        
        // Canvas guides - edges and center
        // Vertical guides
        guides.append(AlignmentGuide(position: 0, axis: .vertical, isCenter: false)) // Left edge
        guides.append(AlignmentGuide(position: canvasSize.width / 2, axis: .vertical, isCenter: true)) // Center
        guides.append(AlignmentGuide(position: canvasSize.width, axis: .vertical, isCenter: false)) // Right edge
        
        // Horizontal guides
        guides.append(AlignmentGuide(position: 0, axis: .horizontal, isCenter: false)) // Top edge
        guides.append(AlignmentGuide(position: canvasSize.height / 2, axis: .horizontal, isCenter: true)) // Center
        guides.append(AlignmentGuide(position: canvasSize.height, axis: .horizontal, isCenter: false)) // Bottom edge
        
        // Check against other layers
        for otherLayer in layers where otherLayer.id != layer.id {
            let otherBounds = otherLayer.getBounds(includeEffects: false)
            let otherCenter = CGPoint(
                x: otherBounds.midX,
                y: otherBounds.midY
            )
            
            // Vertical alignment (left, center, right)
            if abs(movingBounds.minX - otherBounds.minX) < snapThreshold {
                guides.append(AlignmentGuide(position: otherBounds.minX, axis: .vertical, isCenter: false))
            }
            if abs(movingCenter.x - otherCenter.x) < snapThreshold {
                guides.append(AlignmentGuide(position: otherCenter.x, axis: .vertical, isCenter: true))
            }
            if abs(movingBounds.maxX - otherBounds.maxX) < snapThreshold {
                guides.append(AlignmentGuide(position: otherBounds.maxX, axis: .vertical, isCenter: false))
            }
            
            // Also check edge-to-edge alignment
            if abs(movingBounds.minX - otherBounds.maxX) < snapThreshold {
                guides.append(AlignmentGuide(position: otherBounds.maxX, axis: .vertical, isCenter: false))
            }
            if abs(movingBounds.maxX - otherBounds.minX) < snapThreshold {
                guides.append(AlignmentGuide(position: otherBounds.minX, axis: .vertical, isCenter: false))
            }
            
            // Horizontal alignment (top, center, bottom)
            if abs(movingBounds.minY - otherBounds.minY) < snapThreshold {
                guides.append(AlignmentGuide(position: otherBounds.minY, axis: .horizontal, isCenter: false))
            }
            if abs(movingCenter.y - otherCenter.y) < snapThreshold {
                guides.append(AlignmentGuide(position: otherCenter.y, axis: .horizontal, isCenter: true))
            }
            if abs(movingBounds.maxY - otherBounds.maxY) < snapThreshold {
                guides.append(AlignmentGuide(position: otherBounds.maxY, axis: .horizontal, isCenter: false))
            }
            
            // Also check edge-to-edge alignment
            if abs(movingBounds.minY - otherBounds.maxY) < snapThreshold {
                guides.append(AlignmentGuide(position: otherBounds.maxY, axis: .horizontal, isCenter: false))
            }
            if abs(movingBounds.maxY - otherBounds.minY) < snapThreshold {
                guides.append(AlignmentGuide(position: otherBounds.minY, axis: .horizontal, isCenter: false))
            }
        }
        
        return guides
    }
    
    func snapPosition(_ position: CGPoint, for layer: Layer, guides: [AlignmentGuide]) -> CGPoint {
        var snappedPosition = position
        let bounds = layer.bounds
        let scaledBounds = CGRect(
            x: 0,
            y: 0,
            width: bounds.width * layer.transform.scale,
            height: bounds.height * layer.transform.scale
        )
        
        // Check vertical guides
        for guide in guides where guide.axis == .vertical {
            // Check left edge
            let leftEdge = position.x - scaledBounds.width / 2
            if abs(leftEdge - guide.position) < snapThreshold {
                snappedPosition.x = guide.position + scaledBounds.width / 2
                break
            }
            
            // Check center
            if abs(position.x - guide.position) < snapThreshold {
                snappedPosition.x = guide.position
                break
            }
            
            // Check right edge
            let rightEdge = position.x + scaledBounds.width / 2
            if abs(rightEdge - guide.position) < snapThreshold {
                snappedPosition.x = guide.position - scaledBounds.width / 2
                break
            }
        }
        
        // Check horizontal guides
        for guide in guides where guide.axis == .horizontal {
            // Check top edge
            let topEdge = position.y - scaledBounds.height / 2
            if abs(topEdge - guide.position) < snapThreshold {
                snappedPosition.y = guide.position + scaledBounds.height / 2
                break
            }
            
            // Check center
            if abs(position.y - guide.position) < snapThreshold {
                snappedPosition.y = guide.position
                break
            }
            
            // Check bottom edge
            let bottomEdge = position.y + scaledBounds.height / 2
            if abs(bottomEdge - guide.position) < snapThreshold {
                snappedPosition.y = guide.position - scaledBounds.height / 2
                break
            }
        }
        
        return snappedPosition
    }
}

// Guide renderer
class GuideRenderer {
    func renderGuides(_ guides: [AlignmentGuide], in view: UIView) -> CALayer {
        let guideLayer = CALayer()
        guideLayer.frame = view.bounds
        
        for guide in guides {
            let lineLayer = CAShapeLayer()
            let path = UIBezierPath()
            
            if guide.axis == .vertical {
                path.move(to: CGPoint(x: guide.position, y: 0))
                path.addLine(to: CGPoint(x: guide.position, y: view.bounds.height))
            } else {
                path.move(to: CGPoint(x: 0, y: guide.position))
                path.addLine(to: CGPoint(x: view.bounds.width, y: guide.position))
            }
            
            lineLayer.path = path.cgPath
            lineLayer.strokeColor = guide.isCenter ? UIColor.systemBlue.cgColor : UIColor.systemYellow.cgColor
            lineLayer.lineWidth = 1.0
            lineLayer.lineDashPattern = guide.isCenter ? nil : [5, 5]
            
            guideLayer.addSublayer(lineLayer)
        }
        
        return guideLayer
    }
}