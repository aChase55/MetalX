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
                                } else if let pixellate = effect as? PixellateEffect {
                                    PixellateControls(effect: pixellate)
                                } else if let noise = effect as? NoiseEffect {
                                    NoiseControls(effect: noise)
                                } else if let threshold = effect as? ThresholdEffect {
                                    ThresholdControls(effect: threshold)
                                } else if let chromatic = effect as? ChromaticAberrationEffect {
                                    ChromaticAberrationControls(effect: chromatic)
                                } else if let vhs = effect as? VHSEffect {
                                    VHSControls(effect: vhs)
                                } else if let posterize = effect as? PosterizeEffect {
                                    PosterizeControls(effect: posterize)
                                } else if let vignette = effect as? VignetteEffect {
                                    VignetteControls(effect: vignette)
                                } else if let halftone = effect as? HalftoneEffect {
                                    HalftoneControls(effect: halftone)
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
                
                Button(action: {
                    onSelect(ThresholdEffect())
                }) {
                    Label("Threshold", systemImage: "circle.righthalf.filled")
                }
                
                Button(action: {
                    onSelect(PosterizeEffect())
                }) {
                    Label("Posterize", systemImage: "rectangle.3.group")
                }
            }
            
            Section("Stylize") {
                Button(action: {
                    onSelect(PixellateEffect())
                }) {
                    Label("Pixellate", systemImage: "grid")
                }
                
                Button(action: {
                    onSelect(HalftoneEffect())
                }) {
                    Label("Halftone", systemImage: "circle.grid.3x3")
                }
                
                Button(action: {
                    onSelect(VignetteEffect())
                }) {
                    Label("Vignette", systemImage: "circle.dashed")
                }
            }
            
            Section("Distort") {
                Button(action: {
                    onSelect(ChromaticAberrationEffect())
                }) {
                    Label("Chromatic Aberration", systemImage: "eye.trianglebadge.exclamationmark")
                }
                
                Button(action: {
                    onSelect(VHSEffect())
                }) {
                    Label("VHS", systemImage: "tv.and.hifispeaker.fill")
                }
            }
            
            Section("Noise") {
                Button(action: {
                    onSelect(NoiseEffect())
                }) {
                    Label("Noise", systemImage: "waveform")
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

// MARK: - New Effect Controls

struct PixellateControls: View {
    @ObservedObject var effect: PixellateEffect
    
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Pixel Size")
                    Spacer()
                    Text(String(format: "%.0f", effect.pixelSize))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Slider(value: $effect.pixelSize, in: 1...32)
                    .accentColor(.blue)
            }
        }
    }
}

struct NoiseControls: View {
    @ObservedObject var effect: NoiseEffect
    
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Amount")
                    Spacer()
                    Text(String(format: "%.0f%%", effect.amount * 100))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Slider(value: $effect.amount, in: 0...1)
                    .accentColor(.blue)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Seed")
                    Spacer()
                    Text(String(format: "%.2f", effect.seed))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Slider(value: $effect.seed, in: 0...1)
                    .accentColor(.blue)
            }
        }
    }
}

struct ThresholdControls: View {
    @ObservedObject var effect: ThresholdEffect
    
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Threshold")
                    Spacer()
                    Text(String(format: "%.0f%%", effect.threshold * 100))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Slider(value: $effect.threshold, in: 0...1)
                    .accentColor(.blue)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Smoothness")
                    Spacer()
                    Text(String(format: "%.0f%%", effect.smoothness * 100))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Slider(value: $effect.smoothness, in: 0...0.1)
                    .accentColor(.blue)
            }
        }
    }
}

struct ChromaticAberrationControls: View {
    @ObservedObject var effect: ChromaticAberrationEffect
    
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Red Offset")
                    Spacer()
                    Text(String(format: "%.1f", effect.redOffset))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Slider(value: $effect.redOffset, in: -10...10)
                    .accentColor(.blue)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Blue Offset")
                    Spacer()
                    Text(String(format: "%.1f", effect.blueOffset))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Slider(value: $effect.blueOffset, in: -10...10)
                    .accentColor(.blue)
            }
        }
    }
}

struct VHSControls: View {
    @ObservedObject var effect: VHSEffect
    
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Scanlines")
                    Spacer()
                    Text(String(format: "%.0f%%", effect.lineIntensity * 100))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Slider(value: $effect.lineIntensity, in: 0...1)
                    .accentColor(.blue)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Noise")
                    Spacer()
                    Text(String(format: "%.0f%%", effect.noiseIntensity * 100))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Slider(value: $effect.noiseIntensity, in: 0...1)
                    .accentColor(.blue)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Color Bleed")
                    Spacer()
                    Text(String(format: "%.0f%%", effect.colorBleed * 100))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Slider(value: $effect.colorBleed, in: 0...1)
                    .accentColor(.blue)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Distortion")
                    Spacer()
                    Text(String(format: "%.0f%%", effect.distortion * 100))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Slider(value: $effect.distortion, in: 0...1)
                    .accentColor(.blue)
            }
        }
    }
}

struct PosterizeControls: View {
    @ObservedObject var effect: PosterizeEffect
    
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Levels")
                    Spacer()
                    Text(String(format: "%.0f", effect.levels))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Slider(value: $effect.levels, in: 2...32)
                    .accentColor(.blue)
            }
        }
    }
}

struct VignetteControls: View {
    @ObservedObject var effect: VignetteEffect
    
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Size")
                    Spacer()
                    Text(String(format: "%.0f%%", effect.size * 100))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Slider(value: $effect.size, in: 0...2)
                    .accentColor(.blue)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Smoothness")
                    Spacer()
                    Text(String(format: "%.0f%%", effect.smoothness * 100))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Slider(value: $effect.smoothness, in: 0...1)
                    .accentColor(.blue)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Darkness")
                    Spacer()
                    Text(String(format: "%.0f%%", effect.darkness * 100))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Slider(value: $effect.darkness, in: 0...1)
                    .accentColor(.blue)
            }
        }
    }
}

struct HalftoneControls: View {
    @ObservedObject var effect: HalftoneEffect
    
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Dot Size")
                    Spacer()
                    Text(String(format: "%.0f", effect.dotSize))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Slider(value: $effect.dotSize, in: 2...32)
                    .accentColor(.blue)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Angle")
                    Spacer()
                    Text(String(format: "%.0f°", effect.angle))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Slider(value: $effect.angle, in: 0...180)
                    .accentColor(.blue)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Sharpness")
                    Spacer()
                    Text(String(format: "%.0f%%", effect.sharpness * 100))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Slider(value: $effect.sharpness, in: 0...1)
                    .accentColor(.blue)
            }
        }
    }
}