import Foundation

// 通信専用の型定義です
nonisolated struct ModelsResponse: Codable, Sendable {
    let data: [Model]
}

// 非ストリーミング用レスポンス（tool call 対応）
nonisolated struct ChatResponse: Decodable, Sendable {
    struct Choice: Decodable, Sendable {
        struct Message: Decodable, Sendable {
            let role: String?
            let content: String?
            let tool_calls: [ToolCallResponse]?
        }
        let message: Message
        let finish_reason: String?
    }
    let choices: [Choice]
}

// tool_calls レスポンス型
nonisolated struct ToolCallResponse: Decodable, Sendable {
    struct Function: Decodable, Sendable {
        let name: String
        let arguments: String
    }
    let id: String
    let type: String?
    let function: Function
}

// ストリーミング用チャンク（OpenAI互換: choices[0].delta.content）
nonisolated struct StreamChunk: Decodable, Sendable {
    struct Choice: Decodable, Sendable {
        struct Delta: Decodable, Sendable {
            let content: String?
        }
        let delta: Delta?
        let finish_reason: String?
    }
    let choices: [Choice]
}

// OpenRouter のエラー形式
nonisolated struct ErrorEnvelope: Decodable, Sendable {
    struct Inner: Decodable, Sendable {
        let message: String?
        let code: Int?
    }
    let error: Inner?
}

enum NetworkError: LocalizedError {
    case invalidResponse
    case httpError(Int, String?)
    case noData
    case decodingError(Error)
    case missingAPIKey

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "無効なレスポンスです"
        case .httpError(let code, let detail):
            if let detail, !detail.isEmpty {
                return "HTTPエラー: \(code)\n\(detail)"
            }
            return "HTTPエラー: \(code)"
        case .noData:
            return "データが受信されませんでした"
        case .decodingError(let e):
            return "データの解析に失敗しました: \(e.localizedDescription)"
        case .missingAPIKey:
            return "APIキーが設定されていません"
        }
    }
}

final class OpenRouterService: Sendable {
    private let baseURL = "https://openrouter.ai/api/v1"
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

    nonisolated func getModels(apiKey: String) async throws -> [Model] {
        let request = try makeRequest(path: "/models", httpMethod: "GET", body: nil, apiKey: apiKey)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NetworkError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw NetworkError.httpError(http.statusCode, decodeErrorMessage(data))
        }
        do {
            return try JSONDecoder().decode(ModelsResponse.self, from: data).data
        } catch {
            throw NetworkError.decodingError(error)
        }
    }

    /// tool call ループ用: 非ストリーミングで1ターン送信
    /// tool_calls があれば Choice を返し、最終回答なら content を返す
    nonisolated func sendMessageWithTools(
        messages: [[String: Any]],
        modelId: String,
        tools: [ToolDefinition],
        apiKey: String
    ) async throws -> ChatResponse.Choice {
        var body: [String: Any] = [
            "model": modelId,
            "messages": messages,
        ]
        if !tools.isEmpty {
            let encoder = JSONEncoder()
            let toolsData = try encoder.encode(tools)
            let toolsJSON = try JSONSerialization.jsonObject(with: toolsData)
            body["tools"] = toolsJSON
            body["tool_choice"] = "auto"
        }
        let request = try makeRequest(path: "/chat/completions", httpMethod: "POST", body: body, apiKey: apiKey)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NetworkError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw NetworkError.httpError(http.statusCode, decodeErrorMessage(data))
        }
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let choice = decoded.choices.first else { throw NetworkError.noData }
        return choice
    }

    // ストリーミング（最終回答用）
    nonisolated func sendMessageStream(
        messages: [[String: Any]],
        modelId: String,
        apiKey: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let body: [String: Any] = [
                        "model": modelId,
                        "messages": messages,
                        "stream": true,
                    ]
                    let request = try makeRequest(
                        path: "/chat/completions",
                        httpMethod: "POST",
                        body: body,
                        apiKey: apiKey
                    )

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw NetworkError.invalidResponse
                    }
                    guard (200...299).contains(http.statusCode) else {
                        var bodyText = ""
                        for try await line in bytes.lines { bodyText += line + "\n" }
                        throw NetworkError.httpError(
                            http.statusCode,
                            bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    }

                    for try await line in bytes.lines {
                        if line.hasPrefix(":") || line.isEmpty { continue }
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8) else { continue }
                        if let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                            let delta = chunk.choices.first?.delta?.content,
                            !delta.isEmpty
                        {
                            continuation.yield(delta)
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

    private nonisolated func buildMessagesWithSystemPrompt(messages: [[String: Any]])
        -> [[String: Any]]
    {
        let customPrompt = UserDefaults.standard.string(forKey: customPromptKey) ?? ""
        var finalSystemPrompt = systemPrompt
        if !customPrompt.isEmpty {
            finalSystemPrompt += "\n\n# Custom Instructions\n\(customPrompt)"
        }
        var all: [[String: Any]] = [["role": "system", "content": finalSystemPrompt]]
        all.append(contentsOf: messages)
        return all
    }

    private nonisolated func makeRequest(
        path: String,
        httpMethod: String,
        body: [String: Any]?,
        apiKey: String
    ) throws -> URLRequest {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw NetworkError.missingAPIKey }
        guard let url = URL(string: "\(baseURL)\(path)") else { throw NetworkError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = httpMethod
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        }
        return request
    }

    private nonisolated func decodeErrorMessage(_ data: Data) -> String? {
        if let env = try? JSONDecoder().decode(ErrorEnvelope.self, from: data),
            let msg = env.error?.message
        {
            return msg
        }
        return String(data: data, encoding: .utf8)
    }
}
