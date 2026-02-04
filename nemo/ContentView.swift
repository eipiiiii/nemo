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
    @State private var selectedConversationId: UUID?
    @State private var showingSettings = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    var conversationGroups: [UUID: [Conversation]] {
        Dictionary(grouping: conversations, by: { $0.conversationId })
    }
    
    var conversationTitles: [(UUID, String, Date)] {
        conversationGroups.map { conversationId, convs in
            let title = convs.first(where: { $0.role == "user" })?.content.prefix(30).description ?? "新しい会話"
            let date = convs.last?.timestamp ?? Date()
            return (conversationId, String(title), date)
        }.sorted { $0.2 > $1.2 }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // サイドバー
            List(selection: $selectedConversationId) {
                ForEach(conversationTitles, id: \.0) { conversationId, title, date in
                    NavigationLink(value: conversationId) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title)
                                .font(.headline)
                                .lineLimit(1)
                            if let lastMessage = conversationGroups[conversationId]?.last {
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
                            deleteConversation(conversationId: conversationId)
                        }
                    }
                }
                .onDelete(perform: deleteConversations)
            }
            .navigationTitle("会話")
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 350)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .controlBackgroundColor))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: createNewConversation) {
                        Image(systemName: "square.and.pencil")
                    }
                    .help("新しい会話")
                }
                ToolbarItem(placement: .navigation) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gear")
                    }
                    .help("設定")
                }
            }
        } detail: {
            if let selectedId = selectedConversationId {
                ChatView(conversationId: selectedId, modelContext: modelContext)
                    .id(selectedId)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    Text("会話を選択するか、新しい会話を開始してください")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button(action: createNewConversation) {
                        Label("新しい会話", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .frame(minWidth: 600, minHeight: 500)
        }
    }
    
    private func createNewConversation() {
        let conversationId = UUID()
        selectedConversationId = conversationId
    }
    
    private func deleteConversation(conversationId: UUID) {
        let conversationsToDelete = conversations.filter { $0.conversationId == conversationId }
        for conversation in conversationsToDelete {
            modelContext.delete(conversation)
        }
        if selectedConversationId == conversationId {
            selectedConversationId = nil
        }
    }
    
    private func deleteConversations(at offsets: IndexSet) {
        for index in offsets {
            let conversationId = conversationTitles[index].0
            deleteConversation(conversationId: conversationId)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Conversation.self, inMemory: true)
}
