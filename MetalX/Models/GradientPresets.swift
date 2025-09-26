import SwiftUI

struct GradientPreset: Identifiable {
    let id = UUID()
    let name: String
    let data: GradientData
}

enum GradientPresets {
    static let all: [GradientPreset] = [
        GradientPreset(
            name: "Sunset",
            data: GradientData(
                colors: [.red, .orange, .yellow],
                locations: [0.0, 0.5, 1.0],
                type: .linear,
                linearStartPoint: .topLeading,
                linearEndPoint: .bottomTrailing,
                radialCenter: .center,
                radialRadius: 0.6
            )
        ),
        GradientPreset(
            name: "Ocean",
            data: GradientData(
                colors: [.blue, .teal],
                locations: [0.0, 1.0],
                type: .linear,
                linearStartPoint: .leading,
                linearEndPoint: .trailing,
                radialCenter: .center,
                radialRadius: 0.6
            )
        ),
        GradientPreset(
            name: "Forest",
            data: GradientData(
                colors: [.green, .teal],
                locations: [0.0, 1.0],
                type: .linear,
                linearStartPoint: .top,
                linearEndPoint: .bottom,
                radialCenter: .center,
                radialRadius: 0.6
            )
        ),
        GradientPreset(
            name: "Bubblegum",
            data: GradientData(
                colors: [.pink, .purple],
                locations: [0.0, 1.0],
                type: .linear,
                linearStartPoint: .leading,
                linearEndPoint: .trailing,
                radialCenter: .center,
                radialRadius: 0.6
            )
        ),
        GradientPreset(
            name: "Rainbow",
            data: GradientData(
                colors: [.red, .orange, .yellow, .green, .blue, .indigo, .purple],
                locations: [0.0, 0.16, 0.33, 0.5, 0.66, 0.83, 1.0],
                type: .linear,
                linearStartPoint: .leading,
                linearEndPoint: .trailing,
                radialCenter: .center,
                radialRadius: 0.6
            )
        ),
        GradientPreset(
            name: "Fire",
            data: GradientData(
                colors: [.yellow, .orange, .red],
                locations: [0.0, 0.6, 1.0],
                type: .angular,
                linearStartPoint: .center,
                linearEndPoint: .center,
                radialCenter: .center,
                radialRadius: 0.6
            )
        ),
        GradientPreset(
            name: "Midnight",
            data: GradientData(
                colors: [Color(red: 0.05, green: 0.08, blue: 0.2), .black],
                locations: [0.0, 1.0],
                type: .radial,
                linearStartPoint: .center,
                linearEndPoint: .center,
                radialCenter: .center,
                radialRadius: 0.7
            )
        ),
        GradientPreset(
            name: "Steel",
            data: GradientData(
                colors: [Color(white: 0.7), Color(white: 0.2)],
                locations: [0.0, 1.0],
                type: .linear,
                linearStartPoint: .topLeading,
                linearEndPoint: .bottomTrailing,
                radialCenter: .center,
                radialRadius: 0.6
            )
        )
    ]
}
