import Foundation

// OpenRouter APIのレスポンス形式に合わせたモデル定義
struct Model: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let description: String?
    let contextLength: Int?
    let pricing: Pricing?
    let topProvider: TopProvider?
    let architecture: Architecture?
    
    struct Pricing: Codable, Sendable {
        let prompt: String?
        let completion: String?
        let request: String?
        let image: String?
    }
    
    struct TopProvider: Codable, Sendable {
        let contextLength: Int?
        let maxCompletionTokens: Int?
        let isModerated: Bool?
    }
    
    struct Architecture: Codable, Sendable {
        let modality: String?
        let tokenizer: String?
        let instructType: String?
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case contextLength = "context_length"
        case pricing
        case topProvider = "top_provider"
        case architecture
    }
}

extension Model.Pricing {
    enum CodingKeys: String, CodingKey {
        case prompt
        case completion
        case request
        case image
    }
}

extension Model.TopProvider {
    enum CodingKeys: String, CodingKey {
        case contextLength = "context_length"
        case maxCompletionTokens = "max_completion_tokens"
        case isModerated = "is_moderated"
    }
}

extension Model.Architecture {
    enum CodingKeys: String, CodingKey {
        case modality
        case tokenizer
        case instructType = "instruct_type"
    }
}
