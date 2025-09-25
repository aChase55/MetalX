import SwiftUI
import PhotosUI

struct BackgroundSettingsView: View {
    @ObservedObject var canvas: Canvas
    @Binding var isPresented: Bool
    
    @State private var selectedFillType: FillType = .solid
    @State private var selectedColor = Color.white
    @State private var selectedImage: PhotosPickerItem?
    @State private var gradientType: Gradient.GradientType = .linear
    @State private var gradientStops: [GradientStop] = [
        GradientStop(color: .blue, location: 0.0),
        GradientStop(color: .purple, location: 1.0)
    ]
    
    enum FillType: String, CaseIterable {
        case solid = "Solid Color"
        case gradient = "Gradient"
        case image = "Image"
        
        var icon: String {
            switch self {
            case .solid: return "paintpalette"
            case .gradient: return "rectangle.righthalf.inset.filled"
            case .image: return "photo"
            }
        }
    }
    
    struct GradientStop: Identifiable {
        let id = UUID()
        var color: Color
        var location: CGFloat
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Fill Type") {
                    Picker("Type", selection: $selectedFillType) {
                        ForEach(FillType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                switch selectedFillType {
                case .solid:
                    Section("Color") {
                        ColorPicker("Background Color", selection: $selectedColor)
                            .onChange(of: selectedColor) { _ in
                                updateBackground()
                            }
                    }
                    
                case .gradient:
                    Section("Gradient") {
                        Picker("Type", selection: $gradientType) {
                            Text("Linear").tag(Gradient.GradientType.linear)
                            Text("Radial").tag(Gradient.GradientType.radial)
                            Text("Angular").tag(Gradient.GradientType.angular)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: gradientType) { _ in
                            updateBackground()
                        }
                        
                        ForEach(gradientStops.indices, id: \.self) { index in
                            HStack {
                                ColorPicker("", selection: $gradientStops[index].color)
                                    .labelsHidden()
                                    .onChange(of: gradientStops[index].color) { _ in
                                        updateBackground()
                                    }
                                
                                Slider(value: $gradientStops[index].location)
                                    .onChange(of: gradientStops[index].location) { _ in
                                        updateBackground()
                                    }
                                
                                if gradientStops.count > 2 {
                                    Button(action: {
                                        gradientStops.remove(at: index)
                                        updateBackground()
                                    }) {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundColor(.red)
                                    }
                                }
                            }
                        }
                        
                        Button(action: {
                            gradientStops.append(GradientStop(color: .gray, location: 0.5))
                            updateBackground()
                        }) {
                            Label("Add Stop", systemImage: "plus.circle.fill")
                        }
                    }
                    
                case .image:
                    Section("Image") {
                        PhotosPicker(selection: $selectedImage,
                                   matching: .images,
                                   photoLibrary: .shared()) {
                            Label("Choose Image", systemImage: "photo")
                        }
                        .onChange(of: selectedImage) { _ in
                            loadSelectedImage()
                        }
                    }
                }
                
                Section {
                    Toggle("Visible", isOn: Binding(
                        get: { canvas.backgroundLayer?.isVisible ?? true },
                        set: { newValue in
                            canvas.backgroundLayer?.isVisible = newValue
                            canvas.setNeedsDisplay()
                        }
                    ))
                }
            }
            .navigationTitle("Background")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
        .onAppear {
            setupInitialState()
        }
    }
    
    private func setupInitialState() {
        guard let backgroundLayer = canvas.backgroundLayer else {
            canvas.initializeBackgroundLayer()
            return
        }
        
        switch backgroundLayer.fillType {
        case .solid(let color):
            selectedFillType = .solid
            selectedColor = Color(cgColor: color)
            
        case .gradient(let gradient):
            selectedFillType = .gradient
            gradientType = gradient.type
            gradientStops = gradient.colorStops.map { stop in
                GradientStop(color: Color(cgColor: stop.color), location: CGFloat(stop.location))
            }
            
        case .image:
            selectedFillType = .image
        }
    }
    
    private func updateBackground() {
        switch selectedFillType {
        case .solid:
            canvas.setBackgroundFill(.solid(UIColor(selectedColor).cgColor))
            
        case .gradient:
            let colorStops = gradientStops.sorted(by: { $0.location < $1.location }).map { stop in
                Gradient.ColorStop(color: UIColor(stop.color).cgColor, location: Float(stop.location))
            }
            
            let gradient = Gradient(
                type: gradientType,
                colorStops: colorStops,
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 1, y: 1)
            )
            
            canvas.setBackgroundFill(.gradient(gradient))
            
        case .image:
            break // Handled in loadSelectedImage
        }
    }
    
    private func loadSelectedImage() {
        guard let selectedImage = selectedImage else { return }
        
        Task {
            if let data = try? await selectedImage.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run {
                    canvas.setBackgroundFill(.image(image))
                }
            }
        }
    }
}

#Preview {
    BackgroundSettingsView(canvas: Canvas(), isPresented: .constant(true))
}
