<<<<<<< HEAD
import Foundation
=======
>>>>>>> streaming
import Combine
import Foundation
import SwiftData
import SwiftUI

@MainActor
<<<<<<< HEAD
class ChatViewModel: ObservableObject {
=======
final class ChatViewModel: ObservableObject {
>>>>>>> streaming
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
<<<<<<< HEAD
=======

>>>>>>> streaming
    private var streamingTask: Task<Void, Never>?

    init(conversationId: UUID, modelContext: ModelContext) {
        self.conversationId = conversationId
        self.modelContext = modelContext
        loadMessages()
    }
<<<<<<< HEAD

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
=======

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
            id: UUID(),
            role: "user",
            content: trimmed,
            timestamp: Date(),
            conversationId: conversationId
>>>>>>> streaming
        )
        modelContext.insert(userMessage)
        try? modelContext.save()
        loadMessages()
        messageText = ""

        let messageHistory = messages.map { ["role": $0.role, "content": $0.content] }
<<<<<<< HEAD
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
=======

        // SettingsViewModel と同じキー "selected_model_id" を使用
        let modelId = UserDefaults.standard.string(forKey: "selected_model_id") ?? "meta-llama/llama-3.3-70b-instruct:free"

        isStreaming = true
        streamingContent = ""

        streamingTask = Task {
            defer {
                isStreaming = false
                streamingContent = ""
                streamingTask = nil
            }

            do {
                for try await chunk in openRouterService.sendMessageStream(
                    messages: messageHistory,
                    modelId: modelId
                ) {
                    guard !Task.isCancelled else { return }
                    streamingContent += chunk
                }

                guard !Task.isCancelled else { return }
                guard !streamingContent.isEmpty else { return }

                let assistantMessage = Conversation(
                    id: UUID(),
                    role: "assistant",
                    content: streamingContent,
                    timestamp: Date(),
                    conversationId: conversationId
                )
                modelContext.insert(assistantMessage)
                try? modelContext.save()
                loadMessages()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

>>>>>>> streaming
    func cancelStreaming() {
        streamingTask?.cancel()
        streamingTask = nil

        if !streamingContent.isEmpty {
            let assistantMessage = Conversation(
<<<<<<< HEAD
                id: UUID(), role: "assistant",
                content: streamingContent + " *(中断)*",
                timestamp: Date(), conversationId: conversationId
=======
                id: UUID(),
                role: "assistant",
                content: streamingContent + " *(中断)*",
                timestamp: Date(),
                conversationId: conversationId
>>>>>>> streaming
            )
            modelContext.insert(assistantMessage)
            try? modelContext.save()
            loadMessages()
        }

        isStreaming = false
        streamingContent = ""
    }
}
