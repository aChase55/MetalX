import SwiftUI

struct GradientPreview: View {
    let gradientData: GradientData
    
    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(gradientShape(in: geometry.size))
        }
    }
    
    private func gradientShape(in size: CGSize) -> AnyShapeStyle {
        let stops = zip(gradientData.colors, gradientData.locations).map { color, location in
            SwiftUI.Gradient.Stop(color: color, location: CGFloat(location))
        }
        
        let gradient = SwiftUI.Gradient(stops: stops)
        
        switch gradientData.type {
        case .linear:
            return AnyShapeStyle(LinearGradient(
                gradient: gradient,
                startPoint: gradientData.linearStartPoint,
                endPoint: gradientData.linearEndPoint
            ))
        case .radial:
            return AnyShapeStyle(RadialGradient(
                gradient: gradient,
                center: gradientData.radialCenter,
                startRadius: 0,
                endRadius: size.width * CGFloat(gradientData.radialRadius)
            ))
        case .angular:
            return AnyShapeStyle(AngularGradient(
                gradient: gradient,
                center: gradientData.radialCenter
            ))
        }
    }
}
