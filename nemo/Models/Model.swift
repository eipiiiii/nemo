import Foundation

// 共通で使うモデル定義
struct Model: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let description: String?
    let contextLength: Int?
    let maxTokens: Int?
    let pricing: Pricing?
    
    struct Pricing: Codable, Sendable {
        let prompt: Double?
        let completion: Double?
    }
}
