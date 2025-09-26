import SwiftUI

struct AssetPickerView: View {
    let canvas: Canvas
    @Binding var isPresented: Bool
    // Optional pre-supplied asset URLs (local or remote). When provided,
    // these are shown instead of fetching from the remote endpoint.
    let providedAssetURLs: [URL]?
    // Optional pre-supplied assets with display names.
    struct InputAsset { let url: URL; let name: String }
    let providedAssets: [InputAsset]?
    
    @State private var assets: [Asset] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedAsset: Asset?
    @State private var downloadingAssetId: String?
    
    struct Asset: Identifiable, Decodable {
        let id: String
        let name: String
        let image_url: String
        let preview_url: String
        let category: String
        let tags: String?
        let collections: String?
        let is_featured: Bool?
        let premium: Bool?
    }
    
    struct AssetsResponse: Decodable {
        let Items: [Asset]
        let Count: Int?
    }
    
    init(canvas: Canvas, isPresented: Binding<Bool>, providedAssetURLs: [URL]? = nil, providedAssets: [InputAsset]? = nil) {
        self.canvas = canvas
        self._isPresented = isPresented
        self.providedAssetURLs = providedAssetURLs
        self.providedAssets = providedAssets
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading assets...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text("Failed to load assets")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("Try Again") {
                            loadAssets()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 150), spacing: 16)
                        ], spacing: 16) {
                            ForEach(assets) { asset in
                                AssetItemView(
                                    asset: asset,
                                    isDownloading: downloadingAssetId == asset.id,
                                    onTap: {
                                        downloadAsset(asset)
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Assets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
        .onAppear {
            loadAssets()
        }
    }
    
    func loadAssets() {
        isLoading = true
        errorMessage = nil
        // Use provided named assets if available
        if let inputs = providedAssets, !inputs.isEmpty {
            self.assets = inputs.map { input in
                Asset(
                    id: input.url.absoluteString,
                    name: input.name,
                    image_url: input.url.absoluteString,
                    preview_url: input.url.absoluteString,
                    category: "Custom",
                    tags: nil,
                    collections: nil,
                    is_featured: nil,
                    premium: nil
                )
            }
            self.isLoading = false
            return
        }
        // Otherwise, use provided URLs if available
        if let urls = providedAssetURLs, !urls.isEmpty {
            self.assets = urls.map { url in
                Asset(
                    id: url.absoluteString,
                    name: displayName(for: url),
                    image_url: url.absoluteString,
                    preview_url: url.absoluteString,
                    category: "Custom",
                    tags: nil,
                    collections: nil,
                    is_featured: nil,
                    premium: nil
                )
            }
            self.isLoading = false
            return
        }

        guard let url = URL(string: "https://aojic0j0mk.execute-api.us-west-1.amazonaws.com/default/scrapbook_assets") else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let response = try JSONDecoder().decode(AssetsResponse.self, from: data)

                await MainActor.run {
                    self.assets = response.Items
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    private func displayName(for url: URL) -> String {
        // Prefer last path component, trimmed
        var name = url.deletingPathExtension().lastPathComponent
        if name.count > 24 {
            // Middle truncate
            let prefix = name.prefix(12)
            let suffix = name.suffix(8)
            name = String(prefix) + "…" + String(suffix)
        }
        return name
    }
    
    func downloadAsset(_ asset: Asset) {
        guard let url = URL(string: asset.image_url) else { return }

        downloadingAssetId = asset.id

        if url.isFileURL {
            // Load local file synchronously on background thread
            Task {
                do {
                    let data = try Data(contentsOf: url)
                    if let image = UIImage(data: data) {
                        await MainActor.run {
                            addAssetToCanvas(image: image, name: asset.name)
                            downloadingAssetId = nil
                            isPresented = false
                        }
                    } else {
                        await MainActor.run { downloadingAssetId = nil }
                    }
                } catch {
                    await MainActor.run { downloadingAssetId = nil }
                }
            }
        } else {
            Task {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    if let image = UIImage(data: data) {
                        await MainActor.run {
                            addAssetToCanvas(image: image, name: asset.name)
                            downloadingAssetId = nil
                            isPresented = false
                        }
                    } else {
                        await MainActor.run { downloadingAssetId = nil }
                    }
                } catch {
                    await MainActor.run {
                        downloadingAssetId = nil
                        // Could show an error alert here
                    }
                }
            }
        }
    }
    
    func addAssetToCanvas(image: UIImage, name: String) {
        let imageLayer = ImageLayer(image: image)
        imageLayer.name = name
        
        // Center in canvas
        imageLayer.transform.position = CGPoint(
            x: canvas.size.width / 2,
            y: canvas.size.height / 2
        )
        
        // Scale down if too large
        let maxSize: CGFloat = 300
        if image.size.width > maxSize || image.size.height > maxSize {
            let scale = min(maxSize / image.size.width, maxSize / image.size.height)
            imageLayer.transform.scale = scale
        }
        
        canvas.addLayer(imageLayer)
        canvas.selectLayer(imageLayer)
    }
}

struct AssetItemView: View {
    let asset: AssetPickerView.Asset
    let isDownloading: Bool
    let onTap: () -> Void
    
    @State private var thumbnailImage: UIImage?
    @State private var isLoadingThumbnail = true
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(UIColor.secondarySystemFill))
                        .aspectRatio(1, contentMode: .fit)
                    
                    if isLoadingThumbnail {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if let image = thumbnailImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                    }
                    
                    if isDownloading {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.5))
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                }
                
                Text(asset.name)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)
                
                if let tags = asset.tags, !tags.isEmpty {
                    Text(tags)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(UIColor.tertiarySystemFill))
                        .clipShape(Capsule())
                } else if !asset.category.isEmpty {
                    Text(asset.category)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(UIColor.tertiarySystemFill))
                        .clipShape(Capsule())
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isDownloading)
        .onAppear {
            loadThumbnail()
        }
    }
    
    func loadThumbnail() {
        guard let url = URL(string: asset.preview_url) else {
            isLoadingThumbnail = false
            return
        }

        if url.isFileURL {
            Task {
                do {
                    let data = try Data(contentsOf: url)
                    if let image = UIImage(data: data) {
                        await MainActor.run {
                            self.thumbnailImage = image
                            self.isLoadingThumbnail = false
                        }
                    } else {
                        await MainActor.run { self.isLoadingThumbnail = false }
                    }
                } catch {
                    await MainActor.run { self.isLoadingThumbnail = false }
                }
            }
        } else {
            Task {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    if let image = UIImage(data: data) {
                        await MainActor.run {
                            self.thumbnailImage = image
                            self.isLoadingThumbnail = false
                        }
                    } else {
                        await MainActor.run { self.isLoadingThumbnail = false }
                    }
                } catch {
                    await MainActor.run {
                        self.isLoadingThumbnail = false
                    }
                }
            }
        }
    }
}

#Preview {
    AssetPickerView(canvas: Canvas(), isPresented: .constant(true))
}
