import SwiftUI
import MetalKit
import PhotosUI

struct ShapePropertiesView: View {
    @ObservedObject var canvas: Canvas
    @State private var selectedFillType: FillTypeOption = .solid
    @State private var solidColor: Color = .blue
    @State private var showingGradientEditor = false
    @State private var currentGradient = GradientData()
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedFillImage: UIImage?
    
    enum FillTypeOption: String, CaseIterable {
        case solid = "Solid"
        case gradient = "Gradient"
        case image = "Image"
        case none = "None"
        
        var systemImage: String {
            switch self {
            case .solid: return "square.fill"
            case .gradient: return "rectangle.fill.badge.plus"
            case .image: return "photo.fill"
            case .none: return "square"
            }
        }
    }
    
    var shapeLayer: VectorShapeLayer? {
        canvas.selectedLayer as? VectorShapeLayer
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let shape = shapeLayer {
                Text("Shape Properties")
                    .font(.headline)
                    .padding(.bottom, 8)
                
                // Fill Type Selector
                VStack(alignment: .leading, spacing: 8) {
                    Text("Fill Type")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Picker("Fill Type", selection: $selectedFillType) {
                        ForEach(FillTypeOption.allCases, id: \.self) { option in
                            Label(option.rawValue, systemImage: option.systemImage)
                                .tag(option)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .onChange(of: selectedFillType) { _, newValue in
                        updateFillType(newValue)
                    }
                }
                
                // Fill Options
                switch selectedFillType {
                case .solid:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Fill Color")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        ColorPicker("Color", selection: $solidColor)
                            .labelsHidden()
                            .onChange(of: solidColor) { _, newColor in
                                updateSolidColor(newColor)
                            }
                    }
                    
                case .gradient:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Gradient Fill")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        // Gradient preview - show correct type
                        Group {
                            switch currentGradient.type {
                            case .linear:
                                LinearGradient(
                                    colors: currentGradient.colors,
                                    startPoint: currentGradient.linearStartPoint,
                                    endPoint: currentGradient.linearEndPoint
                                )
                            case .radial:
                                RadialGradient(
                                    colors: currentGradient.colors,
                                    center: currentGradient.radialCenter,
                                    startRadius: 0,
                                    endRadius: CGFloat(currentGradient.radialRadius * 60)
                                )
                            case .angular:
                                AngularGradient(
                                    colors: currentGradient.colors,
                                    center: .center
                                )
                            }
                        }
                        .frame(height: 60)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        
                        Button(action: { showingGradientEditor = true }) {
                            Label("Edit Gradient", systemImage: "slider.horizontal.3")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    
                case .image:
                    VStack(alignment: .leading, spacing: 12) {
                        // Image preview
                        if let fillImage = selectedFillImage {
                            Image(uiImage: fillImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 60)
                                .clipped()
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 60)
                                .overlay(
                                    VStack {
                                        Image(systemName: "photo")
                                            .font(.title2)
                                            .foregroundColor(.gray)
                                        Text("No Image")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                )
                        }
                        
                        PhotosPicker(
                            selection: $selectedPhotoItem,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            Label(selectedFillImage == nil ? "Select Image" : "Change Image", 
                                  systemImage: "photo.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .onChange(of: selectedPhotoItem) { _, newItem in
                            Task {
                                if let newItem = newItem,
                                   let data = try? await newItem.loadTransferable(type: Data.self),
                                   let image = UIImage(data: data) {
                                    selectedFillImage = image
                                    applyImageFill(image)
                                }
                            }
                        }
                    }
                    
                case .none:
                    EmptyView()
                }
                
                Divider()
                
                // Stroke properties
                VStack(alignment: .leading, spacing: 8) {
                    Text("Stroke")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Text("Width")
                        Slider(value: .init(
                            get: { CGFloat(shape.strokeWidth) },
                            set: { 
                                shape.strokeWidth = Float($0)
                                updateStroke()
                            }
                        ), in: 0...20)
                        Text("\(Int(shape.strokeWidth))pt")
                            .font(.caption)
                            .monospacedDigit()
                            .frame(width: 40)
                    }
                    
                    if shape.strokeWidth > 0 {
                        HStack {
                            Text("Color")
                            Spacer()
                            ColorPicker("", selection: Binding(
                                get: { 
                                    if let strokeColor = shape.strokeColor {
                                        return Color(UIColor(cgColor: strokeColor))
                                    }
                                    return .black
                                },
                                set: { newColor in
                                    shape.strokeColor = UIColor(newColor).cgColor
                                    updateStroke()
                                }
                            ))
                            .labelsHidden()
                        }
                    }
                }
            } else {
                Text("Select a shape layer to edit properties")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .padding(.vertical)
        .sheet(isPresented: $showingGradientEditor) {
            GradientEditorView(gradientData: $currentGradient) {
                applyGradient()
            }
            .onDisappear {
                // Reload gradient data when editor closes
                loadCurrentFillType()
            }
        }
        .onAppear {
            loadCurrentFillType()
        }
        .onReceive(canvas.$selectedLayer) { _ in
            loadCurrentFillType()
        }
    }
    
    private func loadCurrentFillType() {
        guard let shape = shapeLayer else { return }
        
        if let fillType = shape.fillType {
            switch fillType {
            case .solid(let color):
                selectedFillType = .solid
                solidColor = Color(UIColor(cgColor: color))
            case .gradient(let gradient):
                selectedFillType = .gradient
                currentGradient = GradientData(from: gradient)
            case .pattern(_):
                selectedFillType = .image
                // Note: We can't extract the original UIImage from MTLTexture,
                // so selectedFillImage will remain nil but the UI will show image mode
            }
        } else {
            selectedFillType = .none
        }
    }
    
    private func updateFillType(_ type: FillTypeOption) {
        guard let shape = shapeLayer else { return }
        
        switch type {
        case .solid:
            shape.fillType = .solid(UIColor(solidColor).cgColor)
        case .gradient:
            applyGradient()
        case .image:
            if let image = selectedFillImage {
                applyImageFill(image)
            }
            // Note: PhotosPicker will handle image selection automatically
        case .none:
            shape.fillType = nil
        }
        
        // Force texture recreation
        shape.clearTexture()
        canvas.setNeedsDisplay()
        // Force immediate redraw
        NotificationCenter.default.post(name: NSNotification.Name("CanvasNeedsDisplay"), object: nil)
    }
    
    private func updateSolidColor(_ color: Color) {
        guard let shape = shapeLayer else { return }
        shape.fillType = .solid(UIColor(color).cgColor)
        // Force texture recreation
        shape.clearTexture()
        canvas.setNeedsDisplay()
        // Force immediate redraw
        NotificationCenter.default.post(name: NSNotification.Name("CanvasNeedsDisplay"), object: nil)
    }
    
    private func applyGradient() {
        guard let shape = shapeLayer else { return }
        
        let gradient = currentGradient.toGradient()
        shape.fillType = .gradient(gradient)
        // Force texture recreation
        shape.clearTexture()
        canvas.setNeedsDisplay()
        // Force immediate redraw
        NotificationCenter.default.post(name: NSNotification.Name("CanvasNeedsDisplay"), object: nil)
    }
    
    private func applyImageFill(_ image: UIImage) {
        guard let shape = shapeLayer else { return }
        
        // Convert UIImage to MTLTexture
        if let texture = createTexture(from: image) {
            shape.fillType = .pattern(texture)
            // Force texture recreation
            shape.clearTexture()
            canvas.setNeedsDisplay()
            // Force immediate redraw
            NotificationCenter.default.post(name: NSNotification.Name("CanvasNeedsDisplay"), object: nil)
        }
    }
    
    private func createTexture(from image: UIImage) -> MTLTexture? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        
        let loader = MTKTextureLoader(device: device)
        do {
            let texture = try loader.newTexture(cgImage: image.cgImage!, options: [
                .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
                .SRGB: false
            ])
            return texture
        } catch {
            print("Failed to create texture from image: \(error)")
            return nil
        }
    }
    
    private func updateStroke() {
        guard let shape = shapeLayer else { return }
        
        // Ensure we have a stroke color if width > 0
        if shape.strokeWidth > 0 && shape.strokeColor == nil {
            shape.strokeColor = UIColor.black.cgColor
        }
        
        // Force texture recreation
        shape.clearTexture()
        canvas.setNeedsDisplay()
        // Force immediate redraw
        NotificationCenter.default.post(name: NSNotification.Name("CanvasNeedsDisplay"), object: nil)
    }
}

// Helper struct for gradient editing
struct GradientData {
    var colors: [Color] = [.blue, .purple]
    var locations: [Float] = [0.0, 1.0]
    var type: Gradient.GradientType = .linear
    var linearStartPoint: UnitPoint = .topLeading
    var linearEndPoint: UnitPoint = .bottomTrailing
    var radialCenter: UnitPoint = .center
    var radialRadius: Float = 0.5
    
    init() {}
    
    init(from gradient: Gradient) {
        self.type = gradient.type
        self.colors = gradient.colorStops.map { Color(UIColor(cgColor: $0.color)) }
        self.locations = gradient.colorStops.map { $0.location }
        
        // Convert CGPoint to UnitPoint
        self.linearStartPoint = UnitPoint(
            x: gradient.startPoint.x,
            y: gradient.startPoint.y
        )
        self.linearEndPoint = UnitPoint(
            x: gradient.endPoint.x,
            y: gradient.endPoint.y
        )
        
        // For radial gradients, extract center and radius
        if gradient.type == .radial {
            self.radialCenter = UnitPoint(
                x: gradient.startPoint.x,
                y: gradient.startPoint.y
            )
            // Calculate radius from start and end points
            let dx = gradient.endPoint.x - gradient.startPoint.x
            let dy = gradient.endPoint.y - gradient.startPoint.y
            self.radialRadius = Float(sqrt(dx * dx + dy * dy))
        }
    }
    
    func toGradient() -> Gradient {
        let colorStops = zip(colors, locations).map { color, location in
            Gradient.ColorStop(
                color: UIColor(color).cgColor,
                location: location
            )
        }
        
        let startPoint: CGPoint
        let endPoint: CGPoint
        
        switch type {
        case .linear:
            startPoint = CGPoint(x: linearStartPoint.x, y: linearStartPoint.y)
            endPoint = CGPoint(x: linearEndPoint.x, y: linearEndPoint.y)
        case .angular:
            // For angular gradients, use center point for both start and end
            startPoint = CGPoint(x: 0.5, y: 0.5) // Center of the shape
            endPoint = CGPoint(x: 0.5, y: 0.5)   // Same as start for angular
        case .radial:
            // For radial gradients, startPoint is center, endPoint defines radius
            startPoint = CGPoint(x: radialCenter.x, y: radialCenter.y)
            endPoint = CGPoint(x: radialCenter.x + CGFloat(radialRadius), y: radialCenter.y)
        }
        
        return Gradient(
            type: type,
            colorStops: colorStops,
            startPoint: startPoint,
            endPoint: endPoint
        )
    }
}