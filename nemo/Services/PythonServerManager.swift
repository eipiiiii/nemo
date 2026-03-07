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
            process.executableURL = URL(fileURLWithPath: pythonPath)
            process.currentDirectoryURL = URL(fileURLWithPath: projectPath)
            process.arguments = [
                "-m", "uvicorn",
                "src.api.main:app",
                "--host", "127.0.0.1",
                "--port", "8000",
                "--log-level", "info"
            ]
            
            // KeychainからAPIキーを取得して環境変数として渡す
            process.environment = buildEnvironment()
            
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
        // Poetry仮想環境のPythonを優先
        let projectPath = (try? getProjectPath()) ?? ""
        let poetryVenvPython = "\(projectPath)/.venv/bin/python3"
        if FileManager.default.fileExists(atPath: poetryVenvPython) {
            return poetryVenvPython
        }
        
        // システムのPythonを検索
        let candidates = [
            "/opt/homebrew/bin/python3",  // Apple Silicon Homebrew
            "/usr/local/bin/python3",      // Intel Homebrew
            "/usr/bin/python3",            // macOS system
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        // whichコマンドで検索
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["python3"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            return path
        }
        
        throw NSError(
            domain: "PythonServerManager",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: "Python3 not found. Run ./setup.sh in nemo-agent directory."]
        )
    }
    
    /// nemo-agentのプロジェクトパスを解決
    ///
    /// 問題: Xcodeビルド時、Bundle.main.bundlePath は DerivedData 内を指す
    /// (~/.../DerivedData/nemo-xxxx/Build/Products/Debug/nemo.app)
    /// そこからの相対パスではリポジトリルートに届かない。
    /// 解決策: DerivedData の WorkspaceSettings を参照するか、
    /// ホームディレクトリ配下の一般的な開発ディレクトリを探索する。
    private func getProjectPath() throws -> String {
        let home = NSHomeDirectory()
        let fm = FileManager.default
        
        // 1. DerivedData の WorkspaceSettings.xcsettings から SRCROOT を取得
        if let srcRoot = derivedDataSourceRoot() {
            let candidate = (srcRoot as NSString).appendingPathComponent("nemo-agent")
            if fm.fileExists(atPath: candidate) {
                logger.info("✅ nemo-agent found via DerivedData SRCROOT: \(candidate)")
                return candidate
            }
        }
        
        // 2. ホームディレクトリ配下の一般的な開発ディレクトリを探索
        let searchRoots = [
            home + "/Developer",
            home + "/Documents",
            home + "/Desktop",
            home + "/Projects",
            home,
        ]
        
        for root in searchRoots {
            let candidate = (root as NSString).appendingPathComponent("nemo/nemo-agent")
            let resolved = (candidate as NSString).standardizingPath
            if fm.fileExists(atPath: resolved) {
                logger.info("✅ nemo-agent found at: \(resolved)")
                return resolved
            }
        }
        
        // 3. UserDefaults による手動オーバーライド（デバッグ用）
        if let override = UserDefaults.standard.string(forKey: "NemoAgentPath"),
           !override.isEmpty,
           fm.fileExists(atPath: override) {
            logger.info("✅ nemo-agent found via UserDefaults override: \(override)")
            return override
        }
        
        throw NSError(
            domain: "PythonServerManager",
            code: -3,
            userInfo: [NSLocalizedDescriptionKey:
                "nemo-agent directory not found. " +
                "Searched in ~/Developer, ~/Documents, ~/Desktop, ~/Projects. " +
                "Override with: UserDefaults.standard.set('/path/to/nemo/nemo-agent', forKey: 'NemoAgentPath')"]
        )
    }
    
    /// DerivedData の WorkspaceSettings から元のソースディレクトリを取得
    private func derivedDataSourceRoot() -> String? {
        let bundlePath = Bundle.main.bundlePath as NSString
        
        // DerivedData/nemo-xxxx/ を目指して上に辿る
        // nemo.app -> Debug -> Products -> Build -> DerivedData/nemo-xxxx
        var path = bundlePath as String
        for _ in 0..<4 {
            path = (path as NSString).deletingLastPathComponent
        }
        
        // WorkspaceSettings.xcsettings を確認
        let settingsPath = (path as NSString)
            .appendingPathComponent("info.plist")
        
        guard let info = NSDictionary(contentsOfFile: settingsPath),
              let workspacePath = info["WorkspacePath"] as? String else {
            return nil
        }
        
        // .xcworkspace または .xcodeproj の親ディレクトリがリポジトリルート
        return (workspacePath as NSString).deletingLastPathComponent
    }
}
