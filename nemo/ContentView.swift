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
    @State private var newConversationTitle = ""
    @State private var showingNewConversationSheet = false
    @State private var selectedConversationId: UUID?
    
    var conversationGroups: [UUID: [Conversation]] {
        Dictionary(grouping: conversations, by: { $0.conversationId })
    }
    
    var conversationTitles: [(UUID, String)] {
        conversationGroups.map { conversationId, convs in
            let title = convs.first(where: { $0.role == "user" })?.content.prefix(30).description ?? "新しい会話"
            return (conversationId, String(title))
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedConversationId) {
                Section("会話") {
                    ForEach(conversationTitles, id: \.0) { conversationId, title in
                        NavigationLink(value: conversationId) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(title)
                                    .font(.headline)
                                if let lastMessage = conversationGroups[conversationId]?.last {
                                    Text(lastMessage.content.prefix(50).description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .contextMenu {
                            Button("タイトルを編集") {
                                newConversationTitle = title
                                selectedConversationId = conversationId
                                showingNewConversationSheet = true
                            }
                            Button("削除", role: .destructive) {
                                deleteConversation(conversationId: conversationId)
                            }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 250)
            .toolbar {
                ToolbarItem {
                    Button(action: {
                        showingNewConversationSheet = true
                    }) {
                        Label("新しい会話", systemImage: "plus")
                    }
                }
                ToolbarItem {
                    NavigationLink(destination: SettingsView()) {
                        Label("設定", systemImage: "gear")
                    }
                }
            }
        } detail: {
            if let selectedId = selectedConversationId {
                ChatView(conversationId: selectedId)
            } else {
                Text("会話を選択してください")
                    .foregroundColor(.secondary)
            }
        }
        .sheet(isPresented: $showingNewConversationSheet) {
            NewConversationSheet(
                title: $newConversationTitle,
                onSave: { title in
                    createNewConversation(title: title)
                    showingNewConversationSheet = false
                }
            )
        }
    }
    
    private func createNewConversation(title: String) {
        let conversationId = UUID()
        let firstMessage = Conversation(
            role: "user",
            content: title.isEmpty ? "新しい会話" : title,
            conversationId: conversationId
        )
        modelContext.insert(firstMessage)
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
}

struct NewConversationSheet: View {
    @Binding var title: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                TextField("会話のタイトル", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                
                Spacer()
            }
            .navigationTitle("新しい会話")
            .toolbar {
                ToolbarItem {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                ToolbarItem {
                    Button("作成") {
                        onSave(title)
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Conversation.self, inMemory: true)
}
