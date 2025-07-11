import SwiftUI

struct SelectedLayerPill: View {
    @ObservedObject var canvas: Canvas
    @State private var selectedTab: LayerPropertyTab?
    
    enum LayerPropertyTab: String, CaseIterable, Identifiable {
        var id: String { rawValue }
        case position = "Position"
        case fill = "Fill"
        case blend = "Blend"
        case shadow = "Shadow"
        case effects = "Effects"
        
        var systemImage: String {
            switch self {
            case .position: return "arrow.up.arrow.down.square"
            case .fill: return "paintbrush.fill"
            case .blend: return "rectangle.stack"
            case .shadow: return "shadow"
            case .effects: return "wand.and.stars"
            }
        }
    }
    
    var selectedLayer: (any Layer)? {
        canvas.selectedLayer
    }
    
    var availableTabs: [LayerPropertyTab] {
        guard let layer = selectedLayer else { return LayerPropertyTab.allCases }
        
        // Hide Fill tab for ImageLayers
        if layer is ImageLayer {
            return [.position, .blend, .shadow, .effects]
        }
        return LayerPropertyTab.allCases
    }
    
    var body: some View {
        if let layer = selectedLayer {
            // Debug: Layer selected - \(layer.name)
            VStack(spacing: 0) {
                // Layer info row
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(layer.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                        Text(String(format: "%.0f%% opacity", layer.opacity * 100))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .id(layer.opacity) // Force update when opacity changes
                    
                    Spacer()
                    
                    // Close button
                    Button(action: {
                        canvas.selectLayer(nil)
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                
                // Property tabs row
                HStack(spacing: 0) {
                    ForEach(availableTabs, id: \.self) { tab in
                        Button(action: {
                            selectedTab = tab
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: tab.systemImage)
                                    .font(.system(size: 16))
                                Text(tab.rawValue)
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.clear)
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: -2)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .sheet(item: $selectedTab, content: { tab in
                LayerPropertySheet(
                    canvas: canvas,
                    selectedTab: tab
                )
                .asSelfSizingSheet()
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled)
                .interactiveDismissDisabled(false)
            })
        }
    }
}

// Self-sizing sheet implementation
extension View {
    func asSelfSizingSheet() -> some View {
        modifier(SelfSizingSheet())
    }
}

struct SelfSizingSheet: ViewModifier {
    @State private var sheetHeight: CGFloat = .zero
    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geometry in
                    Color.clear.preference(key: InnerHeightPreferenceKey.self, value: geometry.size.height)
                }
            }
            .onPreferenceChange(InnerHeightPreferenceKey.self) { newHeight in
                sheetHeight = newHeight
            }
            .presentationDetents([.height(sheetHeight)])
    }
}

struct InnerHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = .zero
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct LayerPropertySheet: View {
    @ObservedObject var canvas: Canvas
    let selectedTab: SelectedLayerPill.LayerPropertyTab
    @Environment(\.dismiss) private var dismiss
    
    var selectedLayer: (any Layer)? {
        canvas.selectedLayer
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let layer = selectedLayer {
                switch selectedTab {
                case .position:
                    positionControls(for: layer)
                case .fill:
                    fillControls(for: layer)
                case .blend:
                    blendControls(for: layer)
                case .shadow:
                    shadowControls(for: layer)
                case .effects:
                    effectsControls(for: layer)
                }
            }
        }
        .padding()
    }
    
    @ViewBuilder
    private func positionControls(for layer: any Layer) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Position controls - X and Y side by side
            HStack(spacing: 20) {
                // X Position
                HStack(spacing: 8) {
                    Text("X:")
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                    
                    Button(action: {
                        layer.transform.position.x -= 1
                        canvas.setNeedsDisplay()
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.blue)
                    }
                    
                    Text(String(format: "%.0f", layer.transform.position.x))
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 50)
                    
                    Button(action: {
                        layer.transform.position.x += 1
                        canvas.setNeedsDisplay()
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                    }
                }
                
                // Y Position
                HStack(spacing: 8) {
                    Text("Y:")
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                    
                    Button(action: {
                        layer.transform.position.y -= 1
                        canvas.setNeedsDisplay()
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.blue)
                    }
                    
                    Text(String(format: "%.0f", layer.transform.position.y))
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 50)
                    
                    Button(action: {
                        layer.transform.position.y += 1
                        canvas.setNeedsDisplay()
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                    }
                }
            }
            
