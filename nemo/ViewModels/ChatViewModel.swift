import Foundation
import Combine
import SwiftData
import SwiftUI

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [Conversation] = []
    @Published var messageText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    // ストリーミング用
    @Published var streamingContent: String = ""
    @Published var isStreaming: Bool = false

    private let conversationId: UUID
    private let modelContext: ModelContext
    private let openRouterService = OpenRouterService()
    private var streamingTask: Task<Void, Never>?

    init(conversationId: UUID, modelContext: ModelContext) {
        self.conversationId = conversationId
        self.modelContext = modelContext
        loadMessages()
    }

    func loadMessages() {
        let id = conversationId
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { $0.conversationId == id },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        messages = (try? modelContext.fetch(descriptor)) ?? []
    }

    func sendMessage() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isLoading, !isStreaming else { return }

        // ユーザーメッセージを保存
        let userMessage = Conversation(
            id: UUID(), role: "user", content: trimmed,
            timestamp: Date(), conversationId: conversationId
        )
        modelContext.insert(userMessage)
        try? modelContext.save()
        loadMessages()
        messageText = ""

        let messageHistory = messages.map { ["role": $0.role, "content": $0.content] }
        let modelId = UserDefaults.standard.string(forKey: "selected_model") ?? "openai/gpt-4o-mini"

        isStreaming = true
        streamingContent = ""

        streamingTask = Task {
            do {
                for try await chunk in openRouterService.sendMessageStream(
                    messages: messageHistory,
                    modelId: modelId
                ) {
                    guard !Task.isCancelled else { break }
                    streamingContent += chunk
                }

                // 完了後に SwiftData へ保存
                if !Task.isCancelled, !streamingContent.isEmpty {
                    let assistantMessage = Conversation(
                        id: UUID(), role: "assistant", content: streamingContent,
                        timestamp: Date(), conversationId: conversationId
                    )
                    modelContext.insert(assistantMessage)
                    try? modelContext.save()
                    loadMessages()
                }
            } catch {
                errorMessage = error.localizedDescription
            }

            isStreaming = false
            streamingContent = ""
            streamingTask = nil
        }
    }

    // ストリーミングを中断（途中テキストがあれば保存）
    func cancelStreaming() {
        streamingTask?.cancel()
        streamingTask = nil

        if !streamingContent.isEmpty {
            let assistantMessage = Conversation(
                id: UUID(), role: "assistant",
                content: streamingContent + " *(中断)*",
                timestamp: Date(), conversationId: conversationId
            )
            modelContext.insert(assistantMessage)
            try? modelContext.save()
            loadMessages()
        }

        isStreaming = false
        streamingContent = ""
    }
}
