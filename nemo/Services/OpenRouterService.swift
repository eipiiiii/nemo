import Foundation
import OSLog

// MARK: - Response Types

nonisolated struct ModelsResponse: Codable, Sendable {
    let data: [Model]
}

/// 非ストリーミングレスポンス（互換性のため残す）
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

nonisolated struct ToolCallResponse: Decodable, Sendable {
    struct Function: Decodable, Sendable {
        let name: String
        let arguments: String
    }
    let id: String
    let type: String?
    let function: Function
}

// MARK: - Streaming Types

/// ストリーミングチャンク（テキスト・ tool_calls 両方対応）
nonisolated struct StreamChunk: Decodable, Sendable {
    struct Choice: Decodable, Sendable {
        struct Delta: Decodable, Sendable {
            let role: String?
            let content: String?
            let tool_calls: [ToolCallDelta]?
        }
        let delta: Delta?
        let finish_reason: String?
    }
    let choices: [Choice]
}

/// tool_calls のデルタ（引数はチャンク分割して流れる）
nonisolated struct ToolCallDelta: Decodable, Sendable {
    struct Function: Decodable, Sendable {
        let name: String?
        let arguments: String?
    }
    let index: Int
    let id: String?
    let type: String?
    let function: Function?
}

/// ストリーミングから構築した完全な tool call
nonisolated struct AssembledToolCall: Sendable {
    let id: String
    let name: String
    let arguments: String
}

/// sendMessageStreamWithTools の1ラウンド結果
enum StreamRoundResult: Sendable {
    /// tool 呼び出しがある（実行して次ラウンドへ）
    case toolCalls([AssembledToolCall], assistantContent: String?)
    /// 最終回答（ストリーミングでUIに表示済み）
    case finished
}

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
        case .invalidResponse: return "無効なレスポンスです"
        case .httpError(let code, let detail):
            if let detail, !detail.isEmpty { return "HTTPエラー: \(code)\n\(detail)" }
            return "HTTPエラー: \(code)"
        case .noData: return "データが受信されませんでした"
        case .decodingError(let e): return "データの解析に失敗しました: \(e.localizedDescription)"
        case .missingAPIKey: return "APIキーが設定されていません"
        }
    }
}

// MARK: - Service

final class OpenRouterService: Sendable {
    private let baseURL = "https://openrouter.ai/api/v1"

    nonisolated func getModels(apiKey: String) async throws -> [Model] {
        AppLogger.network.info("📡 getModels 開始")
        let request = try makeRequest(path: "/models", httpMethod: "GET", body: nil, apiKey: apiKey)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NetworkError.invalidResponse }
        AppLogger.network.info("📡 getModels ステータス: \(http.statusCode)")
        guard (200...299).contains(http.statusCode) else {
            let msg = decodeErrorMessage(data) ?? ""
            throw NetworkError.httpError(http.statusCode, msg)
        }
        do {
            let models = try JSONDecoder().decode(ModelsResponse.self, from: data).data
            AppLogger.network.info("✅ getModels 完了: \(models.count) 件")
            return models
        } catch {
            throw NetworkError.decodingError(error)
        }
    }

    // MARK: - Streaming with tool_calls support

    /// 1ラウンドをストリーミングで実行。
    /// - tool 呼び出しがあれば .toolCalls を返す（API呈调引用は1回）。
    /// - 最終回答のテキストは onChunk コールバックでUIにその場で流す。
    nonisolated func sendRound(
        messages: [[String: Any]],
        modelId: String,
        tools: [ToolDefinition],
        apiKey: String,
        onChunk: @Sendable (String) async -> Void
    ) async throws -> StreamRoundResult {
        AppLogger.network.info("📤 sendRound 開始 model=\(modelId) messages=\(messages.count)件 tools=\(tools.count)件")

        var body: [String: Any] = [
            "model": modelId,
            "messages": messages,
            "stream": true,
        ]
        if !tools.isEmpty {
            let encoder = JSONEncoder()
            let toolsData = try encoder.encode(tools)
            let toolsJSON = try JSONSerialization.jsonObject(with: toolsData)
            body["tools"] = toolsJSON
            body["tool_choice"] = "auto"
        }

        let request = try makeRequest(path: "/chat/completions", httpMethod: "POST", body: body, apiKey: apiKey)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw NetworkError.invalidResponse }
        AppLogger.network.info("📥 sendRound SSE 接続: status=\(http.statusCode)")
        guard (200...299).contains(http.statusCode) else {
            var bodyText = ""
            for try await line in bytes.lines { bodyText += line + "\n" }
            throw NetworkError.httpError(http.statusCode, bodyText.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // チャンクを結合するバッファ
        // tool_calls: index ごとに id / name / arguments を結合
        var toolCallBuffers: [Int: (id: String, name: String, arguments: String)] = [:]
        var assistantContent: String = ""
        var finishReason: String? = nil
        var chunkCount = 0

        for try await line in bytes.lines {
            if line.hasPrefix(":") || line.isEmpty { continue }
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" {
                AppLogger.network.info("🏁 sendRound [DONE] chunks=\(chunkCount)")
                break
            }
            guard let data = payload.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                  let choice = chunk.choices.first else { continue }

            chunkCount += 1

            // finish_reason
            if let fr = choice.finish_reason { finishReason = fr }

            guard let delta = choice.delta else { continue }

            // テキストデルタ
            if let text = delta.content, !text.isEmpty {
                assistantContent += text
                await onChunk(text)
            }

            // tool_calls デルタ
            if let toolDeltas = delta.tool_calls {
                for td in toolDeltas {
                    let idx = td.index
                    var buf = toolCallBuffers[idx] ?? (id: "", name: "", arguments: "")
                    if let id = td.id, !id.isEmpty { buf.id = id }
                    if let name = td.function?.name, !name.isEmpty { buf.name += name }
                    if let args = td.function?.arguments { buf.arguments += args }
                    toolCallBuffers[idx] = buf
                }
            }
        }

        AppLogger.network.info("✅ sendRound 完了: finish_reason=\(finishReason ?? "nil") tool_calls=\(toolCallBuffers.count)件")

        // tool_calls があればアセンブルして返す
        if !toolCallBuffers.isEmpty {
            let assembled = toolCallBuffers
                .sorted { $0.key < $1.key }
                .map { AssembledToolCall(id: $0.value.id, name: $0.value.name, arguments: $0.value.arguments) }
            let names = assembled.map { $0.name }.joined(separator: ", ")
            AppLogger.network.info("🔧 tool_calls 検出: \(names)")
            return .toolCalls(assembled, assistantContent: assistantContent.isEmpty ? nil : assistantContent)
        }

        return .finished
    }

    // MARK: - Private

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
        AppLogger.network.debug("🔧 makeRequest: \(httpMethod) \(path) keyLen=\(trimmedKey.count)")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        }
        return request
    }

    private nonisolated func decodeErrorMessage(_ data: Data) -> String? {
        if let env = try? JSONDecoder().decode(ErrorEnvelope.self, from: data),
           let msg = env.error?.message { return msg }
        return String(data: data, encoding: .utf8)
    }
}
