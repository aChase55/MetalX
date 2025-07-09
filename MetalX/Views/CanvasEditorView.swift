import SwiftUI
import PhotosUI

struct CanvasEditorView: View {
    let project: MetalXProject
    let projectList: ProjectListModel
    
    @StateObject private var canvas = Canvas()
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var showingTextInput = false
    @State private var newTextContent = ""
    @State private var hasUnsavedChanges = false
    @State private var lastSaveDate = Date()
    @State private var showingSidebar = false
    @State private var showingAddMenu = false
    @State private var showingExportView = false
    
    // Auto-save timer
    let saveTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            // Bounded canvas with pan/zoom support
            BoundedCanvasView(canvas: canvas)
                .ignoresSafeArea()
                .onChange(of: canvas.layers.count) {
                    hasUnsavedChanges = true
                }
            
            // Floating controls overlay
            VStack {
                // Top toolbar
                HStack {
                    // Toggle sidebar button
                    Button(action: { 
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showingSidebar.toggle()
                        }
                    }) {
                        Image(systemName: "sidebar.left")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.7))
                            .clipShape(Circle())
                    }
                    .padding()
                    
                    Spacer()
                    
                    // Add content button
                    Button(action: { showingAddMenu.toggle() }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.7))
                            .clipShape(Circle())
                    }
                    .padding()
                }
                
                Spacer()
                
                // Bottom area - Selected layer pill
                VStack {
                    // Save status
                    HStack {
                        VStack {
                            if hasUnsavedChanges {
                                Label("Unsaved changes", systemImage: "exclamationmark.circle.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                    .padding(8)
                                    .background(Color.black.opacity(0.7))
                                    .cornerRadius(8)
                            } else {
                                Label("All changes saved", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                    .padding(8)
                                    .background(Color.black.opacity(0.7))
                                    .cornerRadius(8)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                    
                    // Selected layer pill
                    SelectedLayerPill(canvas: canvas)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            
            // Sidebar overlay (slides in from left)
            if showingSidebar {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header
                        HStack {
                            Text("Layers")
                                .font(.title2.bold())
                            
                            Spacer()
                            
                            Button(action: {
                                withAnimation {
                                    showingSidebar = false
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.bottom)
                        
                        // Layer list
                        ScrollView {
                            VStack(spacing: 4) {
                                ForEach(Array(canvas.layers.reversed().enumerated()), id: \.element.id) { index, layer in
                                    LayerRow(layer: layer, isSelected: layer === canvas.selectedLayer)
                                        .onTapGesture {
                                            canvas.selectLayer(layer)
                                        }
                                }
                            }
                        }
                        
                        
                        Spacer()
                    }
                    .frame(width: 280)
                    .padding()
                    .background(Color(UIColor.systemBackground))
                    .background(.ultraThinMaterial)
                    
                    Spacer()
                }
                .transition(.move(edge: .leading))
                .zIndex(1)
            }
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: saveProject) {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    .disabled(!hasUnsavedChanges)
                    
                    Button(action: { showingExportView = true }) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(canvas.layers.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingAddMenu) {
            AddContentMenu(
                selectedItem: $selectedItem,
                onDismiss: { showingAddMenu = false },
                onAddText: { 
                    showingAddMenu = false
                    showingTextInput = true 
                },
                onAddShape: { shape in 
                    showingAddMenu = false
                    addShapeLayer(shape)
                },
                onAddTestLayer: {
                    showingAddMenu = false
                    addTestLayer()
                }
            )
            .presentationDetents([.medium])
        }
        .alert("Add Text", isPresented: $showingTextInput) {
            TextField("Text", text: $newTextContent)
            Button("Add") {
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
        .sheet(isPresented: $showingExportView) {
            ExportView(canvas: canvas, isPresented: $showingExportView)
        }
        .onChange(of: selectedItem) { _, newImage in
            Task {
                if let data = try? await newImage?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        addImageLayer(image)
                        selectedItem = nil
                    }
                }
            }
        }
        .onAppear {
            loadProject()
        }
        .onReceive(saveTimer) { _ in
            if hasUnsavedChanges {
                autoSave()
            }
        }
        .onDisappear {
            if hasUnsavedChanges {
                saveProject()
            }
        }
    }
    
    // MARK: - Project Management
    
    private func loadProject() {
        canvas.loadFromProject(project)
        
        // Check if any layers are outside the canvas bounds
        var needsRepositioning = false
        let canvasBounds = CGRect(origin: .zero, size: canvas.size)
        let padding: CGFloat = 50
        
        for layer in canvas.layers {
            let position = layer.transform.position
            // Check if layer is significantly outside canvas bounds
            if !canvasBounds.insetBy(dx: -padding, dy: -padding).contains(position) {
                // Move to canvas center if way outside
                layer.transform.position = CGPoint(
                    x: canvas.size.width / 2,
                    y: canvas.size.height / 2
                )
                needsRepositioning = true
            }
        }
        
        hasUnsavedChanges = needsRepositioning
        lastSaveDate = Date()
    }
    
    private func saveProject() {
        var updatedProject = canvas.toProject(name: project.name)
        updatedProject.id = project.id  // Preserve original ID
        updatedProject.createdDate = project.createdDate  // Preserve creation date
        
        projectList.saveProject(updatedProject)
        hasUnsavedChanges = false
        lastSaveDate = Date()
    }
    
    private func autoSave() {
        // Only auto-save if enough time has passed
        if Date().timeIntervalSince(lastSaveDate) > 5 {
            saveProject()
        }
    }
    
    // MARK: - Layer Management
    
    private var visibleCenter: CGPoint {
        // Center relative to canvas size
        return CGPoint(x: canvas.size.width / 2, y: canvas.size.height / 2)
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
        imageLayer.transform.position = visibleCenter
        
        canvas.addLayer(imageLayer)
        canvas.selectLayer(imageLayer)
        hasUnsavedChanges = true
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
        
        imageLayer.transform.position = visibleCenter
        
        canvas.addLayer(imageLayer)
        canvas.selectLayer(imageLayer)
        hasUnsavedChanges = true
    }
    
    private func addTextLayer(_ text: String) {
        guard !text.isEmpty else { return }
        
        let textLayer = TextLayer(text: text)
        textLayer.name = "Text: \(text)"
        textLayer.textColor = .white
        textLayer.font = UIFont.systemFont(ofSize: 72, weight: .bold)
        textLayer.forceUpdateTexture()
        
        textLayer.transform.position = CGPoint(
            x: visibleCenter.x,
            y: visibleCenter.y - 100  // Slightly above center for better visibility
        )
        
        canvas.addLayer(textLayer)
        canvas.selectLayer(textLayer)
        hasUnsavedChanges = true
    }
    
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
        
        shapeLayer.transform.position = visibleCenter
        
        canvas.addLayer(shapeLayer)
        canvas.selectLayer(shapeLayer)
        hasUnsavedChanges = true
    }
}

// MARK: - Supporting Views

enum ShapeType {
    case rectangle
    case circle
    case triangle
    case hexagon
}

struct AddContentMenu: View {
    @Binding var selectedItem: PhotosPickerItem?
    let onDismiss: () -> Void
    let onAddText: () -> Void
    let onAddShape: (ShapeType) -> Void
    let onAddTestLayer: () -> Void
    
    var body: some View {
        NavigationStack {
            List {
                Section("Basic") {
                    Button(action: onAddTestLayer) {
                        Label("Test Layer", systemImage: "square.fill")
                    }
                    
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Label("Image", systemImage: "photo")
                    }
                    .onChange(of: selectedItem) { _, _ in
                        if selectedItem != nil {
                            onDismiss()
                        }
                    }
                    
                    Button(action: onAddText) {
                        Label("Text", systemImage: "textformat")
                    }
                }
                
                Section("Shapes") {
                    Button(action: { onAddShape(.rectangle) }) {
                        Label("Rectangle", systemImage: "rectangle")
                    }
                    
                    Button(action: { onAddShape(.circle) }) {
                        Label("Circle", systemImage: "circle")
                    }
                    
                    Button(action: { onAddShape(.triangle) }) {
                        Label("Triangle", systemImage: "triangle")
                    }
                    
                    Button(action: { onAddShape(.hexagon) }) {
                        Label("Hexagon", systemImage: "hexagon")
                    }
                }
            }
            .navigationTitle("Add Content")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct LayerRow: View {
    let layer: any Layer
    let isSelected: Bool
    
    var body: some View {
        HStack {
            Image(systemName: layerIcon)
                .foregroundColor(.secondary)
                .frame(width: 20)
            
            Text(layer.name)
                .lineLimit(1)
            
            Spacer()
            
            if !layer.isVisible {
                Image(systemName: "eye.slash")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(6)
    }
    
    private var layerIcon: String {
        switch layer {
        case is ImageLayer: return "photo"
        case is TextLayer: return "textformat"
        case is VectorShapeLayer: return "square.on.circle"
        default: return "square.stack"
        }
    }
}