import Foundation

struct Sticker: Codable, Identifiable {
    let id: String
    let imageURL: String
    let previewURL: String
    let name: String
    let collections: String
    let tags: String
    let premium: Bool
    
    enum CodingKeys: String, CodingKey {
        case id = "StickerID"
        case imageURL = "image_url"
        case previewURL = "preview_url"
        case name
        case collections
        case tags
        case premium
    }
}

struct StickersResponse: Codable {
    let items: [Sticker]
    
    enum CodingKeys: String, CodingKey {
        case items = "Items"
    }
}