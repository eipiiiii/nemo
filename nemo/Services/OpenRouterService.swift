import Foundation

nonisolated struct ModelsResponse: Codable, Sendable {
    let data: [Model]
}

nonisolated struct ChatRequest: Codable, Sendable {
    let model: String
    let messages: [[String: String]]
    let stream: Bool  // ← 追加
}

nonisolated struct ChatResponse: Codable, Sendable {
    struct Choice: Codable, Sendable {
        struct Message: Codable, Sendable {
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}

// SSE ストリーミング用デルタ構造体
nonisolated struct StreamDelta: Decodable, Sendable {
    struct Choice: Decodable, Sendable {
        struct Delta: Decodable, Sendable {
            let content: String?
        }
        let delta: Delta
        let finish_reason: String?
    }
    let choices: [Choice]
}

enum NetworkError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case noData
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "無効なレスポンスです"
        case .httpError(let c): return "HTTPエラー: \(c)"
        case .noData: return "データが受信されませんでした"
        case .decodingError(let e): return "データの解析に失敗しました: \(e.localizedDescription)"
        }
    }
}

final class OpenRouterService: Sendable {
    private let baseURL = "https://openrouter.ai/api/v1"
    private let apiKeyKey = "openrouter_api_key"
    private let customPromptKey = "custom_prompt"

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
            throw NSError(
                domain: "", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "APIキーが設定されていません"])
        }
        guard let url = URL(string: "\(baseURL)/models") else { throw NetworkError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NetworkError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw NetworkError.httpError(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(ModelsResponse.self, from: data).data
        } catch {
            throw NetworkError.decodingError(error)
        }
    }

    // 非ストリーミング版（後方互換のために残す）
    nonisolated func sendMessage(messages: [[String: String]], modelId: String) async throws
        -> String
    {
        let request = try buildRequest(messages: messages, modelId: modelId, stream: false)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NetworkError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw NetworkError.httpError(http.statusCode)
        }
        do {
            let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
            guard let content = chatResponse.choices.first?.message.content else {
                throw NetworkError.noData
            }
            return content
        } catch {
            throw NetworkError.decodingError(error)
        }
    }

    // ストリーミング版
    nonisolated func sendMessageStream(
        messages: [[String: String]],
        modelId: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let request = try self.buildRequest(
                        messages: messages, modelId: modelId, stream: true)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let http = response as? HTTPURLResponse else {
                        throw NetworkError.invalidResponse
                    }
                    guard (200...299).contains(http.statusCode) else {
                        throw NetworkError.httpError(http.statusCode)
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let json = String(line.dropFirst(6))
                        if json == "[DONE]" { break }
                        guard let data = json.data(using: .utf8) else { continue }
                        if let content = try? JSONDecoder().decode(StreamDelta.self, from: data)
                            .choices.first?.delta.content
                        {
                            continuation.yield(content)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private

    private nonisolated func buildRequest(
        messages: [[String: String]],
        modelId: String,
        stream: Bool
    ) throws -> URLRequest {
        guard let apiKey = UserDefaults.standard.string(forKey: apiKeyKey) else {
            throw NSError(
                domain: "", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "APIキーが設定されていません"])
        }
        let customPrompt = UserDefaults.standard.string(forKey: customPromptKey) ?? ""
        var finalPrompt = systemPrompt
        if !customPrompt.isEmpty { finalPrompt += "\n\n# Custom Instructions\n\(customPrompt)" }

        var allMessages = [["role": "system", "content": finalPrompt]]
        allMessages.append(contentsOf: messages)

        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw NetworkError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ChatRequest(model: modelId, messages: allMessages, stream: stream))
        return request
    }
}
