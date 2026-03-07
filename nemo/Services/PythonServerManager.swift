//
//  PythonServerManager.swift
//  nemo
//
//  Created on 2026-03-07.
//

import Foundation
import Combine
import os.log

/// Manages the Python agent server process lifecycle
@MainActor
final class PythonServerManager: ObservableObject {
    static let shared = PythonServerManager()
    
    @Published private(set) var isRunning = false
    @Published private(set) var serverURL = "http://localhost:8000"
    
    private var serverProcess: Process?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "nemo", category: "PythonServer")
    private let keychain = KeychainService.shared
    private let apiKeyKeychainKey = "openrouter_api_key"
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Start the Python server
    func startServer() async {
        guard !isRunning else {
            logger.info("Server already running")
            return
        }
        
        logger.info("Starting Python agent server...")
        
        do {
            let pythonPath = try findPythonPath()
            let projectPath = try getProjectPath()
            
            logger.info("Python path: \(pythonPath)")
            logger.info("Project path: \(projectPath)")
            
            let process = Process()
            
            // サンドボックス対応: /bin/bash 経由で Python を起動
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.currentDirectoryURL = URL(fileURLWithPath: projectPath)
            
            // bash スクリプトとして実行
            let command = """
            cd "\(projectPath)" && \
            "\(pythonPath)" -m uvicorn src.api.main:app \
                --host 127.0.0.1 \
                --port 8000 \
                --log-level info
            """
            
            process.arguments = ["-c", command]
            
            // KeychainからAPIキーを取得して環境変数として渡す
            process.environment = buildEnvironment()
            
            logger.info("🚀 Launching server with command: \(command)")
            
            setupProcessOutput(process)
            
            process.terminationHandler = { [weak self] process in
                Task { @MainActor in
                    self?.logger.info("Server process terminated with status: \(process.terminationStatus)")
                    self?.isRunning = false
                }
            }
            
            try process.run()
            self.serverProcess = process
            
            try await waitForServerReady()
            
            isRunning = true
            logger.info("Python agent server started successfully")
            
        } catch {
            logger.error("Failed to start server: \(error.localizedDescription)")
            isRunning = false
        }
    }
    
    /// Stop the Python server
    func stopServer() {
        guard let process = serverProcess, process.isRunning else { return }
        
        logger.info("Stopping Python agent server...")
        process.terminate()
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
            Task { @MainActor in
                if let process = self?.serverProcess, process.isRunning {
                    self?.logger.warning("Force killing server process")
                    process.interrupt()
                }
            }
        }
        
        serverProcess = nil
        isRunning = false
    }
    
    /// APIキーが変更されたとき（Settings保存後）にサーバーを再起動
    func restartWithUpdatedApiKey() async {
        guard let process = serverProcess, process.isRunning else { return }
        logger.info("API key updated, restarting server...")
        stopServer()
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒待機
        await startServer()
    }
    
    /// Check if server is healthy
    func checkHealth() async -> Bool {
        guard isRunning else { return false }
        let healthURL = URL(string: "\(serverURL)/health")!
        do {
            let (data, response) = try await URLSession.shared.data(from: healthURL)
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["status"] as? String == "healthy" {
                return true
            }
        } catch {
            logger.error("Health check failed: \(error.localizedDescription)")
        }
        return false
    }
    
    // MARK: - Private Methods
    
    /// KeychainのAPIキーを環境変数として構築する
    private func buildEnvironment() -> [String: String] {
        // 現在のシステム環境変数を引き継ぐ
        var env = ProcessInfo.processInfo.environment
        
        // KeychainからOpenRouter APIキーを取得して注入
        if let apiKey = keychain.load(forKey: apiKeyKeychainKey), !apiKey.isEmpty {
            env["OPENROUTER_API_KEY"] = apiKey
            logger.info("✅ OpenRouter API key injected from Keychain (\(apiKey.prefix(8))...)")
        } else {
            logger.warning("⚠️ OpenRouter API key not found in Keychain. Set it in Settings.")
        }
        
        return env
    }
    
    /// プロセスの標準出力/エラー出力をXcodeコンソールに表示
    private func setupProcessOutput(_ process: Process) {
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                Task { @MainActor in
                    self?.logger.info("[Server] \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
            }
        }
        
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                Task { @MainActor in
                    self?.logger.error("[Server Error] \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
            }
        }
    }
    
    /// サーバーが起動するまでヘルスチェックでポーリング
    private func waitForServerReady(maxAttempts: Int = 30) async throws {
        let healthURL = URL(string: "\(serverURL)/health")!
        for attempt in 1...maxAttempts {
            do {
                let (_, response) = try await URLSession.shared.data(from: healthURL)
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 200 {
                    logger.info("Server is ready after \(attempt) attempt(s)")
                    return
                }
            } catch { /* サーバー未起動、リトライ */ }
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1秒待機
        }
        throw NSError(
            domain: "PythonServerManager",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Server failed to start within timeout"]
        )
    }
    
    /// Python実行ファイルを検索
    private func findPythonPath() throws -> String {
        // 1. Poetry仮想環境のPythonを最優先
        let projectPath = (try? getProjectPath()) ?? ""
        let poetryVenvPython = "\(projectPath)/.venv/bin/python3"
        if FileManager.default.fileExists(atPath: poetryVenvPython) {
            // シンボリックリンクを解決
            let resolved = (poetryVenvPython as NSString).resolvingSymlinksInPath
            logger.info("✅ Using Poetry venv Python: \(poetryVenvPython) -> \(resolved)")
            return resolved
        }
        
        // 2. バージョン指定の Python を優先
        let versionedCandidates = [
            "/opt/homebrew/bin/python3.12",
            "/opt/homebrew/bin/python3.11",
            "/usr/local/bin/python3.12",
            "/usr/local/bin/python3.11",
        ]
        for path in versionedCandidates {
            if FileManager.default.fileExists(atPath: path) {
                let resolved = (path as NSString).resolvingSymlinksInPath
                logger.info("✅ Using versioned Python: \(path) -> \(resolved)")
                return resolved
            }
        }
        
        // 3. 汎用的な python3
        let genericCandidates = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]
        for path in genericCandidates {
            if FileManager.default.fileExists(atPath: path) {
                let realPath = (path as NSString).resolvingSymlinksInPath
                if FileManager.default.fileExists(atPath: realPath) {
                    logger.info("✅ Using generic Python: \(path) -> \(realPath)")
                    return realPath
                }
            }
        }
        
        throw NSError(
            domain: "PythonServerManager",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey:
                "Python 3.11+ not found. Install via: brew install python@3.12"]
        )
    }
    
    /// nemo-agentのプロジェクトパスを解決
    private func getProjectPath() throws -> String {
        let home = NSHomeDirectory()
        let fm = FileManager.default
        
        // 1. UserDefaults を最優先（サンドボックス対応）
        if let override = UserDefaults.standard.string(forKey: "NemoAgentPath"),
           !override.isEmpty,
           fm.fileExists(atPath: override) {
            logger.info("✅ nemo-agent found via UserDefaults: \(override)")
            return override
        }
        
        // 2. DerivedData の WorkspaceSettings
        if let srcRoot = derivedDataSourceRoot() {
            let candidate = (srcRoot as NSString).appendingPathComponent("nemo-agent")
            if fm.fileExists(atPath: candidate) {
                logger.info("✅ nemo-agent found via DerivedData: \(candidate)")
                return candidate
            }
        }
        
        // 3. ホームディレクトリ配下を探索
        let searchPaths = [
            home + "/Projects/swift/nemo/nemo-agent",
            home + "/Developer/nemo/nemo-agent",
            home + "/Documents/nemo/nemo-agent",
            home + "/Desktop/nemo/nemo-agent",
            home + "/Projects/nemo/nemo-agent",
            home + "/nemo/nemo-agent",
        ]
        
        for candidate in searchPaths {
            let resolved = (candidate as NSString).standardizingPath
            if fm.fileExists(atPath: resolved) {
                logger.info("✅ nemo-agent found at: \(resolved)")
                return resolved
            }
        }
        
        throw NSError(
            domain: "PythonServerManager",
            code: -3,
            userInfo: [NSLocalizedDescriptionKey:
                "nemo-agent directory not found. Searched paths: \(searchPaths.joined(separator: ", "))"]
        )
    }
    
    /// DerivedData の info.plist から元のソースディレクトリを取得
    private func derivedDataSourceRoot() -> String? {
        let bundlePath = Bundle.main.bundlePath as NSString
        var path = bundlePath as String
        for _ in 0..<4 {
            path = (path as NSString).deletingLastPathComponent
        }
        let settingsPath = (path as NSString).appendingPathComponent("info.plist")
        guard let info = NSDictionary(contentsOfFile: settingsPath),
              let workspacePath = info["WorkspacePath"] as? String else {
            return nil
        }
        return (workspacePath as NSString).deletingLastPathComponent
    }
}
