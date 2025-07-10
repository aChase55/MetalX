import SwiftUI
import Metal
import MetalKit

struct StickerPickerView: View {
    @ObservedObject var canvas: Canvas
    @Binding var isPresented: Bool
    
    @State private var stickers: [Sticker] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var imageCache: [String: UIImage] = [:]
    
    let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 12)
    ]
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading stickers...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.orange)
                        Text("Error loading stickers")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try Again") {
                            Task {
                                await loadStickers()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(stickers) { sticker in
                                StickerCell(
                                    sticker: sticker,
                                    imageCache: $imageCache,
                                    onTap: {
                                        addStickerToCanvas(sticker)
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Stickers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
        .task {
            await loadStickers()
        }
    }
    
    private func loadStickers() async {
        isLoading = true
        errorMessage = nil
        
        do {
            guard let url = URL(string: "https://2tcx969uh2.execute-api.us-west-1.amazonaws.com/default/fetch_stickers") else {
                throw URLError(.badURL)
            }
            
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(StickersResponse.self, from: data)
            
            await MainActor.run {
                self.stickers = response.items
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    private func addStickerToCanvas(_ sticker: Sticker) {
        // Check if we have the image cached
        if let cachedImage = imageCache[sticker.id] {
            addImageToCanvas(cachedImage, name: sticker.name)
        } else {
            // Download the image first
            Task {
                if let image = await downloadImage(from: sticker.imageURL) {
                    await MainActor.run {
                        imageCache[sticker.id] = image
                        addImageToCanvas(image, name: sticker.name)
                    }
                }
            }
        }
    }
    
    private func downloadImage(from urlString: String) async -> UIImage? {
        guard let url = URL(string: urlString) else { return nil }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data)
        } catch {
            print("Failed to download image: \(error)")
            return nil
        }
    }
    
    private func addImageToCanvas(_ image: UIImage, name: String) {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        
        let textureLoader = MTKTextureLoader(device: device)
        let options: [MTKTextureLoader.Option: Any] = [
            .generateMipmaps: false,
            .SRGB: false
        ]
        
        do {
            let texture = try textureLoader.newTexture(cgImage: image.cgImage!, options: options)
            
            let imageLayer = ImageLayer()
            imageLayer.texture = texture
            imageLayer.name = name
            imageLayer.bounds = CGRect(origin: .zero, size: image.size)
            
            // Center in canvas
            imageLayer.transform.position = CGPoint(
                x: canvas.size.width / 2,
                y: canvas.size.height / 2
            )
            
            // Scale to fit if needed
            let maxDimension: CGFloat = 400
            if image.size.width > maxDimension || image.size.height > maxDimension {
                let scale = min(maxDimension / image.size.width, maxDimension / image.size.height)
                imageLayer.transform.scale = scale
            }
            
            canvas.addLayer(imageLayer)
            canvas.selectLayer(imageLayer)
            
            // Dismiss the picker
            isPresented = false
        } catch {
            print("Failed to create texture: \(error)")
        }
    }
}

struct StickerCell: View {
    let sticker: Sticker
    @Binding var imageCache: [String: UIImage]
    let onTap: () -> Void
    
    @State private var image: UIImage?
    @State private var isLoading = true
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(UIColor.secondarySystemBackground))
                    .aspectRatio(1, contentMode: .fit)
                
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(8)
                } else if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "photo")
                        .foregroundColor(.secondary)
                        .font(.title2)
                }
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        // Check cache first
        if let cachedImage = imageCache[sticker.id] {
            self.image = cachedImage
            self.isLoading = false
            return
        }
        
        // Download image (use preview URL for faster loading in grid)
        Task {
            guard let url = URL(string: sticker.previewURL) else { return }
            
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let downloadedImage = UIImage(data: data) {
                    await MainActor.run {
                        self.image = downloadedImage
                        self.imageCache[sticker.id] = downloadedImage
                        self.isLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
}

#Preview {
    StickerPickerView(canvas: Canvas(), isPresented: .constant(true))
}