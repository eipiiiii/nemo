import Foundation
import os

struct GetWeatherTool: NemoTool {
    var definition: ToolDefinition {
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

    func execute(arguments: String) async -> String {
        guard
            let data = arguments.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let location = json["location"] as? String
        else {
            AppLogger.tool.error("❌ get_weather: 引数解析失敗 args=\(arguments)")
            return "引数の解析に失敗しました"
        }
        AppLogger.tool.info("☁️ get_weather: location=\(location)")
        // TODO: 実際の天気 API に差し替える
        return "\(location) の天気: 晴れ、気温 20°C（スタブデータ）"
    }
}
