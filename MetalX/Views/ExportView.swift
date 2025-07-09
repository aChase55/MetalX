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
                    
                    GeometryReader { geometry in
                        let scale = min(
                            geometry.size.width / canvas.size.width,
                            geometry.size.height / canvas.size.height
                        ) * 0.9
                        
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(UIColor.systemGray6))
                            .frame(
                                width: canvas.size.width * scale,
                                height: canvas.size.height * scale
                            )
                            .overlay(
                                Text("Canvas Preview")
                                    .foregroundColor(.secondary)
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        
        // Simulate export progress
        // In real implementation, this would render the canvas at high resolution
        for i in 0...10 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            await MainActor.run {
                exportProgress = Double(i) / 10.0
            }
        }
        
        // TODO: Actual canvas rendering at export resolution
        // For now, create a placeholder image
        await MainActor.run {
            let renderer = UIGraphicsImageRenderer(size: exportSize)
            exportedImage = renderer.image { context in
                // Draw placeholder - in real implementation, render all layers
                UIColor.systemGray6.setFill()
                context.fill(CGRect(origin: .zero, size: exportSize))
                
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 48),
                    .foregroundColor: UIColor.systemGray
                ]
                let text = "Exported Canvas\n\(Int(exportSize.width)) × \(Int(exportSize.height))"
                let textSize = text.size(withAttributes: attributes)
                let textRect = CGRect(
                    x: (exportSize.width - textSize.width) / 2,
                    y: (exportSize.height - textSize.height) / 2,
                    width: textSize.width,
                    height: textSize.height
                )
                text.draw(in: textRect, withAttributes: attributes)
            }
            
            isExporting = false
            showingShareSheet = true
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