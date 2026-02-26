//
//  ChatView.swift
//  nemo
//
//  Created by 林栄介 on 2026/01/31.
//

//  ChatView.swift — nemo

import MarkdownUI
import SwiftData
import SwiftUI

struct ChatView: View {
    let conversationId: UUID
    let modelContext: ModelContext
    @StateObject private var viewModel: ChatViewModel
    @FocusState private var isInputFocused: Bool

    init(conversationId: UUID, modelContext: ModelContext) {
        self.conversationId = conversationId
        self.modelContext = modelContext
        _viewModel = StateObject(
            wrappedValue: ChatViewModel(
                conversationId: conversationId, modelContext: modelContext))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                MessageBubbleView(message: message).id(message.id)
                            }
                            // ストリーミング中の仮バブル
                            if viewModel.isStreaming {
                                StreamingBubbleView(content: viewModel.streamingContent)
                                    .id("streaming")
                            }
                        }
                        .padding()
                        .padding(.bottom, 60)
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        if let last = viewModel.messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                    .onChange(of: viewModel.isLoading) { _, loading in
                        if !loading, let last = viewModel.messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                    // ストリーミング中はリアルタイムでスクロール追従
                    .onChange(of: viewModel.streamingContent) { _, _ in
                        if viewModel.isStreaming {
                            proxy.scrollTo("streaming", anchor: .bottom)
                        }
                    }
                    .onChange(of: viewModel.isStreaming) { _, streaming in
                        if !streaming, let last = viewModel.messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
            }

            // 入力エリア
            VStack(alignment: .leading, spacing: 0) {
                if let err = viewModel.errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                        Text(err).font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Button("閉じる") { viewModel.errorMessage = nil }.font(.caption)
                    }
                    .padding(.horizontal).padding(.vertical, 8)
                    .background(Color.orange.opacity(0.1))
                }

                HStack(alignment: .bottom, spacing: 12) {
                    TextField("メッセージを入力", text: $viewModel.messageText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .focused($isInputFocused)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .glassEffect(.clear, in: .capsule)
                        .onSubmit { viewModel.sendMessage() }
                        .disabled(viewModel.isLoading || viewModel.isStreaming)

                    // ストリーミング中は停止ボタンを表示
                    if viewModel.isStreaming {
                        Button {
                            viewModel.cancelStreaming()
                        } label: {
                            Image(systemName: "stop.circle.fill")
                                .font(.title2).foregroundColor(.red)
                        }
                        .buttonStyle(.plain).padding(.trailing, 4)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct MessageBubbleView: View {
    let message: Conversation

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == "user" { Spacer(minLength: 60) }
            Group {
                if message.role == "user" {
                    Text(message.content)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .foregroundColor(.primary)
                        .background(Color.gray.opacity(0.25))
                        .cornerRadius(18)
                } else {
                    Markdown(message.content)
                        .markdownTheme(
                            .gitHub.text {
                                FontSize(13)
                                ForegroundColor(.primary)
                            }
                        )
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                }
            }
            if message.role != "user" { Spacer(minLength: 60) }
        }
    }
}

// ストリーミング中の仮バブル（MarkdownUI未完結パース問題を回避するためText使用）
struct StreamingBubbleView: View {
    let content: String
    @State private var showCursor = true

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(content + (showCursor ? "▌" : " "))
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .textSelection(.enabled)
            Spacer(minLength: 60)
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                showCursor.toggle()
            }
        }
    }
}
