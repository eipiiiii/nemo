import Foundation
import os

/// 全 tool を登録・ dispatch するレジストリ。
/// 新しい tool を追加するときはこのリストに1行追加するだけでよい。
final class ToolRegistry: @unchecked Sendable {
    static let shared: ToolRegistry = {
        ToolRegistry(tools: [
            GetCurrentTimeTool(),
            GetWeatherTool(),
            OpenURLTool(),
            FetchPageTool(),
            WebSearchTool(),
        ])
    }()

    private let tools: [String: any NemoTool]

    init(tools: [any NemoTool]) {
        self.tools = Dictionary(
            uniqueKeysWithValues: tools.map { ($0.definition.name, $0) }
        )
        AppLogger.tool.info("🛠 ToolRegistry 初期化: \(tools.map { $0.definition.name }.joined(separator: ", "))")
    }

    /// OpenRouter 向けの tool 定義一覧
    var availableTools: [ToolDefinition] {
        Array(tools.values).map { $0.definition }
    }

    /// tool 名に対応する tool を dispatch して実行
    func execute(toolCallId: String, name: String, arguments: String) async -> ToolResult {
        AppLogger.tool.info("▶️ ToolRegistry.execute: name=\(name) id=\(toolCallId)")
        guard let tool = tools[name] else {
            AppLogger.tool.warning("⚠️ 未知の tool: \(name)")
            return ToolResult(toolCallId: toolCallId, name: name, content: "未知のツール: \(name)")
        }
        let content = await tool.execute(arguments: arguments)
        AppLogger.tool.info("✅ ToolRegistry.execute 完了: name=\(name) result=\(content.prefix(100))")
        return ToolResult(toolCallId: toolCallId, name: name, content: content)
    }
}
