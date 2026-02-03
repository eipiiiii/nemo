//
//  ChatView.swift
//  nemo
//
//  Created by 林栄介 on 2026/01/31.
//

import SwiftUI
import SwiftData

struct ChatView: View {
    let conversationId: UUID
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: ChatViewModel
    @FocusState private var isTextFieldFocused: Bool
    
    init(conversationId: UUID, modelContext: ModelContext) {
        self.conversationId = conversationId
        _viewModel = StateObject(wrappedValue: ChatViewModel(conversationId: conversationId, modelContext: modelContext))
    }

    var body: some View {
        VStack(spacing: 0) {
            // メッセージリスト
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                        
                        if viewModel.isLoading {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("考え中...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal)
                            .id("loading")
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    if let lastMessage = viewModel.messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: viewModel.isLoading) { _, isLoading in
                    if isLoading {
                        withAnimation {
                            proxy.scrollTo("loading", anchor: .bottom)
                        }
                    }
                }
            }
            
            Divider()
            
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
            
            // 入力エリア (iMessage風)
            HStack(alignment: .bottom, spacing: 12) {
                CustomTextField(
                    text: $viewModel.messageText,
                    isLoading: viewModel.isLoading,
                    onSend: {
                        viewModel.sendMessage()
                    }
                )
                .focused($isTextFieldFocused)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .onAppear {
            isTextFieldFocused = true
        }
    }
}

struct MessageBubble: View {
    let message: Conversation
    
    var body: some View {
        HStack {
            if message.role == "user" {
                Spacer(minLength: 60)
            }
            
            Text(message.content)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    message.role == "user" 
                    ? Color.blue 
                    : Color(nsColor: .controlBackgroundColor)
                )
                .foregroundColor(
                    message.role == "user" 
                    ? .white 
                    : .primary
                )
                .cornerRadius(18)
            
            if message.role != "user" {
                Spacer(minLength: 60)
            }
        }
    }
}

struct CustomTextField: NSViewRepresentable {
    @Binding var text: String
    let isLoading: Bool
    let onSend: () -> Void
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.backgroundColor = NSColor.controlBackgroundColor
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 10, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.controlBackgroundColor
        scrollView.borderType = .lineBorder
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        if textView.string != text {
            textView.string = text
        }
        context.coordinator.isLoading = isLoading
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isLoading: isLoading, onSend: onSend)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var isLoading: Bool
        let onSend: () -> Void
        
        init(text: Binding<String>, isLoading: Bool, onSend: @escaping () -> Void) {
            _text = text
            self.isLoading = isLoading
            self.onSend = onSend
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
        
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Enterキーで送信（Shiftが押されていない場合）
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if let event = NSApp.currentEvent,
                   !event.modifierFlags.contains(.shift) {
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading {
                        onSend()
                        return true
                    }
                }
            }
            return false
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Conversation.self, configurations: config)
    let context = ModelContext(container)
    
    return ChatView(conversationId: UUID(), modelContext: context)
        .modelContainer(container)
}
