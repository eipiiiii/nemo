//
//  PythonServerManager.swift
//  nemo
//
//  Created on 2026-03-07.
//

import Foundation
import os.log

/// Manages the Python agent server process lifecycle
@MainActor
final class PythonServerManager: ObservableObject {
    static let shared = PythonServerManager()
    
    @Published private(set) var isRunning = false
    @Published private(set) var serverURL = "http://localhost:8000"
    
    private var serverProcess: Process?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "nemo", category: "PythonServer")
    
    private init() {}
    
    /// Start the Python server
    func startServer() async {
        guard !isRunning else {
            logger.info("Server already running")
            return
        }
        
        logger.info("Starting Python agent server...")
        
        do {
            // Try to find Python installation
            let pythonPath = try findPythonPath()
            let projectPath = try getProjectPath()
            
            logger.info("Python path: \(pythonPath)")
            logger.info("Project path: \(projectPath)")
            
            // Create process
            let process = Process()
            process.executableURL = URL(fileURLWithPath: pythonPath)
            process.currentDirectoryURL = URL(fileURLWithPath: projectPath)
            
            // Arguments to run uvicorn
            process.arguments = [
                "-m", "uvicorn",
                "src.api.main:app",
                "--host", "127.0.0.1",
                "--port", "8000",
                "--log-level", "info"
            ]
            
            // Setup pipes for output
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            // Log output
            outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                    self?.logger.info("[Server] \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
            }
            
            errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                    self?.logger.error("[Server Error] \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
            }
            
            // Set termination handler
            process.terminationHandler = { [weak self] process in
                Task { @MainActor in
                    self?.logger.info("Server process terminated with status: \(process.terminationStatus)")
                    self?.isRunning = false
                }
            }
            
            // Start the process
            try process.run()
            self.serverProcess = process
            
            // Wait for server to be ready
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
        guard let process = serverProcess, process.isRunning else {
            logger.info("No server process to stop")
            return
        }
        
        logger.info("Stopping Python agent server...")
        process.terminate()
        
        // Wait for graceful shutdown
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
            if let process = self?.serverProcess, process.isRunning {
                self?.logger.warning("Force killing server process")
                process.interrupt()
            }
        }
        
        serverProcess = nil
        isRunning = false
        logger.info("Python agent server stopped")
    }
    
    /// Wait for server to be ready by checking health endpoint
    private func waitForServerReady(maxAttempts: Int = 30) async throws {
        let healthURL = URL(string: "\(serverURL)/health")!
        
        for attempt in 1...maxAttempts {
            do {
                let (_, response) = try await URLSession.shared.data(from: healthURL)
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 200 {
                    logger.info("Server is ready after \(attempt) attempts")
                    return
                }
            } catch {
                // Server not ready yet, wait and retry
            }
            
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        }
        
        throw NSError(
            domain: "PythonServerManager",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Server failed to start within timeout"]
        )
    }
    
    /// Find Python executable path
    private func findPythonPath() throws -> String {
        // Try common Python paths
        let candidates = [
            "/usr/local/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/bin/python3",
            "python3" // Will search in PATH
        ]
        
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        // Try using 'which' command
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
            userInfo: [NSLocalizedDescriptionKey: "Python3 not found. Please install Python 3.11 or later."]
        )
    }
    
    /// Get nemo-agent project path
    private func getProjectPath() throws -> String {
        // In development: go up from bundle to project root
        let bundlePath = Bundle.main.bundlePath
        let projectRoot = (bundlePath as NSString)
            .deletingLastPathComponent
            .deletingLastPathComponent
            .deletingLastPathComponent // Remove Build/Products/Debug from Xcode build path
        
        let agentPath = (projectRoot as NSString).appendingPathComponent("nemo-agent")
        
        if FileManager.default.fileExists(atPath: agentPath) {
            return agentPath
        }
        
        throw NSError(
            domain: "PythonServerManager",
            code: -3,
            userInfo: [NSLocalizedDescriptionKey: "nemo-agent directory not found at: \(agentPath)"]
        )
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
}
