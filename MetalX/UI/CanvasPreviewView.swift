import SwiftUI
import Metal

struct CanvasPreviewView: View {
    let canvas: Canvas
    let previewSize: CGSize
    @State private var previewImage: UIImage?
    @State private var renderer: MetalXRenderer?
    
    var validPreviewSize: CGSize {
        CGSize(
            width: max(previewSize.width, 100),
            height: max(previewSize.height, 100)
        )
    }
    
    var body: some View {
        Group {
            if let image = previewImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(UIColor.systemGray6))
                    .overlay(
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    )
            }
        }
        .onAppear {
            setupRenderer()
            renderPreview()
        }
        .onChange(of: canvas.needsDisplay) { _ in
            renderPreview()
        }
        .onChange(of: canvas.layers.count) { _ in
            renderPreview()
        }
        .onChange(of: previewSize) { _ in
            renderPreview()
        }
    }
    
    private func setupRenderer() {
        if renderer == nil, let device = MTLCreateSystemDefaultDevice() {
            renderer = MetalXRenderer(device: device)
            // Update renderer size for preview
            renderer?.updateDrawableSize(validPreviewSize)
        }
    }
    
    private func renderPreview() {
        guard let renderer = renderer else { 
            print("CanvasPreviewView: No renderer available")
            return 
        }
        
        let renderSize = validPreviewSize
        print("CanvasPreviewView: Rendering preview with size: \(renderSize), canvas size: \(canvas.size)")
        
        // Don't render if size is too small
        guard renderSize.width > 0 && renderSize.height > 0 else {
            print("CanvasPreviewView: Invalid render size")
            return
        }
        
        Task {
            let image = await Task.detached { [canvas, renderSize] in
                await MainActor.run {
                    // Render at the canvas's actual size to capture all content
                    renderer.renderToUIImage(canvas: canvas, size: canvas.size)
                }
            }.value
            
            await MainActor.run {
                previewImage = image
                if image == nil {
                    print("CanvasPreviewView: Failed to render preview image")
                } else {
                    print("CanvasPreviewView: Successfully rendered preview image")
                }
            }
        }
    }
}