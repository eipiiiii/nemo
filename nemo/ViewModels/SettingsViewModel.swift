//
//  SettingsViewModel.swift
//  nemo
//
//  Created by 林栄介 on 2026/01/31.
//

import Foundation
import Combine
import os

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
        AppLogger.settings.info("⚙️ SettingsViewModel init")
        loadSettings()
    }

    func saveApiKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            AppLogger.settings.warning("⚠️ saveApiKey スキップ: 空文字")
            return
        }
        apiKey = trimmed
        do {
            try keychain.save(trimmed, forKey: apiKeyKeychainKey)
            AppLogger.settings.info("✅ saveApiKey: 保存完了 文字数=\(trimmed.count)")
        } catch {
            AppLogger.settings.error("❌ saveApiKey エラー: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    func saveCustomPrompt() {
        UserDefaults.standard.set(customPrompt, forKey: customPromptKey)
        AppLogger.settings.info("✅ saveCustomPrompt: \(self.customPrompt.count)文字")
    }

    func loadSettings() {
        apiKey = keychain.load(forKey: apiKeyKeychainKey) ?? ""
        customPrompt = UserDefaults.standard.string(forKey: customPromptKey) ?? ""
        selectedModelId = UserDefaults.standard.string(forKey: selectedModelKey) ?? ""
        AppLogger.settings.info("⚙️ loadSettings: apiKey文字数=\(self.apiKey.count) model=\(self.selectedModelId)")
    }

    func selectModel(_ model: Model) {
        selectedModelId = model.id
        UserDefaults.standard.set(selectedModelId, forKey: selectedModelKey)
        AppLogger.settings.info("✅ selectModel: \(model.id)")
    }

    func fetchModels() {
        guard !apiKey.isEmpty else {
            AppLogger.settings.warning("⚠️ fetchModels スキップ: APIキーなし")
            errorMessage = "APIキーを入力してください"
            return
        }
        AppLogger.settings.info("📊 fetchModels 開始")
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let models = try await service.getModels(apiKey: apiKey)
                self.models = models
                AppLogger.settings.info("✅ fetchModels 完了: \(models.count)件")
            } catch {
                AppLogger.settings.error("❌ fetchModels エラー: \(error)")
                self.errorMessage = error.localizedDescription
            }
            self.isLoading = false
        }
    }
}
