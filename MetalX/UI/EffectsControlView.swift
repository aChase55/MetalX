import SwiftUI

struct EffectsControlView: View {
    @ObservedObject var effectStack: EffectStack
    @ObservedObject var canvas: Canvas
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
                            canvas: canvas,
                            onRemove: {
                                canvas.capturePropertyChange(actionName: "Remove Effect")
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
                                    BrightnessContrastControls(effect: brightnessContrast, canvas: canvas)
                                }
                                if let hueSaturation = effect as? HueSaturationEffect {
                                    HueSaturationControls(effect: hueSaturation, canvas: canvas)
                                }
#if canImport(MetalPerformanceShaders)
                                if let blur = effect as? BlurEffect {
                                    BlurControls(effect: blur, canvas: canvas)
                                }
#endif
                                if let pixellate = effect as? PixellateEffect {
                                    PixellateControls(effect: pixellate, canvas: canvas)
                                }
                                if let noise = effect as? NoiseEffect {
                                    NoiseControls(effect: noise, canvas: canvas)
                                }
                                if let threshold = effect as? ThresholdEffect {
                                    ThresholdControls(effect: threshold, canvas: canvas)
                                }
                                if let chromatic = effect as? ChromaticAberrationEffect {
                                    ChromaticAberrationControls(effect: chromatic, canvas: canvas)
                                }
                                if let vhs = effect as? VHSEffect {
                                    VHSControls(effect: vhs, canvas: canvas)
                                }
                                if let posterize = effect as? PosterizeEffect {
                                    PosterizeControls(effect: posterize, canvas: canvas)
                                }
                                if let vignette = effect as? VignetteEffect {
                                    VignetteControls(effect: vignette, canvas: canvas)
                                }
                                if let cmyk = effect as? CMYKHalftoneEffect {
                                    CMYKHalftoneControls(effect: cmyk, canvas: canvas)
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
                canvas.capturePropertyChange(actionName: "Add Effect")
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
    @ObservedObject var canvas: Canvas
    let onRemove: () -> Void
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                // Enable/disable toggle
                Toggle("", isOn: Binding(
                    get: { effect.isEnabled },
                    set: { newValue in
                        canvas.capturePropertyChange(actionName: "Toggle Effect")
                        effect.isEnabled = newValue
                    }
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
                
                // Removed global intensity slider for effect list
                
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
#if canImport(MetalPerformanceShaders)
                Button(action: {
                    onSelect(BlurEffect())
                }) {
                    Label("Blur", systemImage: "drop")
                }
#endif
                Button(action: {
                    onSelect(PixellateEffect())
                }) {
                    Label("Pixellate", systemImage: "grid")
                }
                
                Button(action: {
                    onSelect(CMYKHalftoneEffect())
                }) {
                    Label("CMYK Halftone", systemImage: "circle.grid.2x2")
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
    @ObservedObject var canvas: Canvas
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            if let brightnessContrast = effect as? BrightnessContrastEffect {
                BrightnessContrastControls(effect: brightnessContrast, canvas: canvas)
            } else if let hueSaturation = effect as? HueSaturationEffect {
                HueSaturationControls(effect: hueSaturation, canvas: canvas)
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
    @ObservedObject var canvas: Canvas
    
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
                    .onChange(of: effect.brightness) { _ in
                        canvas.capturePropertyChange(actionName: "Change Brightness")
                        canvas.setNeedsDisplay()
                    }
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
                    .onChange(of: effect.contrast) { _ in
                        canvas.capturePropertyChange(actionName: "Change Contrast")
                        canvas.setNeedsDisplay()
                    }
            }
            
            // Reset button
            Button(action: {
                canvas.capturePropertyChange(actionName: "Reset Brightness/Contrast")
                effect.brightness = 0
                effect.contrast = 1
                canvas.setNeedsDisplay()
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
    @ObservedObject var canvas: Canvas
    
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
                    .onChange(of: effect.hueShift) { _ in
                        canvas.capturePropertyChange(actionName: "Change Hue")
                        canvas.setNeedsDisplay()
                    }
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
                    .onChange(of: effect.saturation) { _ in
                        canvas.capturePropertyChange(actionName: "Change Saturation")
                        canvas.setNeedsDisplay()
                    }
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
                    .onChange(of: effect.lightness) { _ in
                        canvas.capturePropertyChange(actionName: "Change Lightness")
                        canvas.setNeedsDisplay()
                    }
            }
            
            // Reset button
            Button(action: {
                canvas.capturePropertyChange(actionName: "Reset Hue/Saturation")
                effect.hueShift = 0
                effect.saturation = 1
                effect.lightness = 0
                canvas.setNeedsDisplay()
            }) {
                Text("Reset")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - New Effect Controls

#if canImport(MetalPerformanceShaders)
struct BlurControls: View {
    @ObservedObject var effect: BlurEffect
    @ObservedObject var canvas: Canvas
    
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Radius")
                    Spacer()
                    Text(String(format: "%.1f", effect.radius))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Slider(value: $effect.radius, in: 0...30)
                    .accentColor(.blue)
                    .onChange(of: effect.radius) { _ in
                        canvas.capturePropertyChange(actionName: "Change Blur Radius")
                        canvas.setNeedsDisplay()
                    }
            }
        }
    }
}
#endif

struct PixellateControls: View {
    @ObservedObject var effect: PixellateEffect
    @ObservedObject var canvas: Canvas
    
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
                    .onChange(of: effect.pixelSize) { _ in
                        canvas.capturePropertyChange(actionName: "Change Pixel Size")
                        canvas.setNeedsDisplay()
                    }
            }
        }
    }
}

struct NoiseControls: View {
    @ObservedObject var effect: NoiseEffect
    @ObservedObject var canvas: Canvas
    
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
                    .onChange(of: effect.amount) { _ in
                        canvas.capturePropertyChange(actionName: "Change Noise Amount")
                        canvas.setNeedsDisplay()
                    }
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
                    .onChange(of: effect.seed) { _ in
                        canvas.capturePropertyChange(actionName: "Change Noise Seed")
                        canvas.setNeedsDisplay()
                    }
            }
        }
    }
}

