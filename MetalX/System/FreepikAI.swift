import Foundation
import UIKit

public enum FreepikAIService {
    // Set this once from your app code (e.g., in App.onAppear)
    public static var apiKey: String = ""
    static let endpoint = URL(string: "https://api.freepik.com/v1/ai/text-to-image")!
    
    // Public to allow usage in default parameters
    public struct StyleSettings: Encodable {
        public let style: String
        public let color: String
        public let lighting: String
        public let framing: String
        
        public init(style: String, color: String, lighting: String, framing: String) {
            self.style = style
            self.color = color
            self.lighting = lighting
            self.framing = framing
        }
        
        public static let `default` = StyleSettings(
            style: "digital-art",
            color: "dramatic",
            lighting: "cinematic",
            framing: "portrait"
        )
    }
    
    struct ImageSettings: Encodable { let size: String }
    struct RequestBody: Encodable {
        let prompt: String
        let negative_prompt: String?
        let image: ImageSettings
        let styling: StyleSettings
    }
    
    struct Response: Decodable { let data: [ResponseData] }
    struct ResponseData: Decodable { let base64: String }
    
    public static func generate(
        prompt: String,
        negativePrompt: String? = nil,
        style: StyleSettings = .default,
        size: String = "square"
    ) async throws -> [UIImage] {
        guard !apiKey.isEmpty else {
            print("[FreepikAI] Missing API key. Set FreepikAIService.apiKey before calling generate().")
            throw NSError(domain: "FreepikAI", code: 401, userInfo: [NSLocalizedDescriptionKey: "Freepik API key not set"])
        }
        print("[FreepikAI] Generating images for prompt: \(prompt.prefix(120)))")
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-freepik-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let body = RequestBody(prompt: prompt, negative_prompt: negativePrompt, image: .init(size: size), styling: style)
        req.httpBody = try JSONEncoder().encode(body)
        let (data, respURL) = try await URLSession.shared.data(for: req)
        if let http = respURL as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let txt = String(data: data, encoding: .utf8) ?? "<no body>"
            print("[FreepikAI] HTTP \(http.statusCode): \(txt)")
            throw NSError(domain: "FreepikAI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Freepik HTTP \(http.statusCode)"])
        }
        let resp = try JSONDecoder().decode(Response.self, from: data)
        let images = resp.data.compactMap { Data(base64Encoded: $0.base64) }.compactMap { UIImage(data: $0) }
        print("[FreepikAI] Received \(images.count) image(s)")
        return images
    }
}
