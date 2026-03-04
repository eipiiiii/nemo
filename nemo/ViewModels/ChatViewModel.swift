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
    @Published var selectedImages: [Data] = []

    @Published var streamingContent: String = ""
    @Published var isStreaming: Bool = false
    @Published var toolCallStatus: String? = nil

    /// maxToolRounds 到達時に true になる → View がバナーを表示
    @Published var awaitingContinuationChoice: Bool = false

    private let conversationId: UUID
    private let modelContext: ModelContext
    private let openRouterService = OpenRouterService()
    private let toolRegistry = ToolRegistry.shared
    private let keychain = KeychainService.shared
    private let apiKeyKeychainKey = "openrouter_api_key"

    /// 1セッションあたりの tool ラウンド上限
    private let maxToolRoundsPerSession = 5

    private var streamingTask: Task<Void, Never>?

    /// ユーザーの続行 or 終了の選択を待つ continuation
    private var continuationChoice: CheckedContinuation<Bool, Never>?

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

    // MARK: - ユーザーの続行選択

    /// View の「続行する」ボタンから呼ぶ
    func continueTool() {
        AppLogger.chat.info("▶️ continueTool: ユーザーが続行を選択")
        awaitingContinuationChoice = false
        continuationChoice?.resume(returning: true)
        continuationChoice = nil
    }

    /// View の「まとめて回答」ボタンから呼ぶ
    func finishTool() {
        AppLogger.chat.info("⏹️ finishTool: ユーザーが終了を選択")
        awaitingContinuationChoice = false
        continuationChoice?.resume(returning: false)
        continuationChoice = nil
    }

    // MARK: - Send

    func sendMessage() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!trimmed.isEmpty || !selectedImages.isEmpty), !isLoading, !isStreaming else {
            AppLogger.chat.warning("⚠️ sendMessage スキップ: empty=\(trimmed.isEmpty && self.selectedImages.isEmpty) loading=\(self.isLoading) streaming=\(self.isStreaming)")
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
            timestamp: Date(), conversationId: conversationId,
            imageData: selectedImages.isEmpty ? nil : selectedImages
        )
        modelContext.insert(userMessage)
        try? modelContext.save()
        loadMessages()
        messageText = ""
        selectedImages = []

        let historyMessages: [[String: Any]] = messages
            .filter { $0.role != "tool_use" }
            .map { msg in
                if let imageData = msg.imageData, !imageData.isEmpty {
                    var contentParts: [[String: Any]] = []
                    if !msg.content.isEmpty {
                        contentParts.append(["type": "text", "text": msg.content])
                    }
                    for data in imageData {
                        let base64 = data.base64EncodedString()
                        contentParts.append([
                            "type": "image_url",
                            "image_url": ["url": "data:image/jpeg;base64,\(base64)"]
                        ])
                    }
                    return ["role": msg.role, "content": contentParts]
                } else {
                    return ["role": msg.role, "content": msg.content]
                }
            }

        isStreaming = true
        streamingContent = ""
        toolCallStatus = nil
        awaitingContinuationChoice = false

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
                awaitingContinuationChoice = false
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
        var totalRounds = 0

        AppLogger.chat.info("🤖 runAgentLoop 開始: maxRoundsPerSession=\(self.maxToolRoundsPerSession) tools=\(tools.count)件")

        // ユーザーが「続行する」を選ぶ限りセッションを繰り返す
        while true {
            let sessionLimit = totalRounds + maxToolRoundsPerSession

            // 1セッション分のループ
            var sessionFinished = false
            while totalRounds < sessionLimit {
                guard !Task.isCancelled else {
                    AppLogger.chat.info("⏹️ runAgentLoop キャンセル: round=\(totalRounds)")
                    return
                }
                totalRounds += 1
                AppLogger.chat.info("🔄 ラウンド \(totalRounds) 開始: messages=\(messages.count)件")

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

                    // 中間テキストがあれば tool_use より先に DB 保存
                    if let content = assistantContent, !content.isEmpty {
                        let intermediateMsg = Conversation(
                            id: UUID(), role: "assistant", content: content,
                            timestamp: Date(), conversationId: conversationId
                        )
                        modelContext.insert(intermediateMsg)
                        try? modelContext.save()
                        loadMessages()
                        streamingContent = ""
                        AppLogger.chat.info("💾 中間 assistant メッセージ保存: \(content.count)文字")
                    }

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

                    for toolCall in toolCalls {
                        AppLogger.chat.info("🔧 tool call: \(toolCall.name) args=\(toolCall.arguments)")
                        await MainActor.run { toolCallStatus = "🔧 \(toolCall.name) 実行中..." }

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
                    AppLogger.chat.info("✅ ラウンド \(totalRounds): 最終回答完了 \(self.streamingContent.count)文字")
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
                    sessionFinished = true
                    return
                }
            }

            if sessionFinished { return }

            // セッション上限到達 → ユーザーに選択させる
            AppLogger.chat.warning("⚠️ \(totalRounds)ラウンド到達 → ユーザーに続行確認")
            await MainActor.run {
                toolCallStatus = nil
                awaitingContinuationChoice = true
            }

            // ユーザーの選択を待機（続行: true / 終了: false）
            let shouldContinue = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                self.continuationChoice = cont
            }

            if shouldContinue {
                // さらに maxToolRoundsPerSession ラウンド許可して while ループ継続
                AppLogger.chat.info("▶️ 続行: さらに\(self.maxToolRoundsPerSession)ラウンド追加")
                continue
            } else {
                // 強制終了: tool なし + まとめ指示メッセージ
                AppLogger.chat.info("⏹️ 終了: まとめ回答へ")
                messages.append([
                    "role": "user",
                    "content": """
                    FINAL ANSWER REQUIRED.

                    You have used all available tool calls. Now write your complete response as plain text only.

                    STRICT RULES - violating any of these is an error:
                    - Do NOT write <tool_call> tags
                    - Do NOT write JSON function calls
                    - Do NOT write any code blocks that represent tool invocations
                    - Do NOT say you need more information
                    - Do NOT ask to search again

                    Using ONLY the information already collected above, write your final answer now in natural language using Markdown.
                    """,
                ])
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
                AppLogger.chat.info("🤖 まとめ回答:\n\(self.streamingContent.prefix(200))")
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
        // 選択待ち中にキャンセルされた場合は continuation を終了で解決
        if awaitingContinuationChoice {
            continuationChoice?.resume(returning: false)
            continuationChoice = nil
            awaitingContinuationChoice = false
        }
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
