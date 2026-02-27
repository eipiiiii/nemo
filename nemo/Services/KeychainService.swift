import Foundation
import Security

final class KeychainService {
    static let shared = KeychainService()
    private init() {}

    func save(_ value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else {
            AppLogger.keychain.error("❌ save: UTF-8 変換失敗 key=\(key)")
            throw KeychainError.encodingFailed
        }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
        ]
        SecItemDelete(query as CFDictionary)
        let attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecValueData: data,
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecSuccess {
            AppLogger.keychain.info("✅ save: 成功 key=\(key) 文字数=\(value.count)")
        } else {
            AppLogger.keychain.error("❌ save: 失敗 key=\(key) status=\(status)")
            throw KeychainError.saveFailed(status)
        }
    }

    func load(forKey key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess,
           let data = result as? Data,
           let value = String(data: data, encoding: .utf8)
        {
            AppLogger.keychain.info("✅ load: 成功 key=\(key) 文字数=\(value.count)")
            return value
        } else {
            AppLogger.keychain.warning("⚠️ load: 値なし key=\(key) status=\(status)")
            return nil
        }
    }

    func delete(forKey key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        AppLogger.keychain.info("🗑️ delete: key=\(key) status=\(status)")
    }
}

enum KeychainError: LocalizedError {
    case encodingFailed
    case saveFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Keychain: 文字列のエンコードに失敗しました"
        case .saveFailed(let status):
            return "Keychain: 保存に失敗しました (status: \(status))"
        }
    }
}
