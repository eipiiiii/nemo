//
//  ChatView.swift
//  nemo
//
//  Created by 林栄介 on 2026/02/27.
//

import Combine
import MarkdownUI
import SwiftData
import SwiftUI

struct ChatView: View {
    let conversationId: UUID
    let modelContext: ModelContext
    @StateObject private var viewModel: ChatViewModel
    @FocusState private var isInputFocused: Bool
    @AppStorage("selected_model_id") private var selectedModelId: String = ""
    @State private var showingSettings = false

    init(conversationId: UUID, modelContext: ModelContext) {
        self.conversationId = conversationId
        self.modelContext = modelContext
        _viewModel = StateObject(
            wrappedValue: ChatViewModel(conversationId: conversationId, modelContext: modelContext))
    }

    private var modelDisplayName: String {
        guard !selectedModelId.isEmpty else { return "モデル未選択" }
        return selectedModelId
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        if message.role == "tool_use" {
                            ToolCallBubbleView(message: message)
                                .id(message.id)
                        } else {
                            MessageBubbleView(message: message)
                                .id(message.id)
                        }
                    }
                    if let status = viewModel.toolCallStatus {
                        ToolCallProgressView(status: status)
                            .id("tool_progress")
                    }
                    if viewModel.isStreaming && !viewModel.streamingContent.isEmpty {
                        StreamingBubbleView(content: viewModel.streamingContent)
                            .id("streaming")
                    }
                    if viewModel.isStreaming && viewModel.streamingContent.isEmpty && viewModel.toolCallStatus == nil && !viewModel.awaitingContinuationChoice {
                        TypingIndicatorView()
                            .id("typing")
                    }
                    if viewModel.awaitingContinuationChoice {
                        ContinuationChoiceView(
                            onContinue: { viewModel.continueTool() },
                            onFinish: { viewModel.finishTool() }
                        )
                        .id("continuation")
                    }
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                inputBar
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                guard let last = viewModel.messages.last else { return }
                DispatchQueue.main.async {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: viewModel.toolCallStatus) { _, status in
                guard status != nil else { return }
                DispatchQueue.main.async {
                    withAnimation { proxy.scrollTo("tool_progress", anchor: .bottom) }
                }
            }
            .onChange(of: viewModel.awaitingContinuationChoice) { _, waiting in
                guard waiting else { return }
                DispatchQueue.main.async {
                    withAnimation { proxy.scrollTo("continuation", anchor: .bottom) }
                }
            }
            .onChange(of: viewModel.isStreaming) { _, isStreaming in
                guard isStreaming else { return }
                DispatchQueue.main.async {
                    withAnimation { proxy.scrollTo("typing", anchor: .bottom) }
                }
            }
            .onReceive(
                viewModel.$streamingContent
                    .throttle(for: .milliseconds(120), scheduler: RunLoop.main, latest: true)
            ) { _ in
                guard viewModel.isStreaming else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            }
            .onChange(of: viewModel.isLoading) { _, isLoading in
                guard !isLoading, let last = viewModel.messages.last else { return }
                DispatchQueue.main.async {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button {
                    showingSettings = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                            .font(.caption)
                        Text(modelDisplayName)
                            .font(.caption)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Input Bar

    @ViewBuilder
    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let errorMessage = viewModel.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("閉じる") {
                        viewModel.errorMessage = nil
                    }
                    .font(.caption)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
            }

            HStack(alignment: .bottom, spacing: 12) {
                TextField("メッセージを入力", text: $viewModel.messageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .focused($isInputFocused)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .glassEffect(.clear, in: .capsule)
                    .onSubmit {
                        if viewModel.isStreaming {
                            viewModel.cancelStreaming()
                        } else {
                            viewModel.sendMessage()
                        }
                    }
                    .disabled(viewModel.isLoading)

                if viewModel.isStreaming {
                    Button {
                        viewModel.cancelStreaming()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

// MARK: - Continuation Choice Banner

struct ContinuationChoiceView: View {
    let onContinue: () -> Void
    let onFinish: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.trianglehead.2.clockwise")
                .foregroundStyle(.orange)
            Text("ツール呼び出しが5回に達しました。続行しますか？")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("続行する") { onContinue() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.orange)
            Button("まとめて回答") { onFinish() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.orange.opacity(0.3), lineWidth: 0.5)
        }
    }
}

// MARK: - Tool Call Bubble（折りたたみ）

struct ToolCallBubbleView: View {
    let message: Conversation
    @State private var isExpanded: Bool = false

    var body: some View {
        HStack(alignment: .top) {
            DisclosureGroup(
                isExpanded: $isExpanded,
                content: {
                    if let result = message.toolResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(.top, 2)
                    }
                },
                label: {
                    Label {
                        Text(message.toolName ?? "tool")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.separator, lineWidth: 0.5)
            }
            .animation(.easeInOut(duration: 0.2), value: isExpanded)

            Spacer(minLength: 60)
        }
    }
}

// MARK: - Tool 実行中インジケーター

struct ToolCallProgressView: View {
    let status: String

    var body: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 14, height: 14)
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}

// MARK: - Streaming Bubble

struct StreamingBubbleView: View {
    let content: String

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Markdown(content)
                .markdownTheme(
                    .gitHub
                        .text {
                            FontSize(13)
                            ForegroundColor(.primary)
                        }
                )
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            Spacer(minLength: 60)
        }
    }
}

// MARK: - Typing Indicator

struct TypingIndicatorView: View {
    @State private var dotCount = 0
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(String(repeating: "●", count: dotCount + 1))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .onReceive(timer) { _ in
                    dotCount = (dotCount + 1) % 3
                }
            Spacer()
        }
    }
}

// MARK: - Message Bubble

struct MessageBubbleView: View {
    let message: Conversation

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == "user" {
                Spacer(minLength: 60)
            }

            Group {
                if message.role == "user" {
                    Text(message.content)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .foregroundStyle(.primary)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 18))
                } else {
                    Markdown(message.content)
                        .markdownTheme(
                            .gitHub
                                .text {
                                    FontSize(13)
                                    ForegroundColor(.primary)
                                }
                        )
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
            }

            if message.role != "user" {
                Spacer(minLength: 60)
            }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Conversation.self, configurations: config)
    let context = ModelContext(container)

    let conversationId = UUID()
    let messages: [Conversation] = [
        Conversation(
            id: UUID(), role: "user", content: "現在時刻を教えて", timestamp: Date(),
            conversationId: conversationId),
        Conversation(
            id: UUID(), role: "assistant",
            content: "現在の時刻は **2026年02月27日 11:17:59（金曜日）** です。",
            timestamp: Date(), conversationId: conversationId),
    ]

    let _ = messages.forEach { context.insert($0) }
    let _ = try? context.save()

    return ChatView(conversationId: conversationId, modelContext: context)
        .modelContainer(container)
}
