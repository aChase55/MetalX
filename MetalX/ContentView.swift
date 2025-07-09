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
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("MetalX Demo")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                if demoViewModel.isEngineReady {
                    Label("Engine Ready", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    
                    // Show the Metal view
                    if let engine = demoViewModel.renderEngine {
                        MetalView(renderEngine: engine)
                            .frame(height: 400)
                            .border(Color.gray, width: 1)
                    }
                } else {
                    Label("Initializing Engine...", systemImage: "clock")
                        .foregroundColor(.orange)
                }
                
                Button("Test Render") {
                    Task {
                        await demoViewModel.performTestRender()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!demoViewModel.isEngineReady)
                
                if let error = demoViewModel.lastError {
                    Text("Error: \(error.localizedDescription)")
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("MetalX")
        }
        .task {
            await demoViewModel.initializeEngine()
        }
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
