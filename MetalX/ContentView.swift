//
//  ContentView.swift
//  MetalX
//
//  Created by Alex Chase on 7/8/25.
//

import SwiftUI
import MetalKit

struct ContentView: View {
    @StateObject private var demoViewModel = DemoViewModel()
    @StateObject private var canvas = Canvas()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    Text("MetalX Canvas")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    HStack {
                        if demoViewModel.isEngineReady {
                            Label("Engine Ready", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        }
                        
                        Spacer()
                        
                        Text("Layers: \(canvas.layers.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)
                
                // Canvas
                if demoViewModel.isEngineReady {
                    CanvasView(canvas: canvas)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.05))
                } else {
                    Label("Initializing Engine...", systemImage: "clock")
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                // Canvas controls
                HStack(spacing: 16) {
                    Button("Add Layer") {
                        addTestLayer()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Clear") {
                        canvas.clear()
                    }
                    .buttonStyle(.bordered)
                    .disabled(canvas.layers.isEmpty)
                    
                    Spacer()
                    
                    if canvas.selectedLayer != nil {
                        Text("Selected: \(canvas.selectedLayer?.name ?? "")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                
                if let error = demoViewModel.lastError {
                    Text("Error: \(error.localizedDescription)")
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
            }
            .padding()
            .navigationTitle("MetalX Canvas")
        }
        .task {
            await demoViewModel.initializeEngine()
        }
    }
    
    private func addTestLayer() {
        // Create a simple test image with different colors
        let colors: [UIColor] = [.systemRed, .systemBlue, .systemGreen, .systemOrange, .systemPurple]
        let color = colors[canvas.layers.count % colors.count]
        
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200))
        let image = renderer.image { context in
            // Fill with color
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
            
            // Add white circle
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 50, y: 50, width: 100, height: 100))
            
            // Add layer number
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 48, weight: .bold),
                .foregroundColor: UIColor.black
            ]
            let text = "\(canvas.layers.count + 1)"
            let textSize = text.size(withAttributes: attributes)
            let textRect = CGRect(
                x: 100 - textSize.width/2,
                y: 100 - textSize.height/2,
                width: textSize.width,
                height: textSize.height
            )
            text.draw(in: textRect, withAttributes: attributes)
        }
        
        let imageLayer = ImageLayer(image: image)
        imageLayer.name = "Layer \(canvas.layers.count + 1)"
        imageLayer.transform.position = CGPoint(
            x: 200 + CGFloat(canvas.layers.count * 30),
            y: 200 + CGFloat(canvas.layers.count * 30)
        )
        
        canvas.addLayer(imageLayer)
        canvas.selectLayer(imageLayer)
    }
}

@MainActor
class DemoViewModel: ObservableObject {
    @Published var isEngineReady = false
    @Published var lastError: Error?
    
    var renderEngine: RenderEngine?
    
    func initializeEngine() async {
        // First test if Metal is available
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            lastError = MetalDeviceError.noMetalSupport
            isEngineReady = false
            return
        }
        
        print("Metal device found: \(device.name)")
        
        do {
            let config = EngineConfiguration()
            renderEngine = try RenderEngine(configuration: config)
            isEngineReady = true
        } catch {
            print("Engine initialization failed: \(error)")
            lastError = error
            isEngineReady = false
        }
    }
    
    func performTestRender() async {
        guard let engine = renderEngine else { return }
        
        do {
            // Create a simple test texture
            let testTexture = try engine.createRenderTexture(width: 512, height: 512)
            let outputTexture = try engine.createRenderTexture(width: 512, height: 512)
            
            // Perform a simple copy operation
            try await engine.render(texture: testTexture, to: outputTexture)
            
            print("Test render completed successfully!")
            
        } catch {
            lastError = error
            print("Test render failed: \(error)")
        }
    }
}

#Preview {
    ContentView()
}
