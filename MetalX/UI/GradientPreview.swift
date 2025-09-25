import SwiftUI

struct GradientPreview: View {
    let gradientData: GradientData
    
    var body: some View {
        GeometryReader { geometry in
            gradientFill(in: geometry.size)
        }
    }
    
    // Returning a concrete View avoids using AnyShapeStyle,
    // which is unavailable on older iOS 16 toolchains.
    @ViewBuilder
    private func gradientFill(in size: CGSize) -> some View {
        let stops = zip(gradientData.colors, gradientData.locations).map { color, location in
            SwiftUI.Gradient.Stop(color: color, location: CGFloat(location))
        }
        let gradient = SwiftUI.Gradient(stops: stops)
        
        switch gradientData.type {
        case .linear:
            Rectangle().fill(
                LinearGradient(
                    gradient: gradient,
                    startPoint: gradientData.linearStartPoint,
                    endPoint: gradientData.linearEndPoint
                )
            )
        case .radial:
            Rectangle().fill(
                RadialGradient(
                    gradient: gradient,
                    center: gradientData.radialCenter,
                    startRadius: 0,
                    endRadius: size.width * CGFloat(gradientData.radialRadius)
                )
            )
        case .angular:
            Rectangle().fill(
                AngularGradient(
                    gradient: gradient,
                    center: gradientData.radialCenter
                )
            )
        }
    }
}
