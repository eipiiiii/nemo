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
    @Published var awaitingContinuationChoice: Bool = false

    private let conversationId: UUID
    private let modelContext: ModelContext
    private let keychain = KeychainService.shared
    private let apiKeyKeychainKey = "openrouter_api_key"
    
    /// LangGraph エージェントサーバーのベース URL
    private let agentBaseURL = "http://localhost:8000"

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

    // MARK: - Send

    func sendMessage() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!trimmed.isEmpty || !selectedImages.isEmpty), !isLoading, !isStreaming else {
            AppLogger.chat.warning("⚠️ sendMessage スキップ: empty=\(trimmed.isEmpty && self.selectedImages.isEmpty) loading=\(self.isLoading) streaming=\(self.isStreaming)")
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

        // 会話履歴を LangGraph 形式に変換 (tool_use は除外)
        let historyMessages = messages
            .filter { $0.role != "tool_use" }
            .map { msg -> [String: Any] in
                // 画像対応は現時点ではスキップ（LangGraph 側で対応が必要）
                return ["role": msg.role, "content": msg.content]
            }

        isStreaming = true
        streamingContent = ""
        toolCallStatus = nil
        awaitingContinuationChoice = false

        streamingTask = Task {
            do {
                try await streamAgentResponse(
                    messages: historyMessages,
                    modelId: modelId
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

    // MARK: - LangGraph Agent Streaming

    private func streamAgentResponse(
        messages: [[String: Any]],
        modelId: String
    ) async throws {
        guard let url = URL(string: "\(agentBaseURL)/agent/stream") else {
            throw NSError(domain: "ChatViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid agent URL"])
        }

        let customPrompt = UserDefaults.standard.string(forKey: "custom_prompt") ?? ""
        let requestBody: [String: Any] = [
            "messages": messages,
            "model": modelId,
            "custom_instructions": customPrompt
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 300 // 5分

        AppLogger.chat.info("📡 LangGraph agent stream 開始: \(url)")

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "ChatViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
        }

        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "ChatViewModel", code: httpResponse.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"])
        }

        var currentText = ""
        var currentToolName: String? = nil
        var currentToolInput: String? = nil
        var currentToolOutput: String? = nil

        for try await line in asyncBytes.lines {
            guard !Task.isCancelled else {
                AppLogger.chat.info("⏹️ streamAgentResponse キャンセル")
                return
            }

            guard line.hasPrefix("data: ") else { continue }
            let jsonString = line.dropFirst(6)
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let eventType = json["type"] as? String ?? ""

            switch eventType {
            case "text_chunk":
                if let chunk = json["content"] as? String {
                    currentText += chunk
                    await MainActor.run {
                        streamingContent += chunk
                    }
                }

            case "tool_call":
                let toolName = json["tool_name"] as? String ?? "unknown"
                let toolInput = json["tool_input"] as? String ?? "{}"
                currentToolName = toolName
                currentToolInput = toolInput
                AppLogger.chat.info("🔧 tool_call: \(toolName)")
                await MainActor.run {
                    toolCallStatus = "🔧 \(toolName) 実行中..."
                }

            case "tool_result":
                if let toolOutput = json["tool_output"] as? String {
                    currentToolOutput = toolOutput
                    AppLogger.chat.info("✅ tool_result: \(toolOutput.prefix(100))")
                    
                    // tool_use メッセージを DB に保存
                    if let toolName = currentToolName {
                        let toolBlock = Conversation(
                            id: UUID(), role: "tool_use", content: "",
                            timestamp: Date(), conversationId: conversationId,
                            toolName: toolName, toolResult: toolOutput
                        )
                        modelContext.insert(toolBlock)
                        try? modelContext.save()
                        loadMessages()
                    }
                    
                    await MainActor.run {
                        toolCallStatus = nil
                    }
                }

            case "error":
                let errorMsg = json["message"] as? String ?? "Unknown error"
                AppLogger.chat.error("❌ Agent error: \(errorMsg)")
                await MainActor.run {
                    errorMessage = errorMsg
                }

            case "end":
                AppLogger.chat.info("🏁 Agent stream 終了")
                break

            default:
                break
            }
        }

        // 最終的な assistant メッセージを保存
        guard !Task.isCancelled, !currentText.isEmpty else {
            AppLogger.chat.warning("⚠️ ストリーミング: キャンセル or 空")
            return
        }

        let assistantMessage = Conversation(
            id: UUID(), role: "assistant", content: currentText,
            timestamp: Date(), conversationId: conversationId
        )
        modelContext.insert(assistantMessage)
        try? modelContext.save()
        loadMessages()
        AppLogger.chat.info("💾 最終 assistant メッセージ保存: \(currentText.count)文字")
    }

    // MARK: - Cancel

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
    
    // MARK: - Legacy methods (互換性のため残す)
    
    func continueTool() {
        // LangGraph では使わないが、View が呼び出す可能性があるので空実装
        AppLogger.chat.warning("⚠️ continueTool is not used in LangGraph mode")
    }
    
    func finishTool() {
        // LangGraph では使わないが、View が呼び出す可能性があるので空実装
        AppLogger.chat.warning("⚠️ finishTool is not used in LangGraph mode")
    }
}
