import SwiftUI

struct CanvasEffectsView: View {
    @ObservedObject var canvas: Canvas
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom header
            HStack {
                Text("Canvas Effects")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Done") {
                    isPresented = false
                }
                .font(.body)
                .foregroundColor(.blue)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(UIColor.systemBackground))
            
            Divider()
            
            // Effects content
            ScrollView {
                EffectsControlView(effectStack: canvas.effectStack)
                    .padding()
            }
        }
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    CanvasEffectsView(canvas: Canvas(), isPresented: .constant(true))
}
