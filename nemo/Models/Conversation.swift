//
//  Conversation.swift
//  nemo
//
//  Created by 林栄介 on 2026/01/31.
//

import Foundation
import SwiftData

@Model
final class Conversation {
    var id: UUID
    var role: String // "user" or "assistant"
    var content: String
    var timestamp: Date
    var conversationId: UUID
    
    init(id: UUID = UUID(), role: String, content: String, timestamp: Date = Date(), conversationId: UUID = UUID()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.conversationId = conversationId
    }
}