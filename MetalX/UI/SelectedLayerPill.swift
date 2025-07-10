import SwiftUI

struct SelectedLayerPill: View {
    @ObservedObject var canvas: Canvas
    @State private var selectedTab: LayerPropertyTab = .fill
    @State private var showingPropertySheet = false
    
    enum LayerPropertyTab: String, CaseIterable {
        case fill = "Fill"
        case blend = "Blend"
        case shadow = "Shadow"
        
        var systemImage: String {
            switch self {
            case .fill: return "paintbrush.fill"
            case .blend: return "rectangle.stack"
            case .shadow: return "shadow"
            }
        }
    }
    
    var selectedLayer: (any Layer)? {
        canvas.selectedLayer
    }
    
    var body: some View {
        if let layer = selectedLayer {
            // Debug: Layer selected - \(layer.name)
            VStack(spacing: 0) {
                // Layer info and tabs
                HStack(spacing: 16) {
                    // Layer info
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
                    
                    // Property tabs
                    HStack(spacing: 8) {
                        ForEach(LayerPropertyTab.allCases, id: \.self) { tab in
                            Button(action: {
                                selectedTab = tab
                                showingPropertySheet = true
                                print("Selected tab: \(tab.rawValue)")
                            }) {
                                VStack(spacing: 4) {
                                    Image(systemName: tab.systemImage)
                                        .font(.system(size: 16))
                                    Text(tab.rawValue)
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundColor(selectedTab == tab ? .white : .primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selectedTab == tab ? Color.blue : Color.clear)
                                )
                            }
                        }
                    }
                    
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
                .padding(.vertical, 12)
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: -2)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .sheet(isPresented: $showingPropertySheet) {
                LayerPropertySheet(
                    canvas: canvas,
                    selectedTab: selectedTab
                )
                .presentationDetents([.height(400), .medium])
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(false)
            }
        }
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
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                if let layer = selectedLayer {
                    switch selectedTab {
                    case .fill:
                        fillControls(for: layer)
                    case .blend:
                        blendControls(for: layer)
                    case .shadow:
                        shadowControls(for: layer)
                    }
                    
                    Spacer()
                }
            }
            .padding()
            .navigationTitle(selectedTab.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
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
            VStack(alignment: .leading, spacing: 8) {
                Text("Blend Mode")
                    .font(.headline)
                
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
                .frame(height: 150)
            }
            
            // Opacity Slider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Opacity")
                        .font(.headline)
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
            Toggle("Enable Drop Shadow", isOn: Binding(
                get: { layer.dropShadow.isEnabled },
                set: { enabled in
                    layer.dropShadow.isEnabled = enabled
                    canvas.setNeedsDisplay()
                }
            ))
            .font(.headline)
            
            if layer.dropShadow.isEnabled {
                // Shadow Color
                VStack(alignment: .leading, spacing: 8) {
                    Text("Shadow Color")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    ColorPicker("Shadow Color", selection: Binding(
                        get: { Color(UIColor(cgColor: layer.dropShadow.color)) },
                        set: { newColor in
                            layer.dropShadow.color = UIColor(newColor).cgColor
                            canvas.setNeedsDisplay()
                        }
                    ))
                    .labelsHidden()
                }
                
                // Shadow Offset
                VStack(alignment: .leading, spacing: 8) {
                    Text("Shadow Offset")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Text("X:")
                        Slider(value: Binding(
                            get: { layer.dropShadow.offset.width },
                            set: { newX in
                                layer.dropShadow.offset.width = newX
                                canvas.setNeedsDisplay()
                            }
                        ), in: -20...20)
                        Text("\(Int(layer.dropShadow.offset.width))pt")
                            .font(.caption)
                            .monospacedDigit()
                            .frame(width: 40)
                    }
                    
                    HStack {
                        Text("Y:")
                        Slider(value: Binding(
                            get: { layer.dropShadow.offset.height },
                            set: { newY in
                                layer.dropShadow.offset.height = newY
                                canvas.setNeedsDisplay()
                            }
                        ), in: -20...20)
                        Text("\(Int(layer.dropShadow.offset.height))pt")
                            .font(.caption)
                            .monospacedDigit()
                            .frame(width: 40)
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
                            canvas.setNeedsDisplay()
                        }
                    ), in: 0...20)
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
                            canvas.setNeedsDisplay()
                        }
                    ), in: 0...1)
                    .accentColor(.blue)
                }
            }
        }
    }
}

#Preview {
    VStack {
        Spacer()
        SelectedLayerPill(canvas: Canvas())
    }
    .background(Color.gray.opacity(0.2))
}