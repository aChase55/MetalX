import SwiftUI

struct GradientEditorView: View {
    @Binding var gradientData: GradientData
    @Environment(\.dismiss) var dismiss
    let onApply: () -> Void
    
    @State private var selectedStopIndex: Int? = nil
    @State private var tempColor: Color = .white
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Gradient Preview
                gradientPreview
                    .frame(height: 100)
                    .cornerRadius(12)
                    .padding(.horizontal)
                
                // Gradient Type Picker
                Picker("Type", selection: $gradientData.type) {
                    Text("Linear").tag(Gradient.GradientType.linear)
                    Text("Radial").tag(Gradient.GradientType.radial)
                    Text("Angular").tag(Gradient.GradientType.angular)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                .onChange(of: gradientData.type) { _, _ in
                    onApply()
                }
                
                // Color Stops Editor
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Color Stops")
                            .font(.headline)
                        Spacer()
                        Button(action: addColorStop) {
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                    
                    // Gradient slider with stops
                    gradientSlider
                        .frame(height: 60)
                    
                    // Color stop list
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(Array(gradientData.colors.enumerated()), id: \.offset) { index, color in
                                ColorStopRow(
                                    color: color,
                                    location: gradientData.locations[index],
                                    isSelected: selectedStopIndex == index,
                                    onSelect: {
                                        selectedStopIndex = index
                                        tempColor = color
                                    },
                                    onDelete: {
                                        deleteColorStop(at: index)
                                    },
                                    onLocationChange: { newLocation in
                                        gradientData.locations[index] = newLocation
                                    }
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
                .padding(.horizontal)
                
                // Selected color editor
                if let selectedIndex = selectedStopIndex {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Stop Color")
                            .font(.headline)
                        
                        ColorPicker("Color", selection: $tempColor)
                            .onChange(of: tempColor) { _, newColor in
                                gradientData.colors[selectedIndex] = newColor
                                onApply()
                            }
                    }
                    .padding()
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(8)
                    .padding(.horizontal)
                }
                
                // Direction controls for linear gradient
                if gradientData.type == .linear {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Direction")
                            .font(.headline)
                        
                        HStack(spacing: 12) {
                            directionButton(.topLeading, .bottomTrailing, "arrow.down.right")
                            directionButton(.top, .bottom, "arrow.down")
                            directionButton(.topTrailing, .bottomLeading, "arrow.down.left")
                            directionButton(.leading, .trailing, "arrow.right")
                        }
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
            }
            .navigationTitle("Edit Gradient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply") {
                        onApply()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private var gradientPreview: some View {
        Group {
            switch gradientData.type {
            case .linear:
                LinearGradient(
                    colors: gradientData.colors,
                    startPoint: gradientData.linearStartPoint,
                    endPoint: gradientData.linearEndPoint
                )
            case .radial:
                RadialGradient(
                    colors: gradientData.colors,
                    center: .center,
                    startRadius: 0,
                    endRadius: 100
                )
            case .angular:
                AngularGradient(
                    colors: gradientData.colors,
                    center: .center
                )
            }
        }
    }
    
    private var gradientSlider: some View {
        GeometryReader { geometry in
            ZStack {
                // Gradient background
                LinearGradient(
                    colors: gradientData.colors,
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .cornerRadius(8)
                
                // Color stops
                ForEach(Array(gradientData.colors.enumerated()), id: \.offset) { index, color in
                    Circle()
                        .fill(color)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.black.opacity(0.2), lineWidth: 1)
                        )
                        .scaleEffect(selectedStopIndex == index ? 1.2 : 1.0)
                        .position(
                            x: CGFloat(gradientData.locations[index]) * geometry.size.width,
                            y: geometry.size.height / 2
                        )
                        .onTapGesture {
                            selectedStopIndex = index
                            tempColor = color
                        }
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let newLocation = Float(value.location.x / geometry.size.width)
                                    gradientData.locations[index] = max(0, min(1, newLocation))
                                    selectedStopIndex = index
                                    onApply()
                                }
                        )
                }
            }
        }
    }
    
    private func directionButton(_ start: UnitPoint, _ end: UnitPoint, _ icon: String) -> some View {
        Button(action: {
            gradientData.linearStartPoint = start
            gradientData.linearEndPoint = end
        }) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(
                    gradientData.linearStartPoint == start && gradientData.linearEndPoint == end
                    ? Color.accentColor
                    : Color(UIColor.tertiarySystemFill)
                )
                .foregroundColor(
                    gradientData.linearStartPoint == start && gradientData.linearEndPoint == end
                    ? .white
                    : .primary
                )
                .cornerRadius(8)
        }
    }
    
