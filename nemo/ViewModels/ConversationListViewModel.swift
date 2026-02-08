//
//  ConversationListViewModel.swift
//  nemo
//
//  Created by 林栄介 on 2026/02/08.
//

import Foundation
import SwiftUI
import SwiftData
import Combine

@MainActor
class ConversationListViewModel: ObservableObject {
    // MARK: - Navigation State
    
    @Published var selectedConversationId: UUID?
    @Published var showingSettings: Bool = false
    @Published var columnVisibility: NavigationSplitViewVisibility = .all
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Actions (Write)
    
    /// 新しい会話を作成してIDを返す
    func createNewConversation(in context: ModelContext) -> UUID {
        let conversationId = UUID()
        selectedConversationId = conversationId
        return conversationId
    }
    
    /// 指定された会話IDのメッセージを削除
    func deleteConversation(conversationId: UUID, in context: ModelContext, from conversations: [Conversation]) {
        let conversationsToDelete = conversations.filter { $0.conversationId == conversationId }
        for conversation in conversationsToDelete {
            context.delete(conversation)
        }
        if selectedConversationId == conversationId {
            selectedConversationId = nil
        }
    }
    
    /// IndexSetに基づいて複数の会話グループを削除
    func deleteConversations(at offsets: IndexSet, in context: ModelContext, from conversations: [Conversation]) {
        let titles = buildConversationTitles(from: conversations)
        for index in offsets {
            let conversationId = titles[index].0
            deleteConversation(conversationId: conversationId, in: context, from: conversations)
        }
    }
    
    // MARK: - Presentation Logic (Transform)
    
    /// conversationTitlesを生成（会話グループからタイトルと日付のリストを作成）
    func buildConversationTitles(from conversations: [Conversation]) -> [(UUID, String, Date)] {
        let conversationGroups = Dictionary(grouping: conversations, by: { $0.conversationId })
        
        return conversationGroups.map { conversationId, convs in
            let title = convs.first(where: { $0.role == "user" })?.content.prefix(30).description ?? "新しい会話"
            let date = convs.last?.timestamp ?? Date()
            return (conversationId, String(title), date)
        }.sorted { $0.2 > $1.2 }
    }
}
