import SwiftUI
import PhotosUI
import UIKit
import Metal

public struct CanvasEditorView: View {
    let project: MetalXProject
    let projectList: ProjectListModel
    @Binding var exportTrigger: Bool
    let onExportImage: ((UIImage) -> Void)?
    let assetURLs: [URL]?
    
    public init(
        project: MetalXProject,
        projectList: ProjectListModel,
        exportTrigger: Binding<Bool> = .constant(false),
        onExportImage: ((UIImage) -> Void)? = nil,
        assetURLs: [URL]? = nil
    ) {
        self.project = project
        self.projectList = projectList
        self._exportTrigger = exportTrigger
        self.onExportImage = onExportImage
        self.assetURLs = assetURLs
    }
    
    @StateObject private var canvas = Canvas()
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var showingTextInput = false
    @State private var newTextContent = ""
    @State private var hasUnsavedChanges = false
    @State private var lastSaveDate = Date()
    @State private var showingSidebar = false
    @State private var showingAddMenu = false
    @State private var showingExportView = false
    @State private var showingCanvasEffects = false
    @State private var showingAssetPicker = false
    @State private var showingBackgroundSettings = false
    @State private var aiPrompt: String = ""
    @State private var aiError: String?
    @State private var showingAIGenerateAlert = false
    @State private var isGenerating = false
    
