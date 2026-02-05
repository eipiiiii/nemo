//
//  ChatView.swift
//  nemo
//
//  Created by 林栄介 on 2026/01/31.
//

import SwiftUI
import SwiftData
import MarkdownUI

struct ChatView: View {
    let conversationId: UUID
    let modelContext: ModelContext
    @StateObject private var viewModel: ChatViewModel
    @FocusState private var isInputFocused: Bool
    
    init(conversationId: UUID, modelContext: ModelContext) {
        self.conversationId = conversationId
        self.modelContext = modelContext
        _viewModel = StateObject(wrappedValue: ChatViewModel(conversationId: conversationId, modelContext: modelContext))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // メッセージリスト
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                MessageBubbleView(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding()
                        .padding(.bottom, 120)
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        if let lastMessage = viewModel.messages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: viewModel.isLoading) { _, isLoading in
                        if !isLoading, let lastMessage = viewModel.messages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
            }
            // メッセージ下部のグラデーション
            .overlay(alignment: .bottom) {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(nsColor: .windowBackgroundColor).opacity(0),
                        Color(nsColor: .windowBackgroundColor).opacity(0.5),
                        Color(nsColor: .windowBackgroundColor).opacity(1)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 100)
                .allowsHitTesting(false)
            }
            
            // 入力エリア(Liquid Glass効果付き)
            VStack(alignment: .leading, spacing: 0) {
                // エラー表示
                if let errorMessage = viewModel.errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("閉じる") {
                            viewModel.errorMessage = nil
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.1))
                }
                
                // Liquid Glass入力フィールド
                HStack(alignment: .bottom, spacing: 12) {
                    TextField("メッセージを入力", text: $viewModel.messageText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .focused($isInputFocused)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .lineLimit(1...5)
                        .background {
                            ZStack {
                                // ベースのガラスマテリアル
                                Capsule()
                                    .fill(.regularMaterial)
                                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                                
                                // レンズ効果（内側のハイライト）
                                Capsule()
                                    .stroke(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                .white.opacity(isInputFocused ? 0.4 : 0.2),
                                                .white.opacity(0.0),
                                                .white.opacity(isInputFocused ? 0.1 : 0.05)
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.5
                                    )
                                    .padding(0.5)
                                
                                // フォーカス時の発光効果
                                if isInputFocused {
                                    Capsule()
                                        .stroke(
                                            LinearGradient(
                                                gradient: Gradient(colors: [
                                                    .blue.opacity(0.3),
                                                    .cyan.opacity(0.2),
                                                    .blue.opacity(0.3)
                                                ]),
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            ),
                                            lineWidth: 2
                                        )
                                        .shadow(color: .blue.opacity(0.4), radius: 12, x: 0, y: 0)
                                        .shadow(color: .cyan.opacity(0.3), radius: 8, x: 0, y: 0)
                                        .transition(.opacity)
                                }
                                
                                // 微細なボーダー
                                Capsule()
                                    .strokeBorder(
                                        .white.opacity(0.15),
                                        lineWidth: 0.5
                                    )
                            }
                        }
                        .onSubmit {
                            viewModel.sendMessage()
                        }
                        .disabled(viewModel.isLoading)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isInputFocused)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background {
                    // バックグラウンドの薄いガラス効果
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: -1)
                        .ignoresSafeArea(edges: .bottom)
                }
            }
        }
        .id(conversationId)
    }
}

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
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(18)
                } else {
                    Markdown(message.content)
                        .markdownTheme(.gitHub)
                        .markdownTextStyle {
                            ForegroundColor(.primary)
                            FontSize(14)
                        }
                        .markdownBlockStyle(\.codeBlock) { configuration in
                            configuration.label
                                .padding()
                                .background(Color(nsColor: .textBackgroundColor))
                                .cornerRadius(8)
                                .markdownTextStyle {
                                    FontFamilyVariant(.monospaced)
                                    FontSize(13)
                                }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(18)
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

    // Seed mock messages for preview
    let conversationId = UUID()
    let messages: [Conversation] = [
        Conversation(id: UUID(), role: "user", content: "こんにちは！このアプリはどんなことができますか？", timestamp: Date(), conversationId: conversationId),
        Conversation(id: UUID(), role: "assistant", content: "こんにちは！このアプリではチャット形式でやり取りができます。メッセージを入力して送信すると、ここに返信が表示されます。", timestamp: Date(), conversationId: conversationId),
        Conversation(id: UUID(), role: "user", content: "スクロールのテストをしたいので、少し長めのテキストを送ります。スクロール位置が下に追従するか確認してください。", timestamp: Date(), conversationId: conversationId),
        Conversation(id: UUID(), role: "assistant", content: "了解しました。以下はダミーテキストです。\n\nSwiftUI は宣言的な UI フレームワークで、ビューの状態に応じて UI を構築します。スクロールやレイアウトの挙動は、`ScrollView` や `LazyVStack` を組み合わせることで柔軟に表現できます。長文を表示することで、下部へのオートスクロールや表示の最適化を確認できます。さらにコードブロックや Markdown の表現も組み込めます。\n\n```swift\nstruct ExampleView: View {\n    var body: some View {\n        ScrollView {\n            Text(\"Hello\")\n        }\n    }\n}\n```\n\nこのように長文とコードを混在させて、見え方を確認してください。", timestamp: Date(), conversationId: conversationId),
        Conversation(id: UUID(), role: "user", content: "ありがとうございます！もう少しメッセージを追加しておきます。", timestamp: Date(), conversationId: conversationId),
        Conversation(id: UUID(), role: "assistant", content: "はい、十分な件数のメッセージがあるとスクロールのテストがしやすくなります。必要に応じてさらに増やしてください。", timestamp: Date(), conversationId: conversationId)
    ]

    let _ = messages.forEach { context.insert($0) }
    let _ = try? context.save()

    return ChatView(conversationId: conversationId, modelContext: context)
        .modelContainer(container)
}