    private func addColorStop() {
        let newLocation: Float
        if gradientData.locations.isEmpty {
            newLocation = 0.5
        } else {
            // Find the largest gap to insert new stop
            var maxGap: Float = 0
            var insertLocation: Float = 0.5
            
            let sortedIndices = gradientData.locations.enumerated().sorted { $0.element < $1.element }
            
            for i in 0..<sortedIndices.count - 1 {
                let gap = sortedIndices[i + 1].element - sortedIndices[i].element
                if gap > maxGap {
                    maxGap = gap
                    insertLocation = sortedIndices[i].element + gap / 2
                }
            }
            
            newLocation = insertLocation
        }
        
        // Interpolate color at this location
        let interpolatedColor = interpolateColor(at: newLocation)
        gradientData.colors.append(interpolatedColor)
        gradientData.locations.append(newLocation)
        
        // Select the new stop
        selectedStopIndex = gradientData.colors.count - 1
        tempColor = interpolatedColor
    }
    
    private func deleteColorStop(at index: Int) {
        guard gradientData.colors.count > 2 else { return } // Keep at least 2 stops
        
        gradientData.colors.remove(at: index)
        gradientData.locations.remove(at: index)
        
        if selectedStopIndex == index {
            selectedStopIndex = nil
        } else if let selected = selectedStopIndex, selected > index {
            selectedStopIndex = selected - 1
        }
    }
    
    private func interpolateColor(at location: Float) -> Color {
        // Find surrounding stops
        let sortedStops = zip(gradientData.locations, gradientData.colors)
            .sorted { $0.0 < $1.0 }
        
        for i in 0..<sortedStops.count - 1 {
            if location >= sortedStops[i].0 && location <= sortedStops[i + 1].0 {
                let t = (location - sortedStops[i].0) / (sortedStops[i + 1].0 - sortedStops[i].0)
                return Color.interpolate(from: sortedStops[i].1, to: sortedStops[i + 1].1, fraction: CGFloat(t))
            }
        }
        
        return gradientData.colors.last ?? .white
    }
}

struct ColorStopRow: View {
    let color: Color
    let location: Float
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onLocationChange: (Float) -> Void
    
    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 30, height: 30)
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.accentColor : Color.gray, lineWidth: 2)
                )
                .onTapGesture(perform: onSelect)
            
            Text("\(Int(location * 100))%")
                .font(.caption)
                .monospacedDigit()
                .frame(width: 40)
            
            Slider(value: .init(
                get: { CGFloat(location) },
                set: { onLocationChange(Float($0)) }
            ))
            
            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 4)
    }
}

extension Color {
    static func interpolate(from: Color, to: Color, fraction: CGFloat) -> Color {
        let f = max(0, min(1, fraction))
        
        let c1 = UIColor(from)
        let c2 = UIColor(to)
        
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        
        c1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        c2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        
        let r = r1 + (r2 - r1) * f
        let g = g1 + (g2 - g1) * f
        let b = b1 + (b2 - b1) * f
        let a = a1 + (a2 - a1) * f
        
        return Color(UIColor(red: r, green: g, blue: b, alpha: a))
    }
}