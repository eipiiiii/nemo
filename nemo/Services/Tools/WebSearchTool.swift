import Foundation
import os

/// Web 検索 tool。SearXNG セルフホストのみ使用。
/// サーバー URL: UserDefaults "searxng_url" (default: http://localhost:8080)
struct WebSearchTool: NemoTool {
    var definition: ToolDefinition {
        ToolDefinition(
            type: "function",
            function: ToolFunction(
                name: "web_search",
                description: "Web 検索を行い、関連するページのタイトル・ URL ・スニペットを返します。最新情報や不明なことを調べるときに使ってください。",
                parameters: ToolParameter(
                    type: "object",
                    properties: [
                        "query": ToolProperty(
                            type: "string",
                            description: "検索クエリー"
                        )
                    ],
                    required: ["query"]
                )
            )
        )
    }

    func execute(arguments: String) async -> String {
        guard
            let data = arguments.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let query = json["query"] as? String, !query.isEmpty
        else {
            AppLogger.tool.error("❌ web_search: 引数解析失敗 args=\(arguments)")
            return "引数の解析に失敗しました。"
        }

        let baseUrl = UserDefaults.standard.string(forKey: "searxng_url") ?? "http://localhost:8080"
        AppLogger.tool.info("🔍 web_search: query='\(query)' url=\(baseUrl)")

        var components = URLComponents(string: "\(baseUrl)/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "language", value: "ja"),
        ]
        guard let url = components?.url else {
            return "URL の構築に失敗しました。"
        }

        do {
            var request = URLRequest(url: url, timeoutInterval: 10)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                AppLogger.tool.warning("⚠️ web_search: HTTP \(http.statusCode)")
                return "HTTP エラー: \(http.statusCode)。SearXNG が起動しているか確認してください。"
            }

            guard
                let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let results = jsonObj["results"] as? [[String: Any]],
                !results.isEmpty
            else {
                AppLogger.tool.warning("⚠️ web_search: 結果0件 query='\(query)'")
                return "「\(query)」の検索結果は見つかりませんでした。"
            }

            let formatted = results.prefix(5).enumerated().map { (i, item) -> String in
                let title = item["title"] as? String ?? "タイトルなし"
                let link = item["url"] as? String ?? ""
                let snippet = item["content"] as? String ?? ""
                return "\(i + 1). \(title)\n   URL: \(link)\n   \(snippet)"
            }.joined(separator: "\n\n")

            AppLogger.tool.info("✅ web_search 完了: \(results.count)件 query='\(query)'")
            return "検索結果 (\(min(results.count, 5))件)　クエリ: \(query)\n\n\(formatted)"
        } catch {
            AppLogger.tool.error("❌ web_search 失敗: \(error)")
            return "SearXNG に接続できませんでした。Docker が起動しているか確認してください。"
        }
    }
}
