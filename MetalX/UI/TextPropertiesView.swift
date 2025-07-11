import SwiftUI
import UIKit

struct TextPropertiesView: View {
    let textLayer: TextLayer
    @ObservedObject var canvas: Canvas
    @State private var editingText: String = ""
    @State private var isEditingText = false
    @State private var showingFontPicker = false
    @State private var selectedFontSize: CGFloat = 48
    @State private var showingImagePicker = false
    @State private var gradientStartColor = Color.blue
    @State private var gradientEndColor = Color.purple
    
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
                        textLayer.fillType = .solid(textLayer.textColor)
                        canvas.setNeedsDisplay()
                    })
                    
                    FillTypeButton(title: "Gradient", isSelected: isGradientFill, action: {
                        textLayer.fillType = .gradient(
                            colors: [UIColor(gradientStartColor), UIColor(gradientEndColor)],
                            startPoint: CGPoint(x: 0, y: 0),
                            endPoint: CGPoint(x: 1, y: 1)
                        )
                        canvas.setNeedsDisplay()
                    })
                    
                    FillTypeButton(title: "Image", isSelected: isImageFill, action: {
                        showingImagePicker = true
                    })
                    
                    FillTypeButton(title: "None", isSelected: isNoFill, action: {
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
                                textLayer.fillType = .solid(UIColor(newColor))
                                canvas.setNeedsDisplay()
                            }
                        ))
                        .labelsHidden()
                    }
                    
                case .gradient(let colors, _, _):
                    VStack(spacing: 8) {
                        HStack {
                            Text("Start Color")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            ColorPicker("", selection: Binding(
                                get: { 
                                    if colors.count > 0 {
                                        return Color(colors[0])
                                    }
                                    return gradientStartColor
                                },
                                set: { newColor in
                                    gradientStartColor = newColor
                                    updateGradient()
                                }
                            ))
                            .labelsHidden()
                        }
                        
                        HStack {
                            Text("End Color")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            ColorPicker("", selection: Binding(
                                get: { 
                                    if colors.count > 1 {
                                        return Color(colors[1])
                                    }
                                    return gradientEndColor
                                },
                                set: { newColor in
                                    gradientEndColor = newColor
                                    updateGradient()
                                }
                            ))
                            .labelsHidden()
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
                        textLayer.fillType = .image(image)
                        canvas.setNeedsDisplay()
                    }
                }
            ))
        }
    }
    
    // Helper properties
    var isSolidFill: Bool {
        if case .solid = textLayer.fillType { return true }
        return false
    }
    
    var isGradientFill: Bool {
        if case .gradient = textLayer.fillType { return true }
        return false
    }
    
    var isImageFill: Bool {
        if case .image = textLayer.fillType { return true }
        return false
    }
    
    var isNoFill: Bool {
        if case .none = textLayer.fillType { return true }
        return false
    }
    
    // Helper methods
    func updateGradient() {
        textLayer.fillType = .gradient(
            colors: [UIColor(gradientStartColor), UIColor(gradientEndColor)],
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 1, y: 1)
        )
        canvas.setNeedsDisplay()
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
    let textLayer: TextLayer
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