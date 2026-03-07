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
            ToolCallBlock.self
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
        .commands {
            // アプリケーション起動時にサーバーを自動起動
            CommandGroup(replacing: .appInfo) {
                Button("About nemo") {
                    // About window
                }
            }
        }
    }
    
    init() {
        // アプリ起動時にPythonサーバーを起動
        Task {
            await PythonServerManager.shared.startServer()
        }
        
        // アプリ終了時のクリーンアップ
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            PythonServerManager.shared.stopServer()
        }
    }
}
