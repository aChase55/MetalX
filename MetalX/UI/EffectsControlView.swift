import SwiftUI

struct EffectsControlView: View {
    @ObservedObject var effectStack: EffectStack
    @State private var showingEffectPicker = false
    @State private var selectedEffect: Effect?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with add button
            HStack {
                Text("Effects")
                    .font(.headline)
                
                Spacer()
                
                Button(action: { showingEffectPicker = true }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            
            if effectStack.effects.isEmpty {
                Text("No effects applied")
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .padding(.vertical, 8)
            } else {
                // List of effects
                ForEach(effectStack.effects, id: \.id) { effect in
                    VStack(alignment: .leading, spacing: 8) {
                        // Effect row
                        EffectRow(
                            effect: effect,
                            onRemove: {
                                effectStack.removeEffect(effect)
                                if selectedEffect?.id == effect.id {
                                    selectedEffect = nil
                                }
                            },
                            onSelect: {
                                selectedEffect = selectedEffect?.id == effect.id ? nil : effect
                            }
                        )
                        
                        // Inline controls when selected
                        if selectedEffect?.id == effect.id {
                            VStack(alignment: .leading, spacing: 12) {
                                if let brightnessContrast = effect as? BrightnessContrastEffect {
                                    BrightnessContrastControls(effect: brightnessContrast)
                                } else if let hueSaturation = effect as? HueSaturationEffect {
                                    HueSaturationControls(effect: hueSaturation)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(UIColor.systemGray6))
                            )
                        }
                    }
                }
                .onMove { source, destination in
                    effectStack.moveEffect(from: source, to: destination)
                }
            }
        }
        .sheet(isPresented: $showingEffectPicker) {
            EffectPickerView { effect in
                effectStack.addEffect(effect)
                showingEffectPicker = false
                selectedEffect = effect // Show controls for newly added effect
            }
            .asSelfSizingSheet()
        }
    }
}

// Wrapper to make Effect conform to Identifiable for sheet presentation
struct EffectWrapper: Identifiable {
    let id = UUID()
    let effect: Effect
}

struct EffectRow: View {
    let effect: Effect
    let onRemove: () -> Void
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                // Enable/disable toggle
                Toggle("", isOn: Binding(
                    get: { effect.isEnabled },
                    set: { effect.isEnabled = $0 }
                ))
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .scaleEffect(0.8)
                .onTapGesture {
                    // Prevent button action when toggling
                }
                
                // Effect name
                Text(effect.name)
                    .foregroundColor(effect.isEnabled ? .primary : .secondary)
                
                Spacer()
                
                // Intensity slider
                Slider(value: Binding(
                    get: { CGFloat(effect.intensity) },
                    set: { effect.intensity = Float($0) }
                ), in: 0...1)
                .frame(width: 80)
                .disabled(!effect.isEnabled)
                .onTapGesture {
                    // Prevent button action when using slider
                }
                
                // Remove button
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .onTapGesture {
                    // Prevent button action when removing
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct EffectPickerView: View {
    let onSelect: (Effect) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            Section("Color Adjustments") {
                Button(action: {
                    onSelect(BrightnessContrastEffect())
                }) {
                    Label("Brightness/Contrast", systemImage: "sun.max")
                }
                
                Button(action: {
                    onSelect(HueSaturationEffect())
                }) {
                    Label("Hue/Saturation", systemImage: "paintpalette")
                }
            }
        }
        .navigationTitle("Add Effect")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct EffectDetailView: View {
    let effect: Effect
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            if let brightnessContrast = effect as? BrightnessContrastEffect {
                BrightnessContrastControls(effect: brightnessContrast)
            } else if let hueSaturation = effect as? HueSaturationEffect {
                HueSaturationControls(effect: hueSaturation)
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle(effect.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct BrightnessContrastControls: View {
    @ObservedObject var effect: BrightnessContrastEffect
    
    var body: some View {
        VStack(spacing: 20) {
            // Brightness
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Brightness")
                    Spacer()
                    Text(String(format: "%.0f", effect.brightness * 100))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Slider(value: $effect.brightness, in: -1...1)
                    .accentColor(.blue)
            }
            
            // Contrast
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Contrast")
                    Spacer()
                    Text(String(format: "%.0f", (effect.contrast - 1) * 100))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Slider(value: $effect.contrast, in: 0...2)
                    .accentColor(.blue)
            }
            
            // Reset button
            Button(action: {
                effect.brightness = 0
                effect.contrast = 1
            }) {
                Text("Reset")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}

struct HueSaturationControls: View {
    @ObservedObject var effect: HueSaturationEffect
    
    var body: some View {
        VStack(spacing: 20) {
            // Hue
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Hue")
                    Spacer()
                    Text(String(format: "%.0f°", effect.hueShift))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Slider(value: $effect.hueShift, in: -180...180)
                    .accentColor(.blue)
            }
            
            // Saturation
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Saturation")
                    Spacer()
                    Text(String(format: "%.0f", (effect.saturation - 1) * 100))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Slider(value: $effect.saturation, in: 0...2)
                    .accentColor(.blue)
            }
            
            // Lightness
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Lightness")
                    Spacer()
                    Text(String(format: "%.0f", effect.lightness * 100))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Slider(value: $effect.lightness, in: -1...1)
                    .accentColor(.blue)
            }
            
            // Reset button
            Button(action: {
                effect.hueShift = 0
                effect.saturation = 1
                effect.lightness = 0
            }) {
                Text("Reset")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}