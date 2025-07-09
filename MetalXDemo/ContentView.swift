import SwiftUI
import MetalX
import Metal
import PhotosUI

struct ContentView: View {
    @StateObject private var demoViewModel = DemoViewModel()
    @State private var selectedImage: PhotosPickerItem?
    @State private var showingImagePicker = false
    @State private var isProcessing = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                headerView
                
                if demoViewModel.currentTexture != nil {
                    imageDisplayView
                    controlsView
                } else {
                    placeholderView
                }
                
                statisticsView
                
                Spacer()
            }
            .padding()
            .navigationTitle("MetalX Demo")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Load Image") {
                        showingImagePicker = true
                    }
                }
            }
            .photosPicker(
                isPresented: $showingImagePicker,
                selection: $selectedImage,
                matching: .images
            )
            .onChange(of: selectedImage) { item in
                Task {
                    await loadSelectedImage(item)
                }
            }
            .task {
                await demoViewModel.initializeEngine()
            }
            .alert("Error", isPresented: .constant(demoViewModel.lastError != nil)) {
                Button("OK") {
                    demoViewModel.clearError()
                }
            } message: {
                Text(demoViewModel.lastError?.localizedDescription ?? "Unknown error")
            }
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 8) {
            Text("MetalX Rendering Engine")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Professional GPU-accelerated image processing")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if demoViewModel.isEngineReady {
                Label("Engine Ready", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
            } else {
                Label("Initializing...", systemImage: "clock")
                    .foregroundColor(.orange)
                    .font(.caption)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var placeholderView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text("No Image Loaded")
                .font(.title3)
                .fontWeight(.medium)
            
            Text("Tap 'Load Image' to select a photo from your library")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Load Sample Image") {
                Task {
                    await demoViewModel.loadSampleImage()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!demoViewModel.isEngineReady)
        }
        .frame(maxWidth: .infinity, maxHeight: 200)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var imageDisplayView: some View {
        VStack(spacing: 12) {
            Text("Processed Image")
                .font(.headline)
            
            AsyncImage(url: demoViewModel.currentImageURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(8)
            } placeholder: {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .aspectRatio(1.0, contentMode: .fit)
                    .cornerRadius(8)
                    .overlay {
                        if isProcessing {
                            ProgressView()
                                .scaleEffect(1.5)
                        } else {
                            Image(systemName: "photo")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                        }
                    }
            }
            .frame(maxHeight: 300)
        }
    }
    
    private var controlsView: some View {
        VStack(spacing: 16) {
            Text("Image Adjustments")
                .font(.headline)
            
            VStack(spacing: 12) {
                adjustmentSlider(
                    title: "Brightness",
                    value: $demoViewModel.brightness,
                    range: -1.0...1.0
                )
                
                adjustmentSlider(
                    title: "Contrast",
                    value: $demoViewModel.contrast,
                    range: 0.0...3.0
                )
                
                adjustmentSlider(
                    title: "Saturation",
                    value: $demoViewModel.saturation,
                    range: 0.0...2.0
                )
                
                adjustmentSlider(
                    title: "Exposure",
                    value: $demoViewModel.exposure,
                    range: -2.0...2.0
                )
            }
            
            HStack(spacing: 16) {
                Button("Reset") {
                    demoViewModel.resetAdjustments()
                }
                .buttonStyle(.bordered)
                
                Button("Apply Blur") {
                    Task {
                        isProcessing = true
                        await demoViewModel.applyBlur()
                        isProcessing = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing)
                
                Button("Export") {
                    Task {
                        await demoViewModel.exportImage()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var statisticsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Performance Statistics")
                .font(.headline)
            
            if let stats = demoViewModel.engineStatistics {
                VStack(alignment: .leading, spacing: 4) {
                    statRow("Frame Rate", "\(String(format: "%.1f", stats.currentFrameRate)) FPS")
                    statRow("Memory Usage", "\(stats.memoryUsage / 1024 / 1024) MB")
                    statRow("Frames Rendered", "\(stats.framesRendered)")
                    statRow("Thermal State", thermalStateString(stats.thermalState))
                    statRow("Health Status", stats.isPerformingWell ? "Good" : "Poor")
                }
                .font(.caption)
            } else {
                Text("No statistics available")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func adjustmentSlider(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Slider(value: value, in: range) { _ in
                Task {
                    await demoViewModel.applyAdjustments()
                }
            }
        }
    }
    
    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
    
    private func thermalStateString(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Normal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
    
    private func loadSelectedImage(_ item: PhotosPickerItem?) async {
        guard let item = item else { return }
        
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                await demoViewModel.loadImage(from: data)
            }
        } catch {
            print("Failed to load image: \(error)")
        }
    }
}

#Preview {
    ContentView()
}