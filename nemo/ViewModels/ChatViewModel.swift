//
//  ChatViewModel.swift
//  nemo
//
//  Created by 林栄介 on 2026/01/31.
//

import Foundation
import SwiftUI
import Combine
import SwiftData

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messageText = ""
    @Published var messages: [Conversation] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedModelId = ""
    
    private let service = OpenRouterService()
    private let selectedModelKey = "selected_model_id"
    private let model: ModelContext
    
    var conversationId: UUID
    
    init(conversationId: UUID, modelContext: ModelContext) {
        self.conversationId = conversationId
        self.model = modelContext
        loadMessages()
        loadSelectedModel()
    }
    
    func loadMessages() {
        let conversationId = self.conversationId
        let fetchDescriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate<Conversation> { conversation in
                conversation.conversationId == conversationId
            },
            sortBy: [SortDescriptor(\Conversation.timestamp)]
        )
        
        do {
            messages = try model.fetch(fetchDescriptor)
        } catch {
            print("Error loading messages: \(error)")
        }
    }
    
    func loadSelectedModel() {
        selectedModelId = UserDefaults.standard.string(forKey: selectedModelKey) ?? ""
    }
    
    func sendMessage() {
        guard !messageText.isEmpty else { return }
        guard !selectedModelId.isEmpty else {
            errorMessage = "モデルが選択されていません。設定からモデルを選択してください。"
            return
        }

        let userMessage = Conversation(
            role: "user",
            content: messageText,
            conversationId: conversationId
        )
        model.insert(userMessage)
        
        // Immediately update UI
        messages.append(userMessage)
        messageText = ""
        isLoading = true
        errorMessage = nil

        Task {
            // Use the messages array that has just been updated
            let messagesForAPI = self.messages.map { ["role": $0.role, "content": $0.content] }
            
            do {
                let responseText = try await service.sendMessage(messages: messagesForAPI, modelId: selectedModelId)
                
                let assistantMessage = Conversation(
                    role: "assistant",
                    content: responseText,
                    conversationId: self.conversationId
                )
                model.insert(assistantMessage)
                messages.append(assistantMessage)

            } catch {
                errorMessage = "AIへの送信に失敗しました: \(error.localizedDescription)"
            }
            
            isLoading = false
        }
    }
}