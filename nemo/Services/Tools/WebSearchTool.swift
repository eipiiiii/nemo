import Foundation
import os

/// Web 検索 tool。
/// 優先度: SearXNG (localhost) → Google CSE → エラー
///
/// SearXNG 設定: UserDefaults "searxng_url" (default: http://localhost:8080)
/// Google CSE: Keychain "google_cse_api_key" + "google_cse_cx"
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

        // SearXNG を優先使用
        let searxngUrl = UserDefaults.standard.string(forKey: "searxng_url") ?? "http://localhost:8080"
        AppLogger.tool.info("🔍 web_search: query='\(query)' backend=SearXNG url=\(searxngUrl)")
        let result = await searchWithSearXNG(query: query, baseUrl: searxngUrl)
        if let result { return result }

        // SearXNG 失敗時は Google CSE にフォールバック
        AppLogger.tool.warning("⚠️ SearXNG 失敗、Google CSE にフォールバック")
        guard
            let apiKey = keychain.load(forKey: "google_cse_api_key"), !apiKey.isEmpty,
            let cx = keychain.load(forKey: "google_cse_cx"), !cx.isEmpty
        else {
            return "SearXNG に接続できませんでした。Docker が起動しているか確認してください。"
        }
        return await searchWithGoogleCSE(query: query, apiKey: apiKey, cx: cx)
    }

    // MARK: - SearXNG

    private func searchWithSearXNG(query: String, baseUrl: String) async -> String? {
        var components = URLComponents(string: "\(baseUrl)/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "language", value: "ja"),
        ]
        guard let url = components?.url else { return nil }

        do {
            var request = URLRequest(url: url, timeoutInterval: 10)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                AppLogger.tool.warning("⚠️ SearXNG HTTP \(http.statusCode)")
                return nil
            }

            guard
                let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let results = jsonObj["results"] as? [[String: Any]],
                !results.isEmpty
            else {
                AppLogger.tool.warning("⚠️ SearXNG: 結果0件 query='\(query)'")
                return "「\(query)」の検索結果は見つかりませんでした。"
            }

            let formatted = results.prefix(5).enumerated().map { (i, item) -> String in
                let title = item["title"] as? String ?? "タイトルなし"
                let link = item["url"] as? String ?? ""
                let snippet = item["content"] as? String ?? ""
                return "\(i + 1). \(title)\n   URL: \(link)\n   \(snippet)"
            }.joined(separator: "\n\n")

            AppLogger.tool.info("✅ SearXNG 完了: \(results.count)件 query='\(query)'")
            return "検索結果 (\(min(results.count, 5))件)　クエリ: \(query)\n\n\(formatted)"
        } catch {
            AppLogger.tool.error("❌ SearXNG 失敗: \(error)")
            return nil
        }
    }

    // MARK: - Google CSE （フォールバック）

    private func searchWithGoogleCSE(query: String, apiKey: String, cx: String) async -> String {
        var components = URLComponents(string: "https://www.googleapis.com/customsearch/v1")
        components?.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "cx", value: cx),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "num", value: "5"),
        ]
        guard let url = components?.url else { return "URLの構築に失敗しました。" }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return "HTTP エラー: \(http.statusCode)"
            }
            guard
                let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let items = jsonObj["items"] as? [[String: Any]]
            else { return "「\(query)」の検索結果は見つかりませんでした。" }

            let formatted = items.prefix(5).enumerated().map { (i, item) -> String in
                let title = item["title"] as? String ?? "タイトルなし"
                let link = item["link"] as? String ?? ""
                let snippet = item["snippet"] as? String ?? ""
                return "\(i + 1). \(title)\n   URL: \(link)\n   \(snippet)"
            }.joined(separator: "\n\n")

            AppLogger.tool.info("✅ Google CSE 完了: \(items.count)件")
            return "検索結果 [Google CSE] (\(items.count)件)　\(query)\n\n\(formatted)"
        } catch {
            return "検索に失敗しました: \(error.localizedDescription)"
        }
    }
}
