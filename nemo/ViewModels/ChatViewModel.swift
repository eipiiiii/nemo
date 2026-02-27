import Combine
import Foundation
import SwiftData
import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [Conversation] = []
    @Published var messageText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    // ストリーミング用
    @Published var streamingContent: String = ""
    @Published var isStreaming: Bool = false

    // tool 実行中の状態表示
    @Published var toolCallStatus: String? = nil

    private let conversationId: UUID
    private let modelContext: ModelContext
    private let openRouterService = OpenRouterService()
    private let toolService = ToolService.shared
    private let keychain = KeychainService.shared
    private let apiKeyKeychainKey = "openrouter_api_key"

    /// tool ループの最大ラウンド数（無限ループ防止）
    private let maxToolRounds = 5

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

        guard let apiKey = keychain.load(forKey: apiKeyKeychainKey), !apiKey.isEmpty else {
            errorMessage = "APIキーが設定されていません。設定画面から入力してください。"
            return
        }

        // ユーザーメッセージを保存
        let userMessage = Conversation(
            id: UUID(),
            role: "user",
            content: trimmed,
            timestamp: Date(),
            conversationId: conversationId
        )
        modelContext.insert(userMessage)
        try? modelContext.save()
        loadMessages()
        messageText = ""

        let modelId = UserDefaults.standard.string(forKey: "selected_model_id") ?? "meta-llama/llama-3.3-70b-instruct:free"

        // 会話履歴を [[String: Any]] 形式で構築
        let historyMessages: [[String: Any]] = messages.map { ["role": $0.role, "content": $0.content] }

        isStreaming = true
        streamingContent = ""
        toolCallStatus = nil

        streamingTask = Task {
            defer {
                isStreaming = false
                streamingContent = ""
                toolCallStatus = nil
                streamingTask = nil
            }

            do {
                try await runAgentLoop(
                    initialMessages: historyMessages,
                    modelId: modelId,
                    apiKey: apiKey
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Agent Loop

    /// tool call ループ → 最終ストリーミング回答
    private func runAgentLoop(
        initialMessages: [[String: Any]],
        modelId: String,
        apiKey: String
    ) async throws {
        // system prompt を先頭に追加
        var messages = buildMessagesWithSystemPrompt(initialMessages)
        let tools = toolService.availableTools

        for round in 0 ..< maxToolRounds {
            guard !Task.isCancelled else { return }

            // 非ストリーミングで1ターン送信
            let choice = try await openRouterService.sendMessageWithTools(
                messages: messages,
                modelId: modelId,
                tools: tools,
                apiKey: apiKey
            )

            // tool_calls があれば実行してループ継続
            if let toolCalls = choice.message.tool_calls, !toolCalls.isEmpty {
                // assistant の tool_calls メッセージをコンテキストに追加
                var assistantMsg: [String: Any] = ["role": "assistant"]
                if let content = choice.message.content { assistantMsg["content"] = content }
                let toolCallsJSON = toolCalls.map { tc -> [String: Any] in
                    [
                        "id": tc.id,
                        "type": "function",
                        "function": [
                            "name": tc.function.name,
                            "arguments": tc.function.arguments,
                        ] as [String: Any],
                    ]
                }
                assistantMsg["tool_calls"] = toolCallsJSON
                messages.append(assistantMsg)

                // 各 tool を実行して結果をコンテキストに追加
                for toolCall in toolCalls {
                    toolCallStatus = "🔧 \(toolCall.function.name) 実行中..."
                    let result = await toolService.execute(
                        toolCallId: toolCall.id,
                        name: toolCall.function.name,
                        arguments: toolCall.function.arguments
                    )
                    messages.append([
                        "role": "tool",
                        "tool_call_id": result.toolCallId,
                        "content": result.content,
                    ])
                }
                // 次ラウンドへ
                continue
            }

            // tool_calls がない = 最終回答
            // ここまでのコンテキストでストリーミング回答
            toolCallStatus = nil
            _ = round // suppress unused warning

            for try await chunk in openRouterService.sendMessageStream(
                messages: messages,
                modelId: modelId,
                apiKey: apiKey
            ) {
                guard !Task.isCancelled else { return }
                streamingContent += chunk
            }

            guard !Task.isCancelled, !streamingContent.isEmpty else { return }

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
            return
        }

        // maxToolRounds に達した場合はそのまま最終ストリーミング
        toolCallStatus = nil
        for try await chunk in openRouterService.sendMessageStream(
            messages: messages,
            modelId: modelId,
            apiKey: apiKey
        ) {
            guard !Task.isCancelled else { return }
            streamingContent += chunk
        }
        guard !Task.isCancelled, !streamingContent.isEmpty else { return }
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
    }

    // MARK: - Private

    private func buildMessagesWithSystemPrompt(_ messages: [[String: Any]]) -> [[String: Any]] {
        let customPrompt = UserDefaults.standard.string(forKey: "custom_prompt") ?? ""
        var systemContent = """
            You are a helpful AI assistant.
            Provide accurate, concise, and well-structured responses.

            # Formatting Guidelines
            Your responses are rendered with MarkdownUI. Use Markdown formatting effectively:

            - Use **bold** for emphasis on important points
            - Use `inline code` for variable names, commands, or short code snippets
            - Use code blocks with language specification for multi-line code
            - Use headings (## Heading) to structure longer responses
            - Use bullet lists (-) or numbered lists (1.) for multiple items
            - Use > blockquotes for important notes or warnings
            - Use tables when comparing multiple items with different attributes

            Always format your responses in Markdown to make them clear and easy to read.
            """
        if !customPrompt.isEmpty {
            systemContent += "\n\n# Custom Instructions\n\(customPrompt)"
        }
        var all: [[String: Any]] = [["role": "system", "content": systemContent]]
        all.append(contentsOf: messages)
        return all
    }

    func cancelStreaming() {
        streamingTask?.cancel()
        streamingTask = nil

        if !streamingContent.isEmpty {
            let assistantMessage = Conversation(
                id: UUID(),
                role: "assistant",
                content: streamingContent + " *(中断)*",
                timestamp: Date(),
                conversationId: conversationId
            )
            modelContext.insert(assistantMessage)
            try? modelContext.save()
            loadMessages()
        }

        isStreaming = false
        streamingContent = ""
        toolCallStatus = nil
    }
}
