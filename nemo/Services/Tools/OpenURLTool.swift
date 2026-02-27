import AppKit
import Foundation
import os

struct OpenURLTool: NemoTool {
    var definition: ToolDefinition {
        ToolDefinition(
            type: "function",
            function: ToolFunction(
                name: "open_url",
                description: "デフォルトブラウザで URL を開きます。ユーザーが特定の Web ページやドキュメントを開きたいときに使ってください。",
                parameters: ToolParameter(
                    type: "object",
                    properties: [
                        "url": ToolProperty(
                            type: "string",
                            description: "開く URL（https:// で始まる必要があります）"
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

        // NSWorkspace.shared.open は @MainActor 不要・macOS ネイティブ
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
