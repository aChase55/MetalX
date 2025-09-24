import SwiftUI
import MetalKit

/// A public demo view that mirrors the in-repo MetalX app ContentView.
/// It lives inside the package, so it can use internal types like Canvas and CanvasView.
public struct MetalXEditorDemoView: View {
    @StateObject private var canvas = Canvas()
    @State private var showingImagePicker = false
    @State private var showingTextInput = false
    @State private var newTextContent = ""
    @State private var selectedImage: UIImage?

    public init() {}

    public var body: some View {
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
                        Menu("Shape") {
                            Button("Rectangle") { addShapeLayer(.rectangle) }
                            Button("Circle") { addShapeLayer(.circle) }
                            Button("Triangle") { addShapeLayer(.triangle) }
                            Button("Hexagon") { addShapeLayer(.hexagon) }
                        }
                    } label: {
                        Label("Add Layer", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Clear") { canvas.clear() }
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
                if !newTextContent.isEmpty { addTextLayer(newTextContent) }
                newTextContent = ""
            }
            Button("Cancel", role: .cancel) { newTextContent = "" }
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
        let colors: [UIColor] = [.systemRed, .systemBlue, .systemGreen, .systemOrange, .systemPurple]
        let color = colors[canvas.layers.count % colors.count]

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200))
        let image = renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))

            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 50, y: 50, width: 100, height: 100))

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

        let canvasSize = CGSize(width: 400, height: 400)
        let imageSize = image.size

        if imageSize.width > canvasSize.width || imageSize.height > canvasSize.height {
            let scale = min(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)
            imageLayer.transform.scale = scale
        }

        // Approximate center
        let screenBounds = UIScreen.main.bounds
        imageLayer.transform.position = CGPoint(x: screenBounds.width / 2, y: screenBounds.height / 2)

        canvas.addLayer(imageLayer)
        canvas.selectLayer(imageLayer)
    }

    private func addTextLayer(_ text: String) {
        guard !text.isEmpty else { return }

        let textLayer = TextLayer(text: text)
        textLayer.name = "Text: \(text)"
        textLayer.textColor = .white
        textLayer.font = UIFont.systemFont(ofSize: 72, weight: .bold)
        textLayer.forceUpdateTexture()

        let screenBounds = UIScreen.main.bounds
        textLayer.transform.position = CGPoint(
            x: screenBounds.width / 2,
            y: screenBounds.height / 3
        )

        canvas.addLayer(textLayer)
        canvas.selectLayer(textLayer)
    }

    private enum ShapeType { case rectangle, circle, triangle, hexagon }

    private func addShapeLayer(_ type: ShapeType) {
        let shapeLayer: VectorShapeLayer
        let size: CGFloat = 200

        switch type {
        case .rectangle:
            shapeLayer = VectorShapeLayer.rectangle(size: CGSize(width: size, height: size))
        case .circle:
            shapeLayer = VectorShapeLayer.ellipse(size: CGSize(width: size, height: size))
            shapeLayer.name = "Circle"
        case .triangle:
            shapeLayer = VectorShapeLayer.polygon(sides: 3, radius: size)
            shapeLayer.name = "Triangle"
        case .hexagon:
            shapeLayer = VectorShapeLayer.polygon(sides: 6, radius: size)
            shapeLayer.name = "Hexagon"
        }

        let colors: [UIColor] = [.systemRed, .systemBlue, .systemGreen, .systemOrange, .systemPurple, .systemTeal]
        let color = colors.randomElement() ?? .systemBlue
        shapeLayer.fillType = .solid(color.cgColor)

        let screenBounds = UIScreen.main.bounds
        shapeLayer.transform.position = CGPoint(x: screenBounds.width / 2, y: screenBounds.height / 2)

        canvas.addLayer(shapeLayer)
        canvas.selectLayer(shapeLayer)
    }
}

#Preview {
    MetalXEditorDemoView()
}

