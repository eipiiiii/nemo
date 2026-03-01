import Combine
import Foundation
import SwiftData
import SwiftUI
import os

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [Conversation] = []
    @Published var messageText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    @Published var streamingContent: String = ""
    @Published var isStreaming: Bool = false
    @Published var toolCallStatus: String? = nil

    private let conversationId: UUID
    private let modelContext: ModelContext
    private let openRouterService = OpenRouterService()
    private let toolRegistry = ToolRegistry.shared
    private let keychain = KeychainService.shared
    private let apiKeyKeychainKey = "openrouter_api_key"

    /// tool ループの最大ラウンド数
    private let maxToolRounds = 5

    private var streamingTask: Task<Void, Never>?

    init(conversationId: UUID, modelContext: ModelContext) {
        self.conversationId = conversationId
        self.modelContext = modelContext
        AppLogger.chat.info("💬 ChatViewModel init: conversationId=\(conversationId)")
        loadMessages()
    }

    func loadMessages() {
        let id = conversationId
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { $0.conversationId == id },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        messages = (try? modelContext.fetch(descriptor)) ?? []
        AppLogger.chat.debug("💬 loadMessages: \(self.messages.count)件")
    }

    func sendMessage() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isLoading, !isStreaming else {
            AppLogger.chat.warning("⚠️ sendMessage スキップ: empty=\(trimmed.isEmpty) loading=\(self.isLoading) streaming=\(self.isStreaming)")
            return
        }
        guard let apiKey = keychain.load(forKey: apiKeyKeychainKey), !apiKey.isEmpty else {
            errorMessage = "APIキーが設定されていません。設定画面から入力してください。"
            return
        }

        let modelId = UserDefaults.standard.string(forKey: "selected_model_id") ?? "meta-llama/llama-3.3-70b-instruct:free"
        AppLogger.chat.info("🚀 sendMessage 開始: model=\(modelId) text='\(trimmed.prefix(50))'")

        let userMessage = Conversation(
            id: UUID(), role: "user", content: trimmed,
            timestamp: Date(), conversationId: conversationId
        )
        modelContext.insert(userMessage)
        try? modelContext.save()
        loadMessages()
        messageText = ""

        let historyMessages: [[String: Any]] = messages
            .filter { $0.role != "tool_use" }
            .map { ["role": $0.role, "content": $0.content] }

        isStreaming = true
        streamingContent = ""
        toolCallStatus = nil

        streamingTask = Task {
            do {
                try await runAgentLoop(
                    initialMessages: historyMessages,
                    modelId: modelId,
                    apiKey: apiKey
                )
            } catch {
                AppLogger.chat.error("❌ sendMessage エラー: \(error)")
                await MainActor.run { errorMessage = error.localizedDescription }
            }
            await MainActor.run {
                isStreaming = false
                streamingContent = ""
                toolCallStatus = nil
                streamingTask = nil
                AppLogger.chat.info("🏁 sendMessage Task 終了")
            }
        }
    }

    // MARK: - Agent Loop

    private func runAgentLoop(
        initialMessages: [[String: Any]],
        modelId: String,
        apiKey: String
    ) async throws {
        var messages = buildMessagesWithSystemPrompt(initialMessages)
        let tools = toolRegistry.availableTools

        AppLogger.chat.info("🤖 runAgentLoop 開始: maxRounds=\(self.maxToolRounds) tools=\(tools.count)件")

        for round in 0 ..< maxToolRounds {
            guard !Task.isCancelled else {
                AppLogger.chat.info("⏹️ runAgentLoop キャンセル: round=\(round)")
                return
            }
            AppLogger.chat.info("🔄 ラウンド \(round + 1)/\(self.maxToolRounds) 開始: messages=\(messages.count)件")

            let result = try await openRouterService.sendRound(
                messages: messages,
                modelId: modelId,
                tools: tools,
                apiKey: apiKey
            ) { [weak self] chunk in
                guard let self else { return }
                await MainActor.run { self.streamingContent += chunk }
            }

            switch result {
            case .toolCalls(let toolCalls, let assistantContent):
                AppLogger.chat.info("🔧 tool_calls 検出: \(toolCalls.map { $0.name }.joined(separator: ", "))")

                // ① 中間テキストがあれば tool_use より先に DB 保存
                //    → timestamp 順で assistant が tool_use の上に来る
                if let content = assistantContent, !content.isEmpty {
                    let intermediateMsg = Conversation(
                        id: UUID(), role: "assistant", content: content,
                        timestamp: Date(), conversationId: conversationId
                    )
                    modelContext.insert(intermediateMsg)
                    try? modelContext.save()
                    loadMessages()
                    // UI のストリーミング表示はリセット（DB に永続化済み）
                    streamingContent = ""
                    AppLogger.chat.info("💾 中間 assistant メッセージ保存: \(content.count)文字")
                }

                // ② assistant メッセージをAPIコンテキストに追加
                var assistantMsg: [String: Any] = ["role": "assistant"]
                if let content = assistantContent { assistantMsg["content"] = content }
                assistantMsg["tool_calls"] = toolCalls.map { tc -> [String: Any] in
                    [
                        "id": tc.id,
                        "type": "function",
                        "function": ["name": tc.name, "arguments": tc.arguments] as [String: Any],
                    ]
                }
                messages.append(assistantMsg)

                // ③ tool を順番に実行・保存（timestamp が必ず assistant より後）
                for toolCall in toolCalls {
                    AppLogger.chat.info("🔧 tool call: \(toolCall.name) args=\(toolCall.arguments)")
                    await MainActor.run { toolCallStatus = "🔧 \(toolCall.name) 実行中..." }
                    AppLogger.tool.info("▶️ tool 実行: \(toolCall.name) id=\(toolCall.id)")

                    let toolResult = await toolRegistry.execute(
                        toolCallId: toolCall.id,
                        name: toolCall.name,
                        arguments: toolCall.arguments
                    )
                    AppLogger.tool.info("✅ tool 結果: \(toolResult.content)")

                    let toolBlock = Conversation(
                        id: UUID(), role: "tool_use", content: "",
                        timestamp: Date(), conversationId: conversationId,
                        toolName: toolResult.name, toolResult: toolResult.content
                    )
                    modelContext.insert(toolBlock)
                    try? modelContext.save()
                    loadMessages()

                    messages.append([
                        "role": "tool",
                        "tool_call_id": toolResult.toolCallId,
                        "content": toolResult.content,
                    ])
                }
                await MainActor.run { toolCallStatus = nil }

            case .finished:
                AppLogger.chat.info("✅ ラウンド \(round + 1): 最終回答完了 \(self.streamingContent.count)文字")
                AppLogger.chat.info("🤖 モデル最終回答:\n\(self.streamingContent)")

                guard !Task.isCancelled, !streamingContent.isEmpty else {
                    AppLogger.chat.warning("⚠️ ストリーミング: キャンセル or 空")
                    return
                }
                let assistantMessage = Conversation(
                    id: UUID(), role: "assistant", content: streamingContent,
                    timestamp: Date(), conversationId: conversationId
                )
                modelContext.insert(assistantMessage)
                try? modelContext.save()
                loadMessages()
                return
            }
        }

        // maxToolRounds 到達時: ストリーミングで強制終了
        AppLogger.chat.warning("⚠️ maxToolRounds(\(self.maxToolRounds)) 到達 → 強制終了")
        await MainActor.run { toolCallStatus = nil }
        let _ = try await openRouterService.sendRound(
            messages: messages,
            modelId: modelId,
            tools: [],
            apiKey: apiKey
        ) { [weak self] chunk in
            guard let self else { return }
            await MainActor.run { self.streamingContent += chunk }
        }
        guard !Task.isCancelled, !streamingContent.isEmpty else { return }
        AppLogger.chat.info("🤖 モデル最終回答 (maxRounds強制):\n\(self.streamingContent)")
        let assistantMessage = Conversation(
            id: UUID(), role: "assistant", content: streamingContent,
            timestamp: Date(), conversationId: conversationId
        )
        modelContext.insert(assistantMessage)
        try? modelContext.save()
        loadMessages()
    }

    // MARK: - System Prompt

    private func buildMessagesWithSystemPrompt(_ messages: [[String: Any]]) -> [[String: Any]] {
        let customPrompt = UserDefaults.standard.string(forKey: "custom_prompt") ?? ""
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm (EEEE)"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        let currentTimeString = formatter.string(from: Date())
        let tzName = TimeZone.current.identifier

        let toolGuidelines = toolRegistry.availableTools
            .sorted { $0.name < $1.name }
            .map { "- `\($0.name)`: \($0.function.description)" }
            .joined(separator: "\n")
        let toolNameList = toolRegistry.availableTools
            .map { $0.name }.sorted().joined(separator: ", ")

        var systemContent = """
            You are nemo, a helpful AI assistant running on macOS.

            <environment>
            Current time: \(currentTimeString)
            Timezone: \(tzName)
            </environment>

            # Core Principles
            - Be accurate, concise, and honest.
            - If you are unsure about something, say so rather than guessing.
            - For time-sensitive information (news, weather, prices, etc.), always use tools to get up-to-date data instead of relying on training knowledge.

            # Tools
            You have access to exactly these tools: \(toolNameList)

            **Tool usage guidelines:**
            \(toolGuidelines)

            **Rules that must always be followed:**
            - Only call tools listed above. Never call a tool that is not in the list above, even if you believe it exists.
            - If a tool call returns an error, do not retry the same call. Explain the problem to the user instead.
            - Do not call multiple tools in the same round unless they are fully independent.

            # Response Formatting
            Your responses are rendered with MarkdownUI. Use Markdown formatting effectively:
            - Use **bold** for emphasis on important points
            - Use `inline code` for variable names, commands, or short code snippets
            - Use fenced code blocks with language tags for multi-line code
            - Use ## headings to structure longer responses
            - Use bullet lists or numbered lists for multiple items
            - Use > blockquotes for important notes or warnings
            - Use tables when comparing multiple items
            """
        if !customPrompt.isEmpty {
            systemContent += "\n\n# Custom Instructions\n\(customPrompt)"
        }

        var all: [[String: Any]] = [["role": "system", "content": systemContent]]
        all.append(contentsOf: messages)
        AppLogger.chat.debug("📋 buildMessages: システムプロンプト追加後 \(all.count)件")
        return all
    }

    func cancelStreaming() {
        AppLogger.chat.info("⏹️ cancelStreaming")
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
            AppLogger.chat.info("⏹️ 中断メッセージ保存: \(self.streamingContent.count)文字")
        }
        isStreaming = false
        streamingContent = ""
        toolCallStatus = nil
    }
}
