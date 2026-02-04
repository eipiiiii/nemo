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
    @Published var systemPrompt = ""
    @Published var models: [Model] = []
    @Published var selectedModelId = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let service = OpenRouterService()
    private let apiKeyKey = "openrouter_api_key"
    private let systemPromptKey = "system_prompt"
    private let selectedModelKey = "selected_model_id"
    
    init() {
        loadSettings()
    }
    
    func saveApiKey() {
        UserDefaults.standard.set(apiKey, forKey: apiKeyKey)
    }
    
    func saveSystemPrompt() {
        UserDefaults.standard.set(systemPrompt, forKey: systemPromptKey)
    }
    
    func loadSettings() {
        apiKey = UserDefaults.standard.string(forKey: apiKeyKey) ?? ""
        systemPrompt = UserDefaults.standard.string(forKey: systemPromptKey) ?? "You are a helpful AI assistant."
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
