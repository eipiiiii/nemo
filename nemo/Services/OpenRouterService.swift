import Foundation
import Alamofire

// 通信専用の型定義
struct ModelsResponse: Codable, Sendable {
    let data: [Model]
}

struct ChatRequest: Codable, Sendable {
    let model: String
    let messages: [[String: String]]
}

struct ChatResponse: Codable, Sendable {
    struct Choice: Codable, Sendable {
        struct Message: Codable, Sendable {
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}

// サービスの定義
final class OpenRouterService: Sendable {
    private let baseURL = "https://openrouter.ai/api/v1"
    private let apiKeyKey = "openrouter_api_key"
    
    nonisolated func getModels() async throws -> [Model] {
        guard let apiKey = UserDefaults.standard.string(forKey: apiKeyKey) else {
            throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "APIキーが設定されていません"])
        }
        
        let url = "\(baseURL)/models"
        let headers: HTTPHeaders = [
            "Authorization": "Bearer \(apiKey)",
            "Content-Type": "application/json"
        ]
        
        // 手動でJSONをデコード
        return try await withCheckedThrowingContinuation { continuation in
            AF.request(url, headers: headers)
                .validate()
                .responseData(queue: .global()) { response in
                    switch response.result {
                    case .success(let data):
                        do {
                            let decoder = JSONDecoder()
                            let modelsResponse = try decoder.decode(ModelsResponse.self, from: data)
                            continuation.resume(returning: modelsResponse.data)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
        }
    }
    
    nonisolated func sendMessage(messages: [[String: String]], modelId: String) async throws -> String {
        guard let apiKey = UserDefaults.standard.string(forKey: apiKeyKey) else {
            throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "APIキーが設定されていません"])
        }
        
        let url = "\(baseURL)/chat/completions"
        let headers: HTTPHeaders = [
            "Authorization": "Bearer \(apiKey)",
            "Content-Type": "application/json"
        ]
        
        let requestBody = ChatRequest(model: modelId, messages: messages)
        
        // 手動でJSONをエンコード/デコード
        return try await withCheckedThrowingContinuation { continuation in
            do {
                let encoder = JSONEncoder()
                let jsonData = try encoder.encode(requestBody)
                
                var request = try URLRequest(url: url, method: .post, headers: headers)
                request.httpBody = jsonData
                
                AF.request(request)
                    .validate()
                    .responseData(queue: .global()) { response in
                        switch response.result {
                        case .success(let data):
                            do {
                                let decoder = JSONDecoder()
                                let chatResponse = try decoder.decode(ChatResponse.self, from: data)
                                if let content = chatResponse.choices.first?.message.content {
                                    continuation.resume(returning: content)
                                } else {
                                    continuation.resume(throwing: NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "無効なレスポンス"]))
                                }
                            } catch {
                                continuation.resume(throwing: error)
                            }
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
