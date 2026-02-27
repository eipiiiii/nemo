import Foundation

// MARK: - Tool 定義

struct ToolParameter: Encodable {
    let type: String
    let properties: [String: ToolProperty]
    let required: [String]
}

struct ToolProperty: Encodable {
    let type: String
    let description: String
}

struct ToolFunction: Encodable {
    let name: String
    let description: String
    let parameters: ToolParameter
}

struct ToolDefinition: Encodable {
    let type: String
    let function: ToolFunction
}

// MARK: - Tool 実行結果

struct ToolResult {
    let toolCallId: String
    let name: String
    let content: String
}

// MARK: - ToolService

final class ToolService {
    static let shared = ToolService()
    private init() {}

    /// 利用可能な tool の一覧
    var availableTools: [ToolDefinition] {
        [currentTimeTool, weatherTool]
    }

    // MARK: - Tool 定義

    private var currentTimeTool: ToolDefinition {
        ToolDefinition(
            type: "function",
            function: ToolFunction(
                name: "get_current_time",
                description: "現在の日時を返します。日時に関する質問に答えるときに使ってください。",
                parameters: ToolParameter(
                    type: "object",
                    properties: [:],
                    required: []
                )
            )
        )
    }

    private var weatherTool: ToolDefinition {
        ToolDefinition(
            type: "function",
            function: ToolFunction(
                name: "get_weather",
                description: "指定した都市の現在の天気を返します。",
                parameters: ToolParameter(
                    type: "object",
                    properties: [
                        "location": ToolProperty(
                            type: "string",
                            description: "都市名（例: Tokyo, New York）"
                        )
                    ],
                    required: ["location"]
                )
            )
        )
    }

    // MARK: - Tool 実行

    func execute(toolCallId: String, name: String, arguments: String) async -> ToolResult {
        let content: String
        switch name {
        case "get_current_time":
            content = executeGetCurrentTime()
        case "get_weather":
            content = executeGetWeather(arguments: arguments)
        default:
            content = "未知のツール: \(name)"
        }
        return ToolResult(toolCallId: toolCallId, name: name, content: content)
    }

    // MARK: - 各 Tool の実装

    private func executeGetCurrentTime() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年MM月dd日 HH:mm:ss (EEEE)"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: Date())
    }

    private func executeGetWeather(arguments: String) -> String {
        // スタブ実装: 実際の API 呼び出しに差し替え可能
        guard
            let data = arguments.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let location = json["location"] as? String
        else {
            return "引数の解析に失敗しました"
        }
        // TODO: 実際の天気 API に差し替える
        return "\(location) の天気: 晴れ、気温 20°C（スタブデータ）"
    }
}
