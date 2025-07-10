import SwiftUI
import Metal

struct ExportView: View {
    let canvas: Canvas
    @Binding var isPresented: Bool
    
    @State private var selectedResolution = ExportResolution.standard
    @State private var isExporting = false
    @State private var exportProgress: Double = 0.0
    @State private var showingShareSheet = false
    @State private var exportedImage: UIImage?
    
    private var exportSize: CGSize {
        selectedResolution.size(for: canvas.size)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Preview
                VStack {
                    Text("Preview")
                        .font(.headline)
                    
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(UIColor.systemGray6))
                        
                        CanvasPreviewView(
                            canvas: canvas,
                            previewSize: CGSize(width: 300, height: 300) // Fixed size for now
                        )
                        .aspectRatio(canvas.size, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .frame(height: 300)
                }
                .padding()
                
                // Resolution options
                VStack(alignment: .leading, spacing: 16) {
                    Text("Export Resolution")
                        .font(.headline)
                    
                    ForEach(ExportResolution.resolutions) { resolution in
                        ResolutionOption(
                            resolution: resolution,
                            canvasSize: canvas.size,
                            isSelected: selectedResolution.id == resolution.id,
                            onTap: { selectedResolution = resolution }
                        )
                    }
                }
                .padding()
                
                Spacer()
                
                // Export info
                VStack(spacing: 8) {
                    Text("Export Size: \(Int(exportSize.width)) × \(Int(exportSize.height)) pixels")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    let megapixels = (exportSize.width * exportSize.height) / 1_000_000
                    Text(String(format: "%.1f megapixels", megapixels))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .disabled(isExporting)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") {
                        Task {
                            await exportCanvas()
                        }
                    }
                    .disabled(isExporting)
                }
            }
            .overlay {
                if isExporting {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .overlay(
                            VStack(spacing: 20) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                    .tint(.white)
                                
                                Text("Exporting...")
                                    .foregroundColor(.white)
                                    .font(.headline)
                                
                                ProgressView(value: exportProgress)
                                    .frame(width: 200)
                                    .tint(.white)
                            }
                            .padding(40)
                            .background(Color.black.opacity(0.8))
                            .cornerRadius(20)
                        )
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let image = exportedImage {
                    ShareSheet(items: [image])
                }
            }
        }
    }
    
    private func exportCanvas() async {
        isExporting = true
        exportProgress = 0.0
        
        // Setup Metal renderer
        guard let device = MTLCreateSystemDefaultDevice() else {
            await MainActor.run {
                isExporting = false
            }
            return
        }
        
        let renderer = MetalXRenderer(device: device)
        renderer.updateDrawableSize(exportSize)
        
        // Export in background
        let image = await Task.detached(priority: .userInitiated) { [exportSize, canvas] in
            // Update progress
            await MainActor.run {
                exportProgress = 0.3
            }
            
            // Render the canvas at export resolution
            let exportedImage = await MainActor.run {
                renderer.renderToUIImage(canvas: canvas, size: exportSize)
            }
            
            // Update progress
            await MainActor.run {
                exportProgress = 0.9
            }
            
            return exportedImage
        }.value
        
        await MainActor.run {
            exportProgress = 1.0
            exportedImage = image
            
            // Small delay to show completion
            Task {
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                isExporting = false
                if exportedImage != nil {
                    showingShareSheet = true
                }
            }
        }
    }
}

struct ResolutionOption: View {
    let resolution: ExportResolution
    let canvasSize: CGSize
    let isSelected: Bool
    let onTap: () -> Void
    
    private var exportSize: CGSize {
        resolution.size(for: canvasSize)
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(resolution.name)
                    .font(.headline)
                    .foregroundColor(isSelected ? .accentColor : .primary)
                
                Text(resolution.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("\(Int(exportSize.width)) × \(Int(exportSize.height))")
                .font(.caption)
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .monospacedDigit()
            
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .accentColor : .secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color(UIColor.secondarySystemBackground))
        )
        .onTapGesture(perform: onTap)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ExportView(canvas: Canvas(), isPresented: .constant(true))
}