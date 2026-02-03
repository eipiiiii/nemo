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
    
    var body: some View {
        NavigationView {
            Form {
                Section("API設定") {
                    TextField("OpenRouter APIキー", text: $viewModel.apiKey, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            viewModel.saveApiKey()
                            viewModel.fetchModels()
                        }
                    
                    Button("モデル一覧を取得") {
                        viewModel.saveApiKey()
                        viewModel.fetchModels()
                    }
                    .disabled(viewModel.isLoading)
                }
                
                Section("選択中のモデル") {
                    if !viewModel.selectedModelId.isEmpty {
                        Text("選択中: \(viewModel.selectedModelId)")
                        Button("モデルを選択") {
                            showingModelSelection = true
                        }
                    } else {
                        Text("未選択")
                        Button("モデルを選択") {
                            showingModelSelection = true
                        }
                    }
                }
                
                if viewModel.isLoading {
                    Section("読み込み中...") {
                        ProgressView()
                    }
                }
                
                if let errorMessage = viewModel.errorMessage {
                    Section("エラー") {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showingModelSelection) {
            ModelSelectionView(viewModel: viewModel)
        }
    }
}

struct ModelSelectionView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var searchText = ""
    
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
        NavigationView {
            List {
                Section("検索") {
                    TextField("モデル名で検索", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                }
                
                Section("モデル一覧") {
                    ForEach(filteredModels) { model in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.name)
                                    .font(.headline)
                                if let description = model.description {
                                    Text(description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                HStack {
                                    if let contextLength = model.contextLength {
                                        Text("コンテキスト: \(contextLength)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    if let pricing = model.pricing {
                                        if let prompt = pricing.prompt {
                                            Text("入力: $\(prompt)")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        if let completion = pricing.completion {
                                            Text("出力: $\(completion)")
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
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.selectModel(model)
                        }
                    }
                }
            }
            .navigationTitle("モデル選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}