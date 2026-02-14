//
//  ContentView.swift
//  nemo
//
//  Created by 林栄介 on 2026/01/31.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var conversations: [Conversation]
    @StateObject private var viewModel = ConversationListViewModel()
    
    var body: some View {
        NavigationSplitView {
            // サイドバー
            List(selection: $viewModel.selectedConversationId) {
                ForEach(viewModel.buildConversationTitles(from: conversations), id: \.0) { conversationId, title, date in
                    NavigationLink(value: conversationId) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title)
                                .font(.headline)
                                .lineLimit(1)
                            if let group = Dictionary(grouping: conversations, by: { $0.conversationId })[conversationId],
                               let lastMessage = group.last {
                                Text(lastMessage.content)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .contextMenu {
                        Button("削除", role: .destructive) {
                            viewModel.deleteConversation(conversationId: conversationId, in: modelContext, from: conversations)
                        }
                    }
                }
                .onDelete { offsets in
                    viewModel.deleteConversations(at: offsets, in: modelContext, from: conversations)
                }
            }
            .navigationTitle("会話")
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 350)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .controlBackgroundColor))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        _ = viewModel.createNewConversation(in: modelContext)
                    }) {
                        Image(systemName: "square.and.pencil")
                    }
                    .help("新しい会話")
                }
                ToolbarItem(placement: .navigation) {
                    Button(action: { viewModel.showingSettings = true }) {
                        Image(systemName: "gear")
                    }
                    .help("設定")
                }
                }
        } detail: {
            if let selectedId = viewModel.selectedConversationId {
                ChatView(conversationId: selectedId, modelContext: modelContext)
                    .id(selectedId)
                    .toolbarBackground(.hidden, for: .windowToolbar)  // ツールバー背景を非表示
                    .toolbarTitleDisplayMode(.inline)  // タイトル表示モードをインラインに
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    Text("会話を選択するか、新しい会話を開始してください")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button(action: {
                        _ = viewModel.createNewConversation(in: modelContext)
                    }) {
                        Label("新しい会話", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .sheet(isPresented: $viewModel.showingSettings) {
            SettingsView()
                .frame(minWidth: 600, minHeight: 500)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Conversation.self, inMemory: true)
}