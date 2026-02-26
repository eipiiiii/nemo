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
            print("✅ [Keychain] 保存成功: \(apiKey.prefix(8))...")
        } catch {
            print("❌ [Keychain] 保存失敗: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    func saveCustomPrompt() {
        UserDefaults.standard.set(customPrompt, forKey: customPromptKey)
    }

    func loadSettings() {
        let loaded = keychain.load(forKey: apiKeyKeychainKey)
        print("🔑 [Keychain] load 結果: \(loaded.map { String($0.prefix(8)) + "..." } ?? "nil")")
        apiKey = loaded ?? ""
        customPrompt = UserDefaults.standard.string(forKey: customPromptKey) ?? ""
        selectedModelId = UserDefaults.standard.string(forKey: selectedModelKey) ?? ""
    }

    func selectModel(_ model: Model) {
        selectedModelId = model.id
        UserDefaults.standard.set(selectedModelId, forKey: selectedModelKey)
    }

    func fetchModels() {
        guard !apiKey.isEmpty else {
            errorMessage = "APIキーを入力してください"
            return
        }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                let models = try await service.getModels()
                self.models = models
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isLoading = false
        }
    }
}
