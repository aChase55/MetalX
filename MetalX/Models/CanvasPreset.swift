import Foundation
import CoreGraphics

// MARK: - Canvas Presets

struct CanvasPreset: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let aspectRatio: CGFloat
    let description: String
    let category: Category
    
    enum Category: String, CaseIterable {
        case social = "Social Media"
        case print = "Print"
        case screen = "Screen"
        case photo = "Photo"
    }
    
    // Calculate size for a given reference dimension (width or height)
    func size(forWidth width: CGFloat) -> CGSize {
        return CGSize(width: width, height: width / aspectRatio)
    }
    
    func size(forHeight height: CGFloat) -> CGSize {
        return CGSize(width: height * aspectRatio, height: height)
    }
    
    // Get a reasonable default size for editing
    var defaultEditingSize: CGSize {
        // Use 1024 as base dimension for good quality without being too large
        // But ensure we don't exceed Metal texture limits
        let maxDimension: CGFloat = 4096 // Safe limit below Metal's 8192 max
        let baseDimension: CGFloat = 1024
        
        if aspectRatio >= 1 {
            let width = min(baseDimension, maxDimension)
            let height = min(width / aspectRatio, maxDimension)
            return CGSize(width: width, height: height)
        } else {
            let height = min(baseDimension, maxDimension)
            let width = min(height * aspectRatio, maxDimension)
            return CGSize(width: width, height: height)
        }
    }
}

// MARK: - Common Presets

extension CanvasPreset {
    static let presets: [CanvasPreset] = [
        // Social Media
        CanvasPreset(
            name: "Square",
            aspectRatio: 1.0,
            description: "1:1 - Instagram Post, Icon",
            category: .social
        ),
        CanvasPreset(
            name: "Instagram Story",
            aspectRatio: 9.0/16.0,
            description: "9:16 - Stories, Reels, TikTok",
            category: .social
        ),
        CanvasPreset(
            name: "Instagram Landscape",
            aspectRatio: 1.91,
            description: "1.91:1 - Instagram Wide",
            category: .social
        ),
        CanvasPreset(
            name: "Twitter/X Post",
            aspectRatio: 16.0/9.0,
            description: "16:9 - Twitter Image",
            category: .social
        ),
        
        // Print
        CanvasPreset(
            name: "Letter",
            aspectRatio: 8.5/11.0,
            description: "8.5×11 inches",
            category: .print
        ),
        CanvasPreset(
            name: "A4",
            aspectRatio: 210.0/297.0,
            description: "210×297 mm",
            category: .print
        ),
        CanvasPreset(
            name: "US Photo",
            aspectRatio: 4.0/6.0,
            description: "4×6 inches",
            category: .print
        ),
        CanvasPreset(
            name: "Poster",
            aspectRatio: 2.0/3.0,
            description: "2:3 - Standard Poster",
            category: .print
        ),
        
        // Screen
        CanvasPreset(
            name: "HD Video",
            aspectRatio: 16.0/9.0,
            description: "16:9 - 1080p, 4K",
            category: .screen
        ),
        CanvasPreset(
            name: "iPhone Screen",
            aspectRatio: 9.0/19.5,
            description: "9:19.5 - Modern iPhone",
            category: .screen
        ),
        CanvasPreset(
            name: "iPad Screen",
            aspectRatio: 4.0/3.0,
            description: "4:3 - iPad",
            category: .screen
        ),
        CanvasPreset(
            name: "Desktop",
            aspectRatio: 16.0/10.0,
            description: "16:10 - MacBook",
            category: .screen
        ),
        
        // Photo
        CanvasPreset(
            name: "35mm Film",
            aspectRatio: 3.0/2.0,
            description: "3:2 - Classic Photography",
            category: .photo
        ),
        CanvasPreset(
            name: "Medium Format",
            aspectRatio: 4.0/5.0,
            description: "4:5 - Instagram Portrait",
            category: .photo
        ),
        CanvasPreset(
            name: "Panorama",
            aspectRatio: 3.0/1.0,
            description: "3:1 - Wide Panorama",
            category: .photo
        )
    ]
    
    static let defaultPreset = presets.first!
}

// MARK: - Export Resolution

struct ExportResolution: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let scale: CGFloat
    let description: String
    
    func size(for canvasSize: CGSize) -> CGSize {
        return CGSize(
            width: canvasSize.width * scale,
            height: canvasSize.height * scale
        )
    }
}

extension ExportResolution {
    static let resolutions: [ExportResolution] = [
        ExportResolution(name: "Low", scale: 0.5, description: "Half resolution - Fast export"),
        ExportResolution(name: "Standard", scale: 1.0, description: "1x - Web, preview"),
        ExportResolution(name: "High", scale: 2.0, description: "2x - Retina display"),
        ExportResolution(name: "Ultra", scale: 3.0, description: "3x - Print quality"),
        ExportResolution(name: "4K", scale: 4.0, description: "4x - Ultra HD")
    ]
    
    static let standard = resolutions[1]
}