struct ThresholdControls: View {
    @ObservedObject var effect: ThresholdEffect
    @ObservedObject var canvas: Canvas
    
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
                    .onChange(of: effect.threshold) { _ in
                        canvas.capturePropertyChange(actionName: "Change Threshold")
                        canvas.setNeedsDisplay()
                    }
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
                    .onChange(of: effect.smoothness) { _ in
                        canvas.capturePropertyChange(actionName: "Change Threshold Smoothness")
                        canvas.setNeedsDisplay()
                    }
            }
        }
    }
}

struct ChromaticAberrationControls: View {
    @ObservedObject var effect: ChromaticAberrationEffect
    @ObservedObject var canvas: Canvas
    
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
                    .onChange(of: effect.redOffset) { _ in
                        canvas.capturePropertyChange(actionName: "Change Red Offset")
                        canvas.setNeedsDisplay()
                    }
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
                    .onChange(of: effect.blueOffset) { _ in
                        canvas.capturePropertyChange(actionName: "Change Blue Offset")
                        canvas.setNeedsDisplay()
                    }
            }
        }
    }
}

struct VHSControls: View {
    @ObservedObject var effect: VHSEffect
    @ObservedObject var canvas: Canvas
    
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
                    .onChange(of: effect.lineIntensity) { _ in
                        canvas.capturePropertyChange(actionName: "Change VHS Scanlines")
                        canvas.setNeedsDisplay()
                    }
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
                    .onChange(of: effect.noiseIntensity) { _ in
                        canvas.capturePropertyChange(actionName: "Change VHS Noise")
                        canvas.setNeedsDisplay()
                    }
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
                    .onChange(of: effect.colorBleed) { _ in
                        canvas.capturePropertyChange(actionName: "Change VHS Color Bleed")
                        canvas.setNeedsDisplay()
                    }
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
                    .onChange(of: effect.distortion) { _ in
                        canvas.capturePropertyChange(actionName: "Change VHS Distortion")
                        canvas.setNeedsDisplay()
                    }
            }
        }
    }
}

struct PosterizeControls: View {
    @ObservedObject var effect: PosterizeEffect
    @ObservedObject var canvas: Canvas
    
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
                    .onChange(of: effect.levels) { _ in
                        canvas.capturePropertyChange(actionName: "Change Posterize Levels")
                        canvas.setNeedsDisplay()
                    }
            }
        }
    }
}

struct VignetteControls: View {
    @ObservedObject var effect: VignetteEffect
    @ObservedObject var canvas: Canvas
    
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
                    .onChange(of: effect.size) { _ in
                        canvas.capturePropertyChange(actionName: "Change Vignette Size")
                        canvas.setNeedsDisplay()
                    }
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
                    .onChange(of: effect.smoothness) { _ in
                        canvas.capturePropertyChange(actionName: "Change Vignette Smoothness")
                        canvas.setNeedsDisplay()
                    }
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
                    .onChange(of: effect.darkness) { _ in
                        canvas.capturePropertyChange(actionName: "Change Vignette Darkness")
                        canvas.setNeedsDisplay()
                    }
            }
        }
    }
}

// Removed mono Halftone controls; use CMYKHalftoneControls instead

struct CMYKHalftoneControls: View {
    @ObservedObject var effect: CMYKHalftoneEffect
    @ObservedObject var canvas: Canvas
    
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
                Slider(value: $effect.dotSize, in: 2...50)
                    .accentColor(.blue)
                    .onChange(of: effect.dotSize) { _ in
                        canvas.capturePropertyChange(actionName: "Change CMYK Halftone Size")
                        canvas.setNeedsDisplay()
                    }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Angle")
                    Spacer()
                    Text(String(format: "%.0f°", effect.angle))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Slider(value: $effect.angle, in: -180...180)
                    .accentColor(.blue)
                    .onChange(of: effect.angle) { _ in
                        canvas.capturePropertyChange(actionName: "Change CMYK Halftone Angle")
                        canvas.setNeedsDisplay()
                    }
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
                    .onChange(of: effect.sharpness) { _ in
                        canvas.capturePropertyChange(actionName: "Change CMYK Halftone Sharpness")
                        canvas.setNeedsDisplay()
                    }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("GCR")
                    Spacer()
                    Text(String(format: "%.0f%%", effect.grayComponentReplacement * 100))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Slider(value: $effect.grayComponentReplacement, in: 0...1)
                    .accentColor(.blue)
                    .onChange(of: effect.grayComponentReplacement) { _ in
                        canvas.capturePropertyChange(actionName: "Change CMYK GCR")
                        canvas.setNeedsDisplay()
                    }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("UCR")
                    Spacer()
                    Text(String(format: "%.0f%%", effect.underColorRemoval * 100))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Slider(value: $effect.underColorRemoval, in: 0...1)
                    .accentColor(.blue)
                    .onChange(of: effect.underColorRemoval) { _ in
                        canvas.capturePropertyChange(actionName: "Change CMYK UCR")
                        canvas.setNeedsDisplay()
                    }
            }
        }
    }
}
