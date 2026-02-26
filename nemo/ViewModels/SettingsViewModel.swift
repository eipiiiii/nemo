//
//  SettingsViewModel.swift
//  nemo
//
//  Created by 林栄介 on 2026/01/31.
//

import Foundation
import Combine

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var apiKey = ""
    @Published var customPrompt = ""
    @Published var models: [Model] = []
    @Published var selectedModelId = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service = OpenRouterService()
    private let keychain = KeychainService.shared
    private let apiKeyKeychainKey = "openrouter_api_key"
    private let customPromptKey = "custom_prompt"
    private let selectedModelKey = "selected_model_id"

    init() {
        loadSettings()
    }

    func saveApiKey() {
        do {
            try keychain.save(apiKey, forKey: apiKeyKeychainKey)
            print("✅ [Settings] Keychain 保存成功: '\(apiKey.prefix(8))...' (文字数: \(apiKey.count))")
        } catch {
            print("❌ [Settings] Keychain 保存失敗: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    func saveCustomPrompt() {
        UserDefaults.standard.set(customPrompt, forKey: customPromptKey)
    }

    func loadSettings() {
        let loaded = keychain.load(forKey: apiKeyKeychainKey)
        print("🔑 [Settings] Keychain load: \(loaded.map { "'\($0.prefix(8))...' (文字数: \($0.count))" } ?? "nil")")
        apiKey = loaded ?? ""
        customPrompt = UserDefaults.standard.string(forKey: customPromptKey) ?? ""
        selectedModelId = UserDefaults.standard.string(forKey: selectedModelKey) ?? ""
        print("📦 [Settings] apiKey.isEmpty = \(apiKey.isEmpty)")
    }

    func selectModel(_ model: Model) {
        selectedModelId = model.id
        UserDefaults.standard.set(selectedModelId, forKey: selectedModelKey)
    }

    func fetchModels() {
        guard !apiKey.isEmpty else {
            print("⚠️ [Settings] fetchModels スキップ: apiKey が空")
            errorMessage = "APIキーを入力してください"
            return
        }
        print("🚀 [Settings] fetchModels 開始: apiKey='\(apiKey.prefix(8))...'")

        isLoading = true
        errorMessage = nil

        Task {
            do {
                let models = try await service.getModels(apiKey: apiKey)
                self.models = models
                print("✅ [Settings] モデル取得成功: \(models.count)件")
            } catch {
                print("❌ [Settings] モデル取得失敗: \(error.localizedDescription)")
                self.errorMessage = error.localizedDescription
            }
            self.isLoading = false
        }
    }
}
