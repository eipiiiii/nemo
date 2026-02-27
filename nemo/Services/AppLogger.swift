import Foundation
import OSLog

/// アプリ全体で使用するロガー定義
/// Xcode Console で subsystem / category でフィルタリング可能
enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.nemo"

    /// ネットワーク通信のログ
    static let network = Logger(subsystem: subsystem, category: "Network")

    /// tool use ループのログ
    static let tool = Logger(subsystem: subsystem, category: "Tool")

    /// Keychain 操作のログ
    static let keychain = Logger(subsystem: subsystem, category: "Keychain")

    /// ChatViewModel のログ
    static let chat = Logger(subsystem: subsystem, category: "Chat")

    /// SettingsViewModel のログ
    static let settings = Logger(subsystem: subsystem, category: "Settings")

    /// ストリーミングのログ
    static let streaming = Logger(subsystem: subsystem, category: "Streaming")
}