            Divider()
            
            // Transform controls
            VStack(alignment: .leading, spacing: 12) {
                
                HStack(spacing: 16) {
                    // Flip Horizontal
                    Button(action: {
                        layer.transform.flipHorizontal.toggle()
                        canvas.setNeedsDisplay()
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.left.and.right")
                                .font(.system(size: 20))
                            Text("Flip H")
                                .font(.caption)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.1))
                    )
                    
                    // Flip Vertical
                    Button(action: {
                        layer.transform.flipVertical.toggle()
                        canvas.setNeedsDisplay()
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.up.and.down")
                                .font(.system(size: 20))
                            Text("Flip V")
                                .font(.caption)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.1))
                    )
                }
            }
            
            Divider()
            
            // Layer actions
            VStack(alignment: .leading, spacing: 12) {
                
                HStack(spacing: 16) {
                    // Duplicate
                    Button(action: {
                        duplicateLayer(layer)
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 20))
                            Text("Duplicate")
                                .font(.caption)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.green.opacity(0.1))
                    )
                    
                    // Move Up
                    Button(action: {
                        canvas.moveLayerUp(layer)
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.up.square")
                                .font(.system(size: 20))
                            Text("Move Up")
                                .font(.caption)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.orange.opacity(0.1))
                    )
                    .disabled(!canvas.canMoveLayerUp(layer))
                    
                    // Move Down
                    Button(action: {
                        canvas.moveLayerDown(layer)
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.down.square")
                                .font(.system(size: 20))
                            Text("Move Down")
                                .font(.caption)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.orange.opacity(0.1))
                    )
                    .disabled(!canvas.canMoveLayerDown(layer))
                }
                
                // Delete button
                Button(action: {
                    deleteLayer(layer)
                }) {
                    HStack {
                        Image(systemName: "trash")
                            .font(.system(size: 16))
                        Text("Delete Layer")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red)
                    )
                }
            }
        }
    }
    
    private func duplicateLayer(_ layer: any Layer) {
        // Create a copy of the layer
        var newLayer: (any Layer)?
        
        if let imageLayer = layer as? ImageLayer {
            let copy = ImageLayer()
            copy.texture = imageLayer.texture
            copy.name = "\(imageLayer.name) Copy"
            newLayer = copy
        } else if let shapeLayer = layer as? VectorShapeLayer {
            let copy = VectorShapeLayer()
            copy.path = shapeLayer.path
            copy.fillType = shapeLayer.fillType
            copy.strokeColor = shapeLayer.strokeColor
            copy.strokeWidth = shapeLayer.strokeWidth
            copy.name = "\(shapeLayer.name) Copy"
            copy.bounds = shapeLayer.bounds
            newLayer = copy
        } else if let textLayer = layer as? TextLayer {
            let copy = TextLayer(text: textLayer.text)
            copy.font = textLayer.font
            copy.textColor = textLayer.textColor
            copy.name = "\(textLayer.name) Copy"
            newLayer = copy
        }
        
        if let newLayer = newLayer {
            // Copy common properties
            newLayer.transform = layer.transform
            newLayer.transform.position = CGPoint(x: layer.transform.position.x + 20, y: layer.transform.position.y + 20)
            newLayer.opacity = layer.opacity
            newLayer.blendMode = layer.blendMode
            newLayer.dropShadow = layer.dropShadow
            
            // Add to canvas
            canvas.addLayer(newLayer)
            canvas.selectLayer(newLayer)
        }
    }
    
    private func deleteLayer(_ layer: any Layer) {
        canvas.removeLayer(layer)
        dismiss()
    }
    
    @ViewBuilder
    private func fillControls(for layer: any Layer) -> some View {
        if let shapeLayer = layer as? VectorShapeLayer {
            ShapePropertiesView(canvas: canvas)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Text("Fill properties are not available for this layer type.")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private func blendControls(for layer: any Layer) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Blend Mode Picker
            Picker("Blend Mode", selection: Binding(
                get: { layer.blendMode },
                set: { newMode in
                    layer.blendMode = newMode
                    canvas.setNeedsDisplay()
                }
            )) {
                ForEach(BlendMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue.capitalized).tag(mode)
                }
            }
            .pickerStyle(WheelPickerStyle())
            .frame(height: 120)
            
            Divider()
            
            // Opacity Slider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Opacity")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(layer.opacity * 100))%")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Slider(value: Binding(
                    get: { CGFloat(layer.opacity) },
                    set: { newOpacity in
                        layer.opacity = Float(newOpacity)
                        canvas.setNeedsDisplay()
                    }
                ), in: 0...1)
                .accentColor(.blue)
            }
        }
    }
    
    @ViewBuilder
    private func shadowControls(for layer: any Layer) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Drop Shadow Toggle
            Toggle("Drop Shadow", isOn: Binding(
                get: { layer.dropShadow.isEnabled },
                set: { enabled in
                    layer.dropShadow.isEnabled = enabled
                    canvas.updateShadowForLayer(layer)
                }
            ))
            
            if layer.dropShadow.isEnabled {
                Divider()
                
                // Shadow Color with inline picker
                HStack {
                    Text("Color")
                        .foregroundColor(.secondary)
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: { Color(UIColor(cgColor: layer.dropShadow.color)) },
                        set: { newColor in
                            layer.dropShadow.color = UIColor(newColor).cgColor
                            canvas.updateShadowForLayer(layer)
                        }
                    ))
                    .labelsHidden()
                }
                
                // Shadow Offset - X and Y on same line with compact sliders
                VStack(alignment: .leading, spacing: 8) {
                    Text("Offset")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Text("X")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 15)
                            Slider(value: Binding(
                                get: { layer.dropShadow.offset.width },
                                set: { newX in
                                    layer.dropShadow.offset.width = newX
                                    canvas.updateShadowForLayer(layer)
                                }
                            ), in: -100...100)
                            Text("\(Int(layer.dropShadow.offset.width))")
                                .font(.caption)
                                .monospacedDigit()
                                .frame(width: 30)
                        }
                        
                        HStack(spacing: 4) {
                            Text("Y")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 15)
                            Slider(value: Binding(
                                get: { layer.dropShadow.offset.height },
                                set: { newY in
                                    layer.dropShadow.offset.height = newY
                                    canvas.updateShadowForLayer(layer)
                                }
                            ), in: -100...100)
                            Text("\(Int(layer.dropShadow.offset.height))")
                                .font(.caption)
                                .monospacedDigit()
                                .frame(width: 30)
                        }
                    }
                }
                
                // Shadow Blur
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Shadow Blur")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(layer.dropShadow.blur))pt")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(value: Binding(
                        get: { layer.dropShadow.blur },
                        set: { newBlur in
                            layer.dropShadow.blur = newBlur
                            canvas.updateShadowForLayer(layer)
                        }
                    ), in: 0...100)
                    .accentColor(.blue)
                }
                
                // Shadow Scale
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Shadow Scale")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.1fx", layer.dropShadow.scale))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(value: Binding(
                        get: { layer.dropShadow.scale },
                        set: { newScale in
                            layer.dropShadow.scale = newScale
                            canvas.updateShadowForLayer(layer)
                        }
                    ), in: 0.5...2.0)
                    .accentColor(.blue)
                }
                
                // Shadow Opacity
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Shadow Opacity")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(layer.dropShadow.opacity * 100))%")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(value: Binding(
                        get: { CGFloat(layer.dropShadow.opacity) },
                        set: { newOpacity in
                            layer.dropShadow.opacity = Float(newOpacity)
                            canvas.updateShadowForLayer(layer)
                        }
                    ), in: 0...1)
                    .accentColor(.blue)
                }
            }
        }
    }
    
    @ViewBuilder
    private func effectsControls(for layer: any Layer) -> some View {
        EffectsControlView(effectStack: layer.effectStack)
    }
}

#Preview {
    VStack {
        Spacer()
        SelectedLayerPill(canvas: Canvas())
    }
    .background(Color.gray.opacity(0.2))
}
