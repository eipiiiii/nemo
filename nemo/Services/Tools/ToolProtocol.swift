import Foundation

// MARK: - Tool 実行結果

struct ToolResult {
    let toolCallId: String
    let name: String
    let content: String
}

// MARK: - Tool 共通インターフェース

/// 各 tool が準拡するプロトコル。
/// `definition` は OpenRouter に渡す JSON、`execute` は実際の処理。
protocol NemoTool: Sendable {
    /// OpenRouter 向け tool 定義
    var definition: ToolDefinition { get }

    /// 引数 JSON を受け取り結果文字列を返す
    func execute(arguments: String) async -> String
}

// MARK: - 共通型定義

struct ToolParameter: Encodable {
    let type: String
    let properties: [String: ToolProperty]
    let required: [String]
}

struct ToolProperty: Encodable {
    let type: String
    let description: String
}

struct ToolFunction: Encodable {
    let name: String
    let description: String
    let parameters: ToolParameter
}

struct ToolDefinition: Encodable {
    let type: String
    let function: ToolFunction

    /// tool 名のショートカット
    var name: String { function.name }
}
