import Combine
import Foundation
import os

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var apiKey = ""
    @Published var customPrompt = ""
    @Published var models: [Model] = []
    @Published var selectedModelId = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    // Google CSE
    @Published var googleCseApiKey = ""
    @Published var googleCseCx = ""

    // SearXNG
    @Published var searxngUrl = "http://localhost:8080"

    private let service = OpenRouterService()
    private let keychain = KeychainService.shared
    private let apiKeyKeychainKey = "openrouter_api_key"
    private let customPromptKey = "custom_prompt"
    private let selectedModelKey = "selected_model_id"
    private let googleCseApiKeyKeychainKey = "google_cse_api_key"
    private let googleCseCxKeychainKey = "google_cse_cx"
    private let searxngUrlKey = "searxng_url"

    init() {
        AppLogger.settings.info("⚙️ SettingsViewModel init")
        loadSettings()
    }

    func saveApiKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
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
    }

    func saveGoogleCseApiKey() {
        let trimmed = googleCseApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        googleCseApiKey = trimmed
        do {
            try keychain.save(trimmed, forKey: googleCseApiKeyKeychainKey)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveGoogleCseCx() {
        let trimmed = googleCseCx.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        googleCseCx = trimmed
        do {
            try keychain.save(trimmed, forKey: googleCseCxKeychainKey)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveSearxngUrl() {
        let trimmed = searxngUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        searxngUrl = trimmed
        UserDefaults.standard.set(trimmed, forKey: searxngUrlKey)
        AppLogger.settings.info("✅ saveSearxngUrl: \(trimmed)")
    }

    func loadSettings() {
        apiKey = keychain.load(forKey: apiKeyKeychainKey) ?? ""
        customPrompt = UserDefaults.standard.string(forKey: customPromptKey) ?? ""
        selectedModelId = UserDefaults.standard.string(forKey: selectedModelKey) ?? ""
        googleCseApiKey = keychain.load(forKey: googleCseApiKeyKeychainKey) ?? ""
        googleCseCx = keychain.load(forKey: googleCseCxKeychainKey) ?? ""
        searxngUrl = UserDefaults.standard.string(forKey: searxngUrlKey) ?? "http://localhost:8080"
        AppLogger.settings.info("⚙️ loadSettings 完了")
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
