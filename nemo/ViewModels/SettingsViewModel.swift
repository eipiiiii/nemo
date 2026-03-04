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
    @Published var searxngUrl = "http://localhost:8080"
    @Published var searxngServerStatus: ServerStatus = .unknown

    enum ServerStatus {
        case unknown
        case checking
        case online
        case offline
    }

    private let service = OpenRouterService()
    private let keychain = KeychainService.shared
    private let apiKeyKeychainKey = "openrouter_api_key"
    private let customPromptKey = "custom_prompt"
    private let selectedModelKey = "selected_model_id"
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

    func saveSearxngUrl() {
        let trimmed = searxngUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        searxngUrl = trimmed
        UserDefaults.standard.set(trimmed, forKey: searxngUrlKey)
        AppLogger.settings.info("✅ saveSearxngUrl: \(trimmed)")
        checkSearxngServerStatus()
    }

    func loadSettings() {
        apiKey = keychain.load(forKey: apiKeyKeychainKey) ?? ""
        customPrompt = UserDefaults.standard.string(forKey: customPromptKey) ?? ""
        selectedModelId = UserDefaults.standard.string(forKey: selectedModelKey) ?? ""
        searxngUrl = UserDefaults.standard.string(forKey: searxngUrlKey) ?? "http://localhost:8080"
        AppLogger.settings.info("⚙️ loadSettings 完了")
        checkSearxngServerStatus()
    }
    
    func checkSearxngServerStatus() {
        guard let url = URL(string: searxngUrl) else {
            searxngServerStatus = .offline
            return
        }
        
        searxngServerStatus = .checking
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 3.0
        
        Task {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode < 500 {
                    self.searxngServerStatus = .online
                } else {
                    self.searxngServerStatus = .offline
                }
            } catch {
                self.searxngServerStatus = .offline
            }
        }
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