    // Auto-save timer
    let saveTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    
    public var body: some View {
        ZStack {
            // Bounded canvas with pan/zoom support
            BoundedCanvasView(canvas: canvas)
                .ignoresSafeArea()
                .onChange(of: canvas.layers.count) { _ in
                    hasUnsavedChanges = true
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CanvasNeedsDisplay"))) { _ in
                    hasUnsavedChanges = true
                }
            
            // Floating controls overlay (left sidebar and bottom selected pill)
            VStack {
                Spacer()
                
                // Bottom area - Selected layer pill
                VStack {
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
                                ForEach(Array(canvas.layers.filter { !$0.isInternal }.reversed().enumerated()), id: \.element.id) { index, layer in
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
            
            // Lightweight generating overlay
            if isGenerating {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.circular)
                    Text("Generating…")
                        .font(.callout)
                        .foregroundColor(.primary)
                }
                .padding(20)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Undo button
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    canvas.undoManager.undo()
                }) {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!canvas.undoManager.canUndo)
            }
            
            // Redo button
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    canvas.undoManager.redo()
                }) {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(!canvas.undoManager.canRedo)
            }
            
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
        // Bottom Tab Bar for primary actions when no layer is selected
        .safeAreaInset(edge: .bottom) {
            if canvas.selectedLayer == nil {
                HStack {
                    // Sidebar
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showingSidebar.toggle()
                        }
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: "sidebar.left")
                            Text("Layers")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    // Background
                    Button(action: { showingBackgroundSettings = true }) {
                        VStack(spacing: 4) {
                            Image(systemName: "rectangle.fill")
                            Text("Background")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    // Effects
                    Button(action: { showingCanvasEffects = true }) {
                        VStack(spacing: 4) {
                            Image(systemName: "wand.and.stars")
                            Text("Effects")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    // Add
                    Button(action: { showingAddMenu = true }) {
                        VStack(spacing: 4) {
                            Image(systemName: "plus.circle")
                            Text("Add")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background(.ultraThinMaterial)
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
                onAddAsset: {
                    showingAddMenu = false
                    showingAssetPicker = true
                },
                onGenerate: {
                    showingAddMenu = false
                    showingAIGenerateAlert = true
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
        // Sticker picker removed
        .sheet(isPresented: $showingCanvasEffects) {
            CanvasEffectsView(canvas: canvas, isPresented: $showingCanvasEffects)
                .asSelfSizingSheet()
        }
        .sheet(isPresented: $showingAssetPicker) {
            AssetPickerView(canvas: canvas, isPresented: $showingAssetPicker, providedAssetURLs: assetURLs)
        }
        .sheet(isPresented: $showingBackgroundSettings) {
            BackgroundSettingsView(canvas: canvas, isPresented: $showingBackgroundSettings)
                .asSelfSizingSheet()
        }
        .alert("Error", isPresented: Binding(get: { aiError != nil }, set: { _ in aiError = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(aiError ?? "Unknown error")
        }
        .alert("Generate Image", isPresented: $showingAIGenerateAlert) {
            TextField("Prompt", text: $aiPrompt)
            Button("Generate") {
                Task {
                    do {
                        guard !FreepikAIService.apiKey.isEmpty else {
                            aiError = "Set API key before generating."
                            return
                        }
                        showingAIGenerateAlert = false
                        isGenerating = true
                        let sizeHint = freepikSize(for: canvas.size)
                        print("[AI] Generating image with prompt: \(aiPrompt) [size=\(sizeHint)]")
                        let images = try await FreepikAIService.generate(prompt: aiPrompt, size: sizeHint)
                        if let img = images.first {
                            await MainActor.run { addImageLayer(img) }
                        } else {
                            aiError = "No images returned"
                        }
                    } catch {
                        aiError = error.localizedDescription
                    }
                    isGenerating = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a prompt to generate an image")
        }
        .onChange(of: selectedItem) { newImage in
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("HideSidebar"))) { _ in
            withAnimation { showingSidebar = false }
        }
        .onChange(of: exportTrigger) { _ in
            // Perform export when trigger flips
            if let image = exportCanvasImage(size: canvas.size) {
                onExportImage?(image)
            }
        }
    }

    // Map canvas aspect ratio to Freepik size presets.
    // Falls back to square for near-1:1 ratios.
    private func freepikSize(for canvasSize: CGSize) -> String {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return "square" }
        let ratio = canvasSize.width / canvasSize.height
        if ratio > 1.1 { return "landscape" }
        if ratio < 0.9 { return "portrait" }
        return "square"
    }

    // MARK: - Export
    /// Exports the current canvas to a UIImage.
    /// - Parameter size: Optional export size. Defaults to the canvas size.
    /// - Returns: A rendered UIImage of the canvas, or nil if export fails.
    public func exportCanvasImage(size: CGSize? = nil) -> UIImage? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let renderer = MetalXRenderer(device: device)
        let exportSize = size ?? canvas.size
        return renderer.renderToUIImage(canvas: canvas, size: exportSize)
    }
    
    // MARK: - Project Management
    
    private func loadProject() {
        canvas.loadFromProject(project)
        
        // Initialize background layer if not already present
        canvas.initializeBackgroundLayer()
        
        // Check if any layers are outside the canvas bounds
        var needsRepositioning = false
        let canvasBounds = CGRect(origin: .zero, size: canvas.size)
        let padding: CGFloat = 50
        
        // Comment out automatic repositioning to preserve saved positions
        // This was causing layers to be moved to center during load
        /*
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
        */
        
        // Initialize hasUnsavedChanges to false since we just loaded
        hasUnsavedChanges = false
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
    
    // Removed test layer function
    
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
        textLayer.textColor = .black
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
            shapeLayer = VectorShapeLayer.polygon(sides: 3, radius: size / 2)
        case .hexagon:
            shapeLayer = VectorShapeLayer.polygon(sides: 6, radius: size / 2)
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
    let onAddAsset: () -> Void
    let onGenerate: () -> Void
    
    var body: some View {
        NavigationStack {
            List {
                Section("Basic") {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Label("Image", systemImage: "photo")
                    }
                    .onChange(of: selectedItem) { _ in
                        if selectedItem != nil {
                            onDismiss()
                        }
                    }
                    
                    // Sticker option removed
                    
                    Button(action: onAddAsset) {
                        Label("Assets", systemImage: "sparkles")
                    }
                    
                    Button(action: onGenerate) {
                        Label("Generate Image", systemImage: "wand.and.stars")
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
