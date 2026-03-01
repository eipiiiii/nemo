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

    // ストリーミング用
    @Published var streamingContent: String = ""
    @Published var isStreaming: Bool = false

    // tool 実行中の状態表示
    @Published var toolCallStatus: String? = nil

    private let conversationId: UUID
    private let modelContext: ModelContext
    private let openRouterService = OpenRouterService()
    private let toolRegistry = ToolRegistry.shared
    private let keychain = KeychainService.shared
    private let apiKeyKeychainKey = "openrouter_api_key"

    /// tool ループの最大ラウンド数（無限ループ防止）
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
            AppLogger.chat.error("❌ sendMessage: APIキーなし")
            errorMessage = "APIキーが設定されていません。設定画面から入力してください。"
            return
        }

        let modelId = UserDefaults.standard.string(forKey: "selected_model_id") ?? "meta-llama/llama-3.3-70b-instruct:free"
        AppLogger.chat.info("🚀 sendMessage 開始: model=\(modelId) text='\(trimmed.prefix(50))'")

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

        // API 送信用: tool_use ブロックは除外して user/assistant のみ使う
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
                // @MainActor クラス内だが非同期 Task の完了タイミングで
                // SwiftUI のビュー更新サイクル外に出る場合があるため
                // @Published 変更は必ず MainActor.run でラップする
                await MainActor.run { errorMessage = error.localizedDescription }
            }
            // defer を使わず、Task 完了後に明示的にリセット
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

            let choice = try await openRouterService.sendMessageWithTools(
                messages: messages,
                modelId: modelId,
                tools: tools,
                apiKey: apiKey
            )

            let finishReason = choice.finish_reason ?? "nil"
            let toolCallCount = choice.message.tool_calls?.count ?? 0
            AppLogger.chat.info("📨 ラウンド \(round + 1) 応答: finish_reason=\(finishReason) tool_calls=\(toolCallCount)件")

            // モデルのテキスト返答（thinking やツール呼び出し前のコメント）をログ出力
            if let assistantText = choice.message.content, !assistantText.isEmpty {
                AppLogger.chat.info("🤖 モデル応答 (content): \(assistantText)")
            }

            if let toolCalls = choice.message.tool_calls, !toolCalls.isEmpty {
                AppLogger.chat.info("🔧 tool_calls 検出: \(toolCalls.map { $0.function.name }.joined(separator: ", "))")

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

                for toolCall in toolCalls {
                    AppLogger.chat.info("🔧 tool call: \(toolCall.function.name) args=\(toolCall.function.arguments)")
                    await MainActor.run { toolCallStatus = "🔧 \(toolCall.function.name) 実行中..." }
                    AppLogger.tool.info("▶️ tool 実行: \(toolCall.function.name) id=\(toolCall.id)")

                    let result = await toolRegistry.execute(
                        toolCallId: toolCall.id,
                        name: toolCall.function.name,
                        arguments: toolCall.function.arguments
                    )
                    AppLogger.tool.info("✅ tool 結果: \(result.content)")

                    // SwiftData に tool_use ブロックとして保存
                    let toolBlock = Conversation(
                        id: UUID(),
                        role: "tool_use",
                        content: "",
                        timestamp: Date(),
                        conversationId: conversationId,
                        toolName: result.name,
                        toolResult: result.content
                    )
                    modelContext.insert(toolBlock)
                    try? modelContext.save()
                    loadMessages()

                    messages.append([
                        "role": "tool",
                        "tool_call_id": result.toolCallId,
                        "content": result.content,
                    ])
                }
                continue
            }

            // 最終回答: ストリーミング
            AppLogger.chat.info("🌊 ラウンド \(round + 1): toolなし → ストリーミング開始")
            await MainActor.run { toolCallStatus = nil }

            for try await chunk in openRouterService.sendMessageStream(
                messages: messages,
                modelId: modelId,
                apiKey: apiKey
            ) {
                guard !Task.isCancelled else { return }
                await MainActor.run { streamingContent += chunk }
            }

            guard !Task.isCancelled, !streamingContent.isEmpty else {
                AppLogger.chat.warning("⚠️ ストリーミング: キャンセル or 空")
                return
            }

            AppLogger.chat.info("✅ ストリーミング完了: \(self.streamingContent.count)文字")
            AppLogger.chat.info("🤖 モデル最終回答:\n\(self.streamingContent)")

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

        // maxToolRounds 到達時
        AppLogger.chat.warning("⚠️ maxToolRounds(\(self.maxToolRounds)) 到達 → ストリーミングで強制終了")
        await MainActor.run { toolCallStatus = nil }
        for try await chunk in openRouterService.sendMessageStream(
            messages: messages,
            modelId: modelId,
            apiKey: apiKey
        ) {
            guard !Task.isCancelled else { return }
            await MainActor.run { streamingContent += chunk }
        }
        guard !Task.isCancelled, !streamingContent.isEmpty else { return }

        AppLogger.chat.info("🤖 モデル最終回答 (maxRounds強制):\n\(self.streamingContent)")

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
            .map { $0.name }
            .sorted()
            .joined(separator: ", ")

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
                id: UUID(),
                role: "assistant",
                content: streamingContent + " *(中断)*",
                timestamp: Date(),
                conversationId: conversationId
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
