//
//  SettingsView.swift
//  nemo
//
//  Created by 林栄介 on 2026/01/31.
//

import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State private var showingModelSelection = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("設定")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("完了") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // カスタム指示
                    VStack(alignment: .leading, spacing: 12) {
                        Text("カスタム指示")
                            .font(.headline)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("AIの振る舞いや制約を追加できます（オプション）")
                                .font(.caption).foregroundColor(.secondary)
                            TextEditor(text: $viewModel.customPrompt)
                                .font(.system(.body))
                                .frame(height: 100)
                                .padding(8)
                                .background(Color(nsColor: .textBackgroundColor))
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                                .onChange(of: viewModel.customPrompt) { _, _ in viewModel.saveCustomPrompt() }
                            HStack {
                                Text("例: 「回答は日本語で、簡潔にまとめてください」")
                                    .font(.caption).foregroundColor(.secondary)
                                Spacer()
                                if !viewModel.customPrompt.isEmpty {
                                    Button("クリア") {
                                        viewModel.customPrompt = ""
                                        viewModel.saveCustomPrompt()
                                    }.font(.caption)
                                }
                            }
                        }
                    }

                    Divider()

                    // OpenRouter API
                    VStack(alignment: .leading, spacing: 12) {
                        Text("OpenRouter API").font(.headline)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("APIキー").font(.subheadline).foregroundColor(.secondary)
                            SecureField("APIキーを入力", text: $viewModel.apiKey)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { viewModel.saveApiKey() }
                        }
                    }

                    Divider()

                    // SearXNG
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass.circle")
                                .foregroundColor(.secondary)
                            Text("SearXNG (検索サーバー)")
                                .font(.headline)
                                
                            Spacer()
                            
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(statusColor(for: viewModel.searxngServerStatus))
                                    .frame(width: 8, height: 8)
                                Text(statusText(for: viewModel.searxngServerStatus))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Button(action: {
                                    viewModel.checkSearxngServerStatus()
                                }) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(12)
                        }
                        Text("Docker で起動した SearXNG サーバーの URL。web_search ツールで使用されます。")
                            .font(.caption).foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("サーバー URL").font(.subheadline).foregroundColor(.secondary)
                            TextField("http://localhost:8080", text: $viewModel.searxngUrl)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { viewModel.saveSearxngUrl() }
                                .onChange(of: viewModel.searxngUrl) { _, _ in viewModel.saveSearxngUrl() }
                        }
                    }

                    Divider()

                    // モデル選択
                    VStack(alignment: .leading, spacing: 12) {
                        Text("選択中のモデル").font(.headline)
                        if !viewModel.selectedModelId.isEmpty {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(viewModel.selectedModelId).font(.subheadline)
                                    Text("選択中").font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("変更") {
                                    viewModel.saveApiKey()
                                    viewModel.fetchModels()
                                    showingModelSelection = true
                                }
                                .disabled(viewModel.isLoading || viewModel.apiKey.isEmpty)
                            }
                            .padding()
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(8)
                        } else {
                            Text("モデルが選択されていません")
                                .font(.subheadline).foregroundColor(.secondary)
                            Button("モデルを選択") {
                                viewModel.saveApiKey()
                                viewModel.fetchModels()
                                showingModelSelection = true
                            }
                            .disabled(viewModel.isLoading || viewModel.apiKey.isEmpty)
                        }
                    }

                    if viewModel.isLoading {
                        Divider()
                        HStack(spacing: 12) {
                            ProgressView().controlSize(.small)
                            Text("読み込み中...").font(.subheadline).foregroundColor(.secondary)
                        }
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                                Text("エラー").font(.headline)
                            }
                            Text(errorMessage).font(.subheadline).foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 500, maxWidth: 600, minHeight: 400, maxHeight: 700)
        .sheet(isPresented: $showingModelSelection) {
            ModelSelectionView(viewModel: viewModel)
        }
    }

    private func statusColor(for status: SettingsViewModel.ServerStatus) -> Color {
        switch status {
        case .online:
            return .green
        case .offline:
            return .red
        case .checking:
            return .orange
        case .unknown:
            return .gray
        }
    }

    private func statusText(for status: SettingsViewModel.ServerStatus) -> String {
        switch status {
        case .online:
            return "オンライン"
        case .offline:
            return "オフライン"
        case .checking:
            return "確認中..."
        case .unknown:
            return "不明"
        }
    }
}

#Preview {
    SettingsView()
}

struct ModelSelectionView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    var filteredModels: [Model] {
        searchText.isEmpty ? viewModel.models : viewModel.models.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.id.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("モデル選択").font(.title2).fontWeight(.semibold)
                Spacer()
                Button("完了") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("モデル名で検索", text: $searchText).textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .padding()

            Divider()

            if viewModel.isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("モデル一覧を取得中...").font(.subheadline).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredModels) { model in
                            Button(action: { viewModel.selectModel(model); dismiss() }) {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(model.name).font(.headline).foregroundColor(.primary)
                                        if let description = model.description {
                                            Text(description).font(.caption).foregroundColor(.secondary).lineLimit(2)
                                        }
                                        HStack(spacing: 12) {
                                            if let contextLength = model.contextLength {
                                                Label("\(contextLength)", systemImage: "text.alignleft")
                                                    .font(.caption2).foregroundColor(.secondary)
                                            }
                                            if let pricing = model.pricing {
                                                if let prompt = pricing.prompt {
                                                    Label("$\(prompt)", systemImage: "arrow.down")
                                                        .font(.caption2).foregroundColor(.secondary)
                                                }
                                                if let completion = pricing.completion {
                                                    Label("$\(completion)", systemImage: "arrow.up")
                                                        .font(.caption2).foregroundColor(.secondary)
                                                }
                                            }
                                        }
                                    }
                                    Spacer()
                                    if viewModel.selectedModelId == model.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.blue).font(.title3)
                                    }
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(viewModel.selectedModelId == model.id ? Color.blue.opacity(0.1) : Color.clear)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(minWidth: 600, maxWidth: 700, minHeight: 400, maxHeight: 600)
    }
}

#Preview {
    SettingsView()
}
