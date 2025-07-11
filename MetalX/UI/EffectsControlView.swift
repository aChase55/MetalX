import SwiftUI

struct EffectsControlView: View {
    @ObservedObject var effectStack: EffectStack
    let useNavigation: Bool
    @State private var showingEffectPicker = false
    @State private var selectedEffect: Effect?
    
    init(effectStack: EffectStack, useNavigation: Bool = false) {
        self.effectStack = effectStack
        self.useNavigation = useNavigation
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with add button
            HStack {
                Text("Effects")
                    .font(.headline)
                
                Spacer()
                
                if useNavigation {
                    NavigationLink(value: "picker") {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                    }
                } else {
                    Button(action: { showingEffectPicker = true }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                    }
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
                    if useNavigation {
                        NavigationLink(value: effect.id) {
                            EffectRow(effect: effect, onRemove: {
                                effectStack.removeEffect(effect)
                            })
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        Button(action: { selectedEffect = effect }) {
                            EffectRow(effect: effect, onRemove: {
                                effectStack.removeEffect(effect)
                            })
                        }
                        .buttonStyle(PlainButtonStyle())
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
            }
            .presentationDetents([.medium])
        }
        .sheet(item: Binding<EffectWrapper?>(
            get: { selectedEffect.map(EffectWrapper.init) },
            set: { _ in selectedEffect = nil }
        )) { wrapper in
            EffectDetailView(effect: wrapper.effect)
                .presentationDetents([.medium])
        }
        .navigationDestination(for: String.self) { value in
            if value == "picker" {
                EffectPickerView { effect in
                    effectStack.addEffect(effect)
                }
            }
        }
        .navigationDestination(for: UUID.self) { effectID in
            if let effect = effectStack.effects.first(where: { $0.id == effectID }) {
                EffectDetailView(effect: effect)
            }
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
    
    var body: some View {
        HStack {
            // Enable/disable toggle
            Toggle("", isOn: Binding(
                get: { effect.isEnabled },
                set: { effect.isEnabled = $0 }
            ))
            .labelsHidden()
            .toggleStyle(SwitchToggleStyle(tint: .blue))
            .scaleEffect(0.8)
            
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
            
            // Remove button
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
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