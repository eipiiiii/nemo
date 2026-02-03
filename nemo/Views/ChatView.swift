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
    
    init(conversationId: UUID, modelContext: ModelContext) {
        self.conversationId = conversationId
        _viewModel = StateObject(wrappedValue: ChatViewModel(conversationId: conversationId, modelContext: modelContext))
    }

    var body: some View {
        VStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.messages) { message in
                        if message.role == "user" {
                            HStack {
                                Spacer()
                                Text(message.content)
                                    .padding(10)
                                    .background(Color.blue.opacity(0.2))
                                    .cornerRadius(15)
                                    .foregroundColor(.primary)
                            }
                        } else {
                            HStack {
                                Text(message.content)
                                    .padding(10)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(15)
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                        }
                    }
                }
                .padding()
                
                if viewModel.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding()
                        Spacer()
                    }
                }
            }
            
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
            }
            
            HStack(alignment: .bottom) {
                TextField("メッセージを入力", text: $viewModel.messageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.gray.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    )
                    .lineLimit(1...5)
                    .onSubmit {
                        viewModel.sendMessage()
                    }
                
                Button(action: {
                    viewModel.sendMessage()
                }) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.blue)
                        .clipShape(Circle())
                }
                .disabled(viewModel.isLoading || viewModel.messageText.isEmpty)
            }
            .padding()
        }
        .navigationTitle("チャット")
    }
}

#Preview {
    // Preview requires a proper ModelContainer setup
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Conversation.self, configurations: config)
    let context = ModelContext(container)
    
    return ChatView(conversationId: UUID(), modelContext: context)
        .modelContainer(container)
}
