import Foundation

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

// エラー定義
enum NetworkError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case noData
    case decodingError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "無効なレスポンスです"
        case .httpError(let code):
            return "HTTPエラー: \(code)"
        case .noData:
            return "データが受信されませんでした"
        case .decodingError(let error):
            return "データの解析に失敗しました: \(error.localizedDescription)"
        }
    }
}

// サービスの定義
final class OpenRouterService: Sendable {
    private let baseURL = "https://openrouter.ai/api/v1"
    private let apiKeyKey = "openrouter_api_key"
    private let customPromptKey = "custom_prompt"
    
    // 固定のシステムプロンプト（アプリ側で管理、ユーザーは編集不可）
    private let systemPrompt = """
    You are a helpful AI assistant.
    Provide accurate, concise, and well-structured responses.
    
    # Formatting Guidelines
    Your responses are rendered with MarkdownUI. Use Markdown formatting effectively:
    
    - Use **bold** for emphasis on important points
    - Use `inline code` for variable names, commands, or short code snippets
    - Use code blocks with language specification for multi-line code:
      ```swift
      let example = "code here"
      ```
    - Use headings (## Heading) to structure longer responses
    - Use bullet lists (-) or numbered lists (1.) for multiple items
    - Use > blockquotes for important notes or warnings
    - Use tables when comparing multiple items with different attributes
    - Use --- for horizontal rules to separate major sections if needed
    
    Always format your responses in Markdown to make them clear and easy to read.
    """
    
    nonisolated func getModels() async throws -> [Model] {
        guard let apiKey = UserDefaults.standard.string(forKey: apiKeyKey) else {
            throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "APIキーが設定されていません"])
        }
        
        guard let url = URL(string: "\(baseURL)/models") else {
            throw NetworkError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.httpError(httpResponse.statusCode)
        }
        
        do {
            let decoder = JSONDecoder()
            let modelsResponse = try decoder.decode(ModelsResponse.self, from: data)
            return modelsResponse.data
        } catch {
            throw NetworkError.decodingError(error)
        }
    }
    
    nonisolated func sendMessage(messages: [[String: String]], modelId: String) async throws -> String {
        guard let apiKey = UserDefaults.standard.string(forKey: apiKeyKey) else {
            throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "APIキーが設定されていません"])
        }
        
        // カスタムプロンプトを取得（ユーザーが編集可能）
        let customPrompt = UserDefaults.standard.string(forKey: customPromptKey) ?? ""
        
        // システムプロンプトとカスタムプロンプトを結合
        var finalSystemPrompt = systemPrompt
        if !customPrompt.isEmpty {
            finalSystemPrompt += "\n\n# Custom Instructions\n\(customPrompt)"
        }
        
        // システムプロンプトを先頭に追加
        var allMessages = [["role": "system", "content": finalSystemPrompt]]
        allMessages.append(contentsOf: messages)
        
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw NetworkError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = ChatRequest(model: modelId, messages: allMessages)
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.httpError(httpResponse.statusCode)
        }
        
        do {
            let decoder = JSONDecoder()
            let chatResponse = try decoder.decode(ChatResponse.self, from: data)
            
            guard let content = chatResponse.choices.first?.message.content else {
                throw NetworkError.noData
            }
            
            return content
        } catch {
            throw NetworkError.decodingError(error)
        }
    }
}
