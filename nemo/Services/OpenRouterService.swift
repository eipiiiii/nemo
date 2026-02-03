import Foundation
import Alamofire

// 通信専用の型定義（Model.swiftと重複しないようにここで定義）
struct ModelsResponse: Decodable, Sendable {
    let data: [Model]
}

struct ChatRequest: Encodable, Sendable {
    let model: String
    let messages: [[String: String]]
}

struct ChatResponse: Decodable, Sendable {
    struct Choice: Decodable, Sendable {
        struct Message: Decodable, Sendable {
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}

// サービスの定義（@MainActorは外す）
class OpenRouterService {
    private let baseURL = "https://openrouter.ai/api/v1"
    private let apiKeyKey = "openrouter_api_key"
    
    func getModels() async throws -> [Model] {
        guard let apiKey = UserDefaults.standard.string(forKey: apiKeyKey) else {
            throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "APIキーが設定されていません"])
        }
        
        let url = "\(baseURL)/models"
        let headers: HTTPHeaders = [
            "Authorization": "Bearer \(apiKey)",
            "Content-Type": "application/json"
        ]
        
        // 非同期リクエストの実行
        let response = try await AF.request(url, headers: headers)
            .validate()
            .serializingDecodable(ModelsResponse.self)
            .value
            
        return response.data
    }
    
    func sendMessage(messages: [[String: String]], modelId: String) async throws -> String {
        guard let apiKey = UserDefaults.standard.string(forKey: apiKeyKey) else {
            throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "APIキーが設定されていません"])
        }
        
        let url = "\(baseURL)/chat/completions"
        let headers: HTTPHeaders = [
            "Authorization": "Bearer \(apiKey)",
            "Content-Type": "application/json"
        ]
        
        let requestBody = ChatRequest(model: modelId, messages: messages)
        
        // 非同期リクエストの実行
        let response = try await AF.request(url, method: .post, parameters: requestBody, encoder: JSONParameterEncoder.default, headers: headers)
            .validate()
            .serializingDecodable(ChatResponse.self)
            .value
        
        guard let content = response.choices.first?.message.content else {
            throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "無効なレスポンス"])
        }
        
        return content
    }
}
