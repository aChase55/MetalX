import SwiftUI
import UIKit

struct TextPropertiesView: View {
    @ObservedObject var textLayer: TextLayer
    @ObservedObject var canvas: Canvas
    @State private var editingText: String = ""
    @State private var isEditingText = false
    @State private var showingFontPicker = false
    @State private var selectedFontSize: CGFloat = 48
    @State private var showingImagePicker = false
    @State private var gradientData = GradientData()
    @State private var lastSolidColor = Color.white
    @State private var showingGradientEditor = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Text content editing
            VStack(alignment: .leading, spacing: 8) {
                Text("Text Content")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if isEditingText {
                    VStack(alignment: .trailing, spacing: 8) {
                        TextEditor(text: $editingText)
                            .frame(minHeight: 60, maxHeight: 120)
                            .padding(4)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                            .scrollContentBackground(.hidden)
                            .background(Color.gray.opacity(0.05))
                            .cornerRadius(8)
                        
                        Button("Done") {
                            canvas.capturePropertyChange(actionName: "Change Text")
                            textLayer.text = editingText
                            canvas.setNeedsDisplay()
                            isEditingText = false
                        }
                        .foregroundColor(.blue)
                    }
                } else {
                    HStack {
                        Text(textLayer.text)
                            .lineLimit(3)
                            .truncationMode(.tail)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Spacer()
                        
                        Button("Edit") {
                            editingText = textLayer.text
                            isEditingText = true
                        }
                        .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.1))
                    )
                }
            }
            
            Divider()
            
            // Font selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Font")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Button(action: {
                    showingFontPicker = true
                }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(textLayer.font.familyName)
                                .font(.system(size: 14))
                            Text("\(Int(textLayer.font.pointSize))pt")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.1))
                    )
                }
                .foregroundColor(.primary)
            }
            
            // Font size slider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Size")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(textLayer.font.pointSize))pt")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Slider(value: Binding(
                    get: { textLayer.font.pointSize },
                    set: { newSize in
                        canvas.capturePropertyChange(actionName: "Change Font Size")
                        textLayer.font = textLayer.font.withSize(newSize)
                        canvas.setNeedsDisplay()
                    }
                ), in: 12...200, step: 1)
                .accentColor(.blue)
            }
            
            Divider()
            
            // Text Fill Type
            VStack(alignment: .leading, spacing: 12) {
                Text("Fill Type")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // Fill type selector
                HStack(spacing: 12) {
                    FillTypeButton(title: "Solid", isSelected: isSolidFill, action: {
                        canvas.capturePropertyChange(actionName: "Change Text Fill Type")
                        textLayer.fillType = .solid(UIColor(lastSolidColor))
                        canvas.setNeedsDisplay()
                    })
                    
                    FillTypeButton(title: "Gradient", isSelected: isGradientFill, action: {
                        if case .gradient = textLayer.fillType {
                            // Already gradient, show editor
                            showingGradientEditor = true
                        } else {
                            // Switch to gradient with default
                            canvas.capturePropertyChange(actionName: "Change Text Fill Type")
                            textLayer.fillType = .gradient(gradientData.toGradient())
                            canvas.setNeedsDisplay()
                        }
                    })
                    
                    FillTypeButton(title: "Image", isSelected: isImageFill, action: {
                        if case .image = textLayer.fillType {
                            // Already has image, show picker to change it
                            showingImagePicker = true
                        } else {
                            // Set to image fill and show picker
                            showingImagePicker = true
                        }
                    })
                    
                    FillTypeButton(title: "None", isSelected: isNoFill, action: {
                        canvas.capturePropertyChange(actionName: "Change Text Fill Type")
                        textLayer.fillType = .none
                        canvas.setNeedsDisplay()
                    })
                }
                
                // Fill-specific controls
                switch textLayer.fillType {
                case .solid(let color):
                    HStack {
                        Text("Color")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        ColorPicker("", selection: Binding(
                            get: { Color(color) },
                            set: { newColor in
                                canvas.capturePropertyChange(actionName: "Change Text Color")
                                lastSolidColor = newColor
                                textLayer.fillType = .solid(UIColor(newColor))
                                canvas.setNeedsDisplay()
                            }
                        ))
                        .labelsHidden()
                    }
                    
                case .gradient(let gradient):
                    VStack(spacing: 12) {
                        // Gradient preview
                        GradientPreview(gradientData: gradientData)
                            .frame(height: 60)
                            .cornerRadius(8)
                        
                        // Edit gradient button
                        Button(action: {
                            showingGradientEditor = true
                        }) {
                            HStack {
                                Image(systemName: "slider.horizontal.3")
                                Text("Edit Gradient")
                            }
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    
                case .image:
                    Button(action: { showingImagePicker = true }) {
                        HStack {
                            Image(systemName: "photo")
                            Text("Change Image")
                        }
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                case .none:
                    Text("Text will be outline only")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Text outline
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Text Outline", isOn: Binding(
                    get: { textLayer.hasOutline },
                    set: { enabled in
                        canvas.capturePropertyChange(actionName: "Toggle Text Outline")
                        textLayer.hasOutline = enabled
                        canvas.setNeedsDisplay()
                    }
                ))
                
                // Outline color - always visible
                HStack {
                    Text("Outline Color")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    ColorPicker("", selection: Binding(
                        get: { Color(textLayer.outlineColor) },
                        set: { newColor in
                            canvas.capturePropertyChange(actionName: "Change Outline Color")
                            textLayer.outlineColor = UIColor(newColor)
                            canvas.setNeedsDisplay()
                        }
                    ))
                    .labelsHidden()
                }
                
                // Outline width - always visible
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Outline Width")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.1f", textLayer.outlineWidth))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(value: Binding(
                        get: { textLayer.outlineWidth },
                        set: { newWidth in
                            textLayer.outlineWidth = newWidth
                            canvas.setNeedsDisplay()
                        }
                    ), in: 0.5...10)
                    .accentColor(.blue)
                    .onChange(of: textLayer.outlineWidth) { _ in
                        canvas.capturePropertyChange(actionName: "Change Outline Width")
                    }
                }
            }
        }
        .sheet(isPresented: $showingFontPicker) {
            FontPickerView(textLayer: textLayer, canvas: canvas)
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(selectedImage: Binding(
                get: { 
                    if case .image(let img) = textLayer.fillType {
                        return img
                    }
                    return nil
                },
                set: { newImage in
                    if let image = newImage {
                        canvas.capturePropertyChange(actionName: "Change Text Image Fill")
                        textLayer.fillType = .image(image)
                        canvas.setNeedsDisplay()
                    }
                }
            ))
        }
        .onAppear {
            // Initialize state from text layer
            switch textLayer.fillType {
            case .solid(let color):
                lastSolidColor = Color(color)
            case .gradient(let gradient):
                gradientData = GradientData(from: gradient)
            default:
                break
            }
        }
        .sheet(isPresented: $showingGradientEditor) {
            GradientEditorView(gradientData: $gradientData) {
                canvas.capturePropertyChange(actionName: "Change Text Gradient")
                textLayer.fillType = .gradient(gradientData.toGradient())
                canvas.setNeedsDisplay()
            }
        }
    }
    
    // Helper properties
    var isSolidFill: Bool {
        switch textLayer.fillType {
        case .solid: return true
        default: return false
        }
    }
    
    var isGradientFill: Bool {
        switch textLayer.fillType {
        case .gradient: return true
        default: return false
        }
    }
    
    var isImageFill: Bool {
        switch textLayer.fillType {
        case .image: return true
        default: return false
        }
    }
    
    var isNoFill: Bool {
        switch textLayer.fillType {
        case .none: return true
        default: return false
        }
    }
    
}

