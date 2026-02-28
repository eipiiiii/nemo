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
            // ヘッダー
            HStack {
                Text("設定")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("完了") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // コンテンツ
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // カスタムプロンプト設定
                    VStack(alignment: .leading, spacing: 12) {
                        Text("カスタム指示")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("AIの振る舞いや制約を追加できます（オプション）")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            TextEditor(text: $viewModel.customPrompt)
                                .font(.system(.body, design: .default))
                                .frame(height: 100)
                                .padding(8)
                                .background(Color(nsColor: .textBackgroundColor))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                                .onChange(of: viewModel.customPrompt) { _, _ in
                                    viewModel.saveCustomPrompt()
                                }

                            HStack {
                                Text("例: 「回答は日本語で、簡潔にまとめてください」")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                if !viewModel.customPrompt.isEmpty {
                                    Button("クリア") {
                                        viewModel.customPrompt = ""
                                        viewModel.saveCustomPrompt()
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                    }

                    Divider()

                    // OpenRouter API 設定
                    VStack(alignment: .leading, spacing: 12) {
                        Text("OpenRouter API")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("APIキー")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            SecureField("APIキーを入力", text: $viewModel.apiKey)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    viewModel.saveApiKey()
                                }

                            Button("モデル一覧を取得") {
                                viewModel.saveApiKey()
                                viewModel.fetchModels()
                            }
                            .disabled(viewModel.isLoading || viewModel.apiKey.isEmpty)
                        }
                    }

                    Divider()

                    // Google CSE 設定
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            Text("Google 検索 (CSE)")
                                .font(.headline)
                        }

                        Text("web_search ツールで使用されます。未設定の場合、検索機能は無効になります。")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("API キー")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            SecureField("Google CSE API キーを入力", text: $viewModel.googleCseApiKey)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { viewModel.saveGoogleCseApiKey() }
                                .onChange(of: viewModel.googleCseApiKey) { _, _ in
                                    viewModel.saveGoogleCseApiKey()
                                }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("検索エンジン ID (cx)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            TextField("例: 012345678901234567890", text: $viewModel.googleCseCx)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { viewModel.saveGoogleCseCx() }
                                .onChange(of: viewModel.googleCseCx) { _, _ in
                                    viewModel.saveGoogleCseCx()
                                }
                        }

                        // 設定状態インジケーター
                        HStack(spacing: 6) {
                            if !viewModel.googleCseApiKey.isEmpty && !viewModel.googleCseCx.isEmpty {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("検索機能有効")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "exclamationmark.circle")
                                    .foregroundColor(.orange)
                                Text("未設定 — 両方入力すると有効になります")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                            Spacer()
                            Link("取得方法",
                                 destination: URL(string: "https://developers.google.com/custom-search/v1/overview")!)
                                .font(.caption)
                        }
                    }

                    Divider()

                    // モデル選択
                    VStack(alignment: .leading, spacing: 12) {
                        Text("選択中のモデル")
                            .font(.headline)

                        if !viewModel.selectedModelId.isEmpty {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(viewModel.selectedModelId)
                                        .font(.subheadline)
                                    Text("選択中")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("変更") {
                                    showingModelSelection = true
                                }
                                .disabled(viewModel.models.isEmpty)
                            }
                            .padding()
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(8)
                        } else {
                            Text("モデルが選択されていません")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Button("モデルを選択") {
                                showingModelSelection = true
                            }
                            .disabled(viewModel.models.isEmpty)
                        }
                    }

                    // ローディング表示
                    if viewModel.isLoading {
                        Divider()
                        HStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.small)
                            Text("読み込み中...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    // エラー表示
                    if let errorMessage = viewModel.errorMessage {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("エラー")
                                    .font(.headline)
                            }
                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 500, maxWidth: 600, minHeight: 400, maxHeight: 750)
        .sheet(isPresented: $showingModelSelection) {
            ModelSelectionView(viewModel: viewModel)
        }
    }
}

struct ModelSelectionView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    var filteredModels: [Model] {
        if searchText.isEmpty {
            return viewModel.models
        } else {
            return viewModel.models.filter { model in
                model.name.localizedCaseInsensitiveContains(searchText) ||
                    model.id.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            HStack {
                Text("モデル選択")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("完了") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            // 検索バー
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("モデル名で検索", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .padding()

            Divider()

            // モデルリスト
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredModels) { model in
                        Button(action: {
                            viewModel.selectModel(model)
                            dismiss()
                        }) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(model.name)
                                        .font(.headline)
                                        .foregroundColor(.primary)

                                    if let description = model.description {
                                        Text(description)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }

                                    HStack(spacing: 12) {
                                        if let contextLength = model.contextLength {
                                            Label("\(contextLength)", systemImage: "text.alignleft")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        if let pricing = model.pricing {
                                            if let prompt = pricing.prompt {
                                                Label("$\(prompt)", systemImage: "arrow.down")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                            if let completion = pricing.completion {
                                                Label("$\(completion)", systemImage: "arrow.up")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                }

                                Spacer()

                                if viewModel.selectedModelId == model.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                        .font(.title3)
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
        .frame(minWidth: 600, maxWidth: 700, minHeight: 400, maxHeight: 600)
    }
}

#Preview {
    SettingsView()
}
