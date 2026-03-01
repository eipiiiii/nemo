import Foundation
import os

struct FetchPageTool: NemoTool {
    var definition: ToolDefinition {
        ToolDefinition(
            type: "function",
            function: ToolFunction(
                name: "fetch_page",
                description: "Fetches and returns the plain text content of a webpage at the given URL. Use this to read the full content of a specific page after finding its URL via web_search — for example, to summarize an article, extract details, or verify information. Only https:// URLs are accepted. The response is truncated to 4000 characters.",
                parameters: ToolParameter(
                    type: "object",
                    properties: [
                        "url": ToolProperty(
                            type: "string",
                            description: "The URL of the page to fetch. Must start with https://"
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
            let urlString = json["url"] as? String,
            urlString.hasPrefix("https://"),
            let url = URL(string: urlString)
        else {
            AppLogger.tool.error("❌ fetch_page: 引数解析失敗 args=\(arguments)")
            return "引数の解析に失敗しました。https:// で始まる URL を指定してください。"
        }

        AppLogger.tool.info("📋 fetch_page: \(urlString)")

        do {
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
                forHTTPHeaderField: "User-Agent"
            )
            let (data, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                AppLogger.tool.warning("⚠️ fetch_page: HTTP \(http.statusCode) url=\(urlString)")
                return "HTTP エラー: \(http.statusCode)"
            }

            let raw = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? ""

            let text = stripHTML(raw)
            let truncated = text.count > 4000
                ? String(text.prefix(4000)) + "\n...ページの内容が長いため先頭4000文字で打ち切りました。"
                : text

            AppLogger.tool.info("✅ fetch_page 完了: \(truncated.count)文字 url=\(urlString)")
            return truncated.isEmpty ? "ページのテキストを取得できませんでした。" : truncated
        } catch {
            AppLogger.tool.error("❌ fetch_page 失敗: \(error) url=\(urlString)")
            return "ページの取得に失敗しました: \(error.localizedDescription)"
        }
    }

    // MARK: - HTML タグ除去

    private func stripHTML(_ html: String) -> String {
        var text = html
            .replacingOccurrences(of: #"<script[\s\S]*?</script>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<style[\s\S]*?</style>"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " "),
            ("&mdash;", "—"), ("&ndash;", "–"), ("&hellip;", "…"),
        ]
        for (entity, char) in entities {
            text = text.replacingOccurrences(of: entity, with: char)
        }
        text = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return text
    }
}
