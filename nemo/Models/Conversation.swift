//
//  Conversation.swift
//  nemo
//
//  Created by 林栄介 on 2026/01/31.
//

import Foundation
import SwiftData

/// role の種類:
/// - "user"     : ユーザーのメッセージ
/// - "assistant": アシスタントの回答
/// - "tool_use" : tool 呼び出しブロック（toolName / toolResult を使用）
@Model
final class Conversation {
    var id: UUID
    var role: String
    var content: String
    var timestamp: Date
    var conversationId: UUID

    // tool_use ブロック専用フィールド（role == "tool_use" のときのみ使用）
    var toolName: String?
    var toolResult: String?

    init(
        id: UUID = UUID(),
        role: String,
        content: String,
        timestamp: Date = Date(),
        conversationId: UUID = UUID(),
        toolName: String? = nil,
        toolResult: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.conversationId = conversationId
        self.toolName = toolName
        self.toolResult = toolResult
    }
}
