import Foundation
import os

/// Google Custom Search JSON API を使った Web 検索 tool。
/// APIキー: Keychain "google_cse_api_key"
/// 検索エンジンID (cx): Keychain "google_cse_cx"
struct WebSearchTool: NemoTool {
    private let keychain = KeychainService.shared

    var definition: ToolDefinition {
        ToolDefinition(
            type: "function",
            function: ToolFunction(
                name: "web_search",
                description: "Google で Web 検索を行い、関連するページのタイトル・ URL ・スニペットを返します。最新情報や不明なことを調べるときに使ってください。",
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

        guard
            let apiKey = keychain.load(forKey: "google_cse_api_key"), !apiKey.isEmpty,
            let cx = keychain.load(forKey: "google_cse_cx"), !cx.isEmpty
        else {
            AppLogger.tool.warning("⚠️ web_search: Google CSE の APIキーまたは CX が未設定")
            return "検索機能を使用するには、設定画面で Google CSE の APIキーと検索エンジンIDを設定してください。"
        }

        AppLogger.tool.info("🔍 web_search: query='\(query)'")

        var components = URLComponents(string: "https://www.googleapis.com/customsearch/v1")
        components?.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "cx", value: cx),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "num", value: "5"),
        ]

        guard let url = components?.url else {
            return "URLの構築に失敗しました。"
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? ""
                AppLogger.tool.error("❌ web_search: HTTP \(http.statusCode) body=\(body.prefix(200))")
                return "HTTP エラー: \(http.statusCode)"
            }

            guard
                let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let items = jsonObj["items"] as? [[String: Any]]
            else {
                AppLogger.tool.warning("⚠️ web_search: 検索結果0件 query='\(query)'")
                return "'\(query)' の検索結果は見つかりませんでした。"
            }

            let results = items.prefix(5).enumerated().map { (i, item) -> String in
                let title = item["title"] as? String ?? "タイトルなし"
                let link = item["link"] as? String ?? ""
                let snippet = item["snippet"] as? String ?? ""
                return "\(i + 1). \(title)\n   URL: \(link)\n   \(snippet)"
            }.joined(separator: "\n\n")

            AppLogger.tool.info("✅ web_search 完了: \(items.count)件 query='\(query)'")
            return "検索結果 (\(items.count)件)　クエリ: \(query)\n\n\(results)"
        } catch {
            AppLogger.tool.error("❌ web_search 失敗: \(error)")
            return "検索に失敗しました: \(error.localizedDescription)"
        }
    }
}
