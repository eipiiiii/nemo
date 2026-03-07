//
//  nemoApp.swift
//  nemo
//
//  Created by Eisuke Hayashi on 2024/01/01.
//

import SwiftUI
import SwiftData

@main
struct nemoApp: App {
    @StateObject private var serverManager = PythonServerManager.shared
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Conversation.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(serverManager)
        }
        .modelContainer(sharedModelContainer)
    }
    
    init() {
        // サンドボックス環境では NSHomeDirectory() が実際のホームを返さないため、
        // 絶対パスを UserDefaults で明示的に指定
        UserDefaults.standard.set(
            "/Users/hayashieisuke/Projects/swift/nemo/nemo-agent",
            forKey: "NemoAgentPath"
        )
        
        // アプリ起動時にPythonサーバーを起動
        Task { @MainActor in
            await PythonServerManager.shared.startServer()
        }
        
        // アプリ終了時のクリーンアップ
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                PythonServerManager.shared.stopServer()
            }
        }
    }
}
