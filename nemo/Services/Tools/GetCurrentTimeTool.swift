import Foundation
import os

struct GetCurrentTimeTool: NemoTool {
    var definition: ToolDefinition {
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

    func execute(arguments: String) async -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年MM月dd日 HH:mm:ss (EEEE)"
        formatter.timeZone = TimeZone.current
        let result = formatter.string(from: Date())
        AppLogger.tool.info("🕒 get_current_time: \(result)")
        return result
    }
}