// Fill type button component
struct FillTypeButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color.gray.opacity(0.2))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(8)
        }
    }
}

// Font picker view
struct FontPickerView: View {
    @ObservedObject var textLayer: TextLayer
    @ObservedObject var canvas: Canvas
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    
    let fontFamilies = UIFont.familyNames.sorted()
    
    var filteredFonts: [String] {
        if searchText.isEmpty {
            return fontFamilies
        }
        return fontFamilies.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        NavigationView {
            List {
                ForEach(filteredFonts, id: \.self) { family in
                    Section(header: Text(family)) {
                        ForEach(UIFont.fontNames(forFamilyName: family).sorted(), id: \.self) { fontName in
                            Button(action: {
                                if let font = UIFont(name: fontName, size: textLayer.font.pointSize) {
                                    canvas.capturePropertyChange(actionName: "Change Font")
                                    textLayer.font = font
                                    canvas.setNeedsDisplay()
                                    dismiss()
                                }
                            }) {
                                HStack {
                                    Text("Sample Text")
                                        .font(Font(UIFont(name: fontName, size: 16) ?? UIFont.systemFont(ofSize: 16)))
                                    
                                    Spacer()
                                    
                                    if fontName == textLayer.font.fontName {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                            .foregroundColor(.primary)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search fonts")
            .navigationTitle("Choose Font")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
