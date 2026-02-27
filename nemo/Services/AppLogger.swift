import Foundation
import OSLog

/// アプリ全体で使用するロガー定義
/// Xcode Console で subsystem / category でフィルタリング可能
///
/// `nonisolated` を付けることで Swift 6 の actor isolation 警告を回避。
/// `Logger` は `Sendable` なので nonisolatedにしても安全。
enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.nemo"

    /// ネットワーク通信のログ
    nonisolated(unsafe) static let network = Logger(subsystem: subsystem, category: "Network")

    /// tool use ループのログ
    nonisolated(unsafe) static let tool = Logger(subsystem: subsystem, category: "Tool")

    /// Keychain 操作のログ
    nonisolated(unsafe) static let keychain = Logger(subsystem: subsystem, category: "Keychain")

    /// ChatViewModel のログ
    nonisolated(unsafe) static let chat = Logger(subsystem: subsystem, category: "Chat")

    /// SettingsViewModel のログ
    nonisolated(unsafe) static let settings = Logger(subsystem: subsystem, category: "Settings")

    /// ストリーミングのログ
    nonisolated(unsafe) static let streaming = Logger(subsystem: subsystem, category: "Streaming")
}
