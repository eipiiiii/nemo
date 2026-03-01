import AppKit
import Foundation
import os

struct OpenURLTool: NemoTool {
    var definition: ToolDefinition {
        ToolDefinition(
            type: "function",
            function: ToolFunction(
                name: "open_url",
                description: "Opens a URL in the user's default browser. Use this only when the user explicitly asks to open or visit a specific webpage. Do NOT use this speculatively — only open a URL when the user has clearly requested it. Only https:// URLs are accepted.",
                parameters: ToolParameter(
                    type: "object",
                    properties: [
                        "url": ToolProperty(
                            type: "string",
                            description: "The URL to open. Must start with https://"
                        )
                    ],
                    required: ["url"]
                )
            )
        )
    }

    func execute(arguments: String) async -> String {
        guard
            let data = arguments.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let urlString = json["url"] as? String
        else {
            AppLogger.tool.error("❌ open_url: 引数解析失敗 args=\(arguments)")
            return "引数の解析に失敗しました"
        }

        // https:// のみ許可（セキュリティバリデーション）
        guard urlString.hasPrefix("https://"), let url = URL(string: urlString) else {
            AppLogger.tool.warning("⚠️ open_url: 無効な URL: \(urlString)")
            return "無効な URL です。https:// で始まる URL を指定してください。"
        }

        let opened = NSWorkspace.shared.open(url)
        if opened {
            AppLogger.tool.info("🌐 open_url: 開いた URL=\(urlString)")
            return "\(urlString) をブラウザで開きました。"
        } else {
            AppLogger.tool.warning("⚠️ open_url: 開けない URL: \(urlString)")
            return "URL を開けませんでした: \(urlString)"
        }
    }
}
