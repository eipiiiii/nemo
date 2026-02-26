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
        // 空文字では Keychain を上書きしない
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("⚠️ [Settings] saveApiKey スキップ: apiKey が空")
            return
        }
        do {
            try keychain.save(apiKey, forKey: apiKeyKeychainKey)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveCustomPrompt() {
        UserDefaults.standard.set(customPrompt, forKey: customPromptKey)
    }

    func loadSettings() {
        apiKey = keychain.load(forKey: apiKeyKeychainKey) ?? ""
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
                let models = try await service.getModels(apiKey: apiKey)
                self.models = models
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isLoading = false
        }
    }
}
