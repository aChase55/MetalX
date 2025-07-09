//
//  ContentView.swift
//  MetalX
//
//  Created by Alex Chase on 7/8/25.
//

import SwiftUI
import MetalKit

struct ContentView: View {
    @StateObject private var canvas = Canvas()
    @State private var showingImagePicker = false
    @State private var showingTextInput = false
    @State private var newTextContent = ""
    @State private var selectedImage: UIImage?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Spacer()
                    
                    Text("Layers: \(canvas.layers.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                
                // Canvas
                CanvasView(canvas: canvas)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.05))
                
                // Canvas controls
                HStack(spacing: 16) {
                    Menu {
                        Button("Test Layer") {
                            addTestLayer()
                        }
                        Button("From Photos") {
                            showingImagePicker = true
                        }
                        Button("Text") {
                            showingTextInput = true
                        }
                    } label: {
                        Label("Add Layer", systemImage: "plus")
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
            }
            .padding()
            .navigationTitle("MetalX Canvas")
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(selectedImage: $selectedImage)
        }
        .alert("Add Text", isPresented: $showingTextInput) {
            TextField("Text", text: $newTextContent)
            Button("Add") {
                print("Adding text layer with content: '\(newTextContent)'")
                if !newTextContent.isEmpty {
                    addTextLayer(newTextContent)
                }
                newTextContent = ""
            }
            Button("Cancel", role: .cancel) {
                newTextContent = ""
            }
        } message: {
            Text("Enter text for the new layer")
        }
        .onChange(of: selectedImage) { newImage in
            if let image = newImage {
                addImageLayer(image)
                selectedImage = nil
            }
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
    
    private func addImageLayer(_ image: UIImage) {
        let imageLayer = ImageLayer(image: image)
        imageLayer.name = "Photo Layer"
        
        // Scale image to fit canvas if too large
        let canvasSize = CGSize(width: 400, height: 400) // Target size
        let imageSize = image.size
        
        if imageSize.width > canvasSize.width || imageSize.height > canvasSize.height {
            let scale = min(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)
            imageLayer.transform.scale = scale
        }
        
        // Center in canvas
        imageLayer.transform.position = CGPoint(x: 360, y: 640) // Approximate center
        
        canvas.addLayer(imageLayer)
        canvas.selectLayer(imageLayer)
    }
    
    private func addTextLayer(_ text: String) {
        guard !text.isEmpty else { 
            print("addTextLayer: Empty text, returning")
            return 
        }
        
        print("Creating text layer with text: '\(text)'")
        let textLayer = TextLayer(text: text)
        textLayer.name = "Text: \(text)"
        textLayer.textColor = .white
        textLayer.font = UIFont.systemFont(ofSize: 72, weight: .bold)
        textLayer.forceUpdateTexture() // Update texture after setting properties
        // Center in canvas - use screen center for now
        let screenBounds = UIScreen.main.bounds
        textLayer.transform.position = CGPoint(
            x: screenBounds.width / 2,
            y: screenBounds.height / 3  // Upper third for better visibility
        )
        
        print("Text layer texture: \(textLayer.texture)")
        print("Text layer bounds: \(textLayer.bounds)")
        
        canvas.addLayer(textLayer)
        canvas.selectLayer(textLayer)
    }
}

#Preview {
    ContentView()
}
