import Foundation
import os

struct GetCurrentTimeTool: NemoTool {
    var definition: ToolDefinition {
        ToolDefinition(
            type: "function",
            function: ToolFunction(
                name: "get_current_time",
                description: "Returns the current local date and time. Use this when the user asks what time or date it is, or when you need the precise current timestamp for a calculation. Do NOT use this just to confirm the date already provided in the system prompt.",
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
