import SwiftUI

struct TextPropertiesView: View {
    let textLayer: TextLayer
    @ObservedObject var canvas: Canvas
    @State private var editingText: String = ""
    @State private var isEditingText = false
    @State private var showingFontPicker = false
    @State private var selectedFontSize: CGFloat = 48
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Text content editing
            VStack(alignment: .leading, spacing: 8) {
                Text("Text Content")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if isEditingText {
                    HStack {
                        TextField("Enter text", text: $editingText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onSubmit {
                                textLayer.text = editingText
                                canvas.setNeedsDisplay()
                                isEditingText = false
                            }
                        
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
                            .lineLimit(1)
                            .truncationMode(.tail)
                        
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
            
            // Text color
            HStack {
                Text("Text Color")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                ColorPicker("", selection: Binding(
                    get: { Color(textLayer.textColor) },
                    set: { newColor in
                        textLayer.textColor = UIColor(newColor)
                        canvas.setNeedsDisplay()
                    }
                ))
                .labelsHidden()
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
                
                if textLayer.hasOutline {
                    // Outline color
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
                    
                    // Outline width
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
        }
        .sheet(isPresented: $showingFontPicker) {
            FontPickerView(textLayer: textLayer, canvas: canvas)
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