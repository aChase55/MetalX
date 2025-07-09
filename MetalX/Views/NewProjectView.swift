import SwiftUI

struct NewProjectView: View {
    @Binding var isPresented: Bool
    let onCreate: (String, CanvasPreset) -> Void
    
    @State private var projectName = "Untitled Project"
    @State private var selectedPreset = CanvasPreset.defaultPreset
    @State private var selectedCategory: CanvasPreset.Category = .social
    
    private var presetsForCategory: [CanvasPreset] {
        CanvasPreset.presets.filter { $0.category == selectedCategory }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Project Details") {
                    TextField("Project Name", text: $projectName)
                        .textFieldStyle(.roundedBorder)
                }
                
                Section("Canvas Size") {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(CanvasPreset.Category.allCases, id: \.self) { category in
                            Text(category.rawValue).tag(category)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        ForEach(presetsForCategory) { preset in
                            PresetCard(
                                preset: preset,
                                isSelected: selectedPreset.id == preset.id,
                                onTap: { selectedPreset = preset }
                            )
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section("Preview") {
                    VStack(spacing: 8) {
                        // Visual representation of canvas
                        GeometryReader { geometry in
                            let maxWidth = geometry.size.width
                            let maxHeight: CGFloat = 200
                            let presetSize = selectedPreset.defaultEditingSize
                            let scale = min(
                                maxWidth / presetSize.width,
                                maxHeight / presetSize.height
                            )
                            let displaySize = CGSize(
                                width: presetSize.width * scale,
                                height: presetSize.height * scale
                            )
                            
                            Rectangle()
                                .fill(Color(UIColor.systemGray5))
                                .frame(width: displaySize.width, height: displaySize.height)
                                .overlay(
                                    Text(selectedPreset.name)
                                        .foregroundColor(.secondary)
                                )
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .frame(height: 200)
                        
                        Text("Canvas: \(Int(selectedPreset.defaultEditingSize.width)) × \(Int(selectedPreset.defaultEditingSize.height))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(projectName, selectedPreset)
                        isPresented = false
                    }
                    .disabled(projectName.isEmpty)
                }
            }
        }
    }
}

struct PresetCard: View {
    let preset: CanvasPreset
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        VStack(spacing: 6) {
            // Visual representation
            Rectangle()
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color(UIColor.systemGray6))
                .aspectRatio(preset.aspectRatio, contentMode: .fit)
                .frame(height: 60)
                .overlay(
                    Rectangle()
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color(UIColor.systemGray4),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
            
            Text(preset.name)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .accentColor : .primary)
                .lineLimit(1)
            
            Text(preset.description)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .onTapGesture(perform: onTap)
    }
}

#Preview {
    NewProjectView(isPresented: .constant(true)) { _, _ in }
}