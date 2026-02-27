import Foundation
import OSLog

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

// ストリーミング用チャンク
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
        AppLogger.network.info("📡 getModels 開始")
        let request = try makeRequest(path: "/models", httpMethod: "GET", body: nil, apiKey: apiKey)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NetworkError.invalidResponse }
        AppLogger.network.info("📡 getModels ステータス: \(http.statusCode)")
        guard (200...299).contains(http.statusCode) else {
            let msg = decodeErrorMessage(data) ?? ""
            AppLogger.network.error("❌ getModels エラー: \(http.statusCode) \(msg)")
            throw NetworkError.httpError(http.statusCode, msg)
        }
        do {
            let models = try JSONDecoder().decode(ModelsResponse.self, from: data).data
            AppLogger.network.info("✅ getModels 完了: \(models.count) 件")
            return models
        } catch {
            AppLogger.network.error("❌ getModels デコード失敗: \(error)")
            throw NetworkError.decodingError(error)
        }
    }

    /// tool call ループ用: 非ストリーミング1ターン送信
    nonisolated func sendMessageWithTools(
        messages: [[String: Any]],
        modelId: String,
        tools: [ToolDefinition],
        apiKey: String
    ) async throws -> ChatResponse.Choice {
        AppLogger.network.info("📤 sendMessageWithTools 開始 model=\(modelId) messages=\(messages.count)件 tools=\(tools.count)件")

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

        AppLogger.network.info("📥 sendMessageWithTools ステータス: \(http.statusCode)")
        guard (200...299).contains(http.statusCode) else {
            let msg = decodeErrorMessage(data) ?? ""
            AppLogger.network.error("❌ sendMessageWithTools エラー: \(http.statusCode) \(msg)")
            throw NetworkError.httpError(http.statusCode, msg)
        }

        do {
            let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
            guard let choice = decoded.choices.first else { throw NetworkError.noData }
            let toolCallCount = choice.message.tool_calls?.count ?? 0
            AppLogger.network.info("✅ sendMessageWithTools 完了: finish_reason=\(choice.finish_reason ?? "nil") tool_calls=\(toolCallCount)件")
            return choice
        } catch {
            // デコード失敗時は生の JSON もログに出す
            let raw = String(data: data, encoding: .utf8) ?? "(binary)"
            AppLogger.network.error("❌ sendMessageWithTools デコード失敗: \(error)\nRaw: \(raw)")
            throw NetworkError.decodingError(error)
        }
    }

    // ストリーミング（最終回答用）
    nonisolated func sendMessageStream(
        messages: [[String: Any]],
        modelId: String,
        apiKey: String
    ) -> AsyncThrowingStream<String, Error> {
        AppLogger.streaming.info("🌊 sendMessageStream 開始 model=\(modelId) messages=\(messages.count)件")
        return AsyncThrowingStream { continuation in
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
                    AppLogger.streaming.info("🌊 SSE 接続: status=\(http.statusCode)")
                    guard (200...299).contains(http.statusCode) else {
                        var bodyText = ""
                        for try await line in bytes.lines { bodyText += line + "\n" }
                        let trimmed = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
                        AppLogger.streaming.error("❌ SSE エラー: \(http.statusCode) \(trimmed)")
                        throw NetworkError.httpError(http.statusCode, trimmed)
                    }

                    var chunkCount = 0
                    for try await line in bytes.lines {
                        if line.hasPrefix(":") || line.isEmpty { continue }
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" {
                            AppLogger.streaming.info("🌊 SSE [DONE] 受信 chunks=\(chunkCount)")
                            break
                        }
                        guard let data = payload.data(using: .utf8) else { continue }
                        if let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                            let delta = chunk.choices.first?.delta?.content,
                            !delta.isEmpty
                        {
                            chunkCount += 1
                            continuation.yield(delta)
                        }
                    }
                    AppLogger.streaming.info("✅ sendMessageStream 完了: 合計 \(chunkCount) chunks")
                    continuation.finish()
                } catch {
                    AppLogger.streaming.error("❌ sendMessageStream エラー: \(error)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private

    private nonisolated func makeRequest(
        path: String,
        httpMethod: String,
        body: [String: Any]?,
        apiKey: String
    ) throws -> URLRequest {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            AppLogger.network.error("❌ makeRequest: APIキーなし")
            throw NetworkError.missingAPIKey
        }
        guard let url = URL(string: "\(baseURL)\(path)") else {
            AppLogger.network.error("❌ makeRequest: 無効な URL: \(self.baseURL)\(path)")
            throw NetworkError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = httpMethod
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        AppLogger.network.debug("🔧 makeRequest: \(httpMethod) \(path) keyLen=\(trimmedKey.count)")
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
