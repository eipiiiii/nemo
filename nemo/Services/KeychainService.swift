//
//  KeychainService.swift
//  nemo
//

import Foundation
import Security

enum KeychainError: LocalizedError {
    case saveError(OSStatus)
    case loadError(OSStatus)
    case deleteError(OSStatus)
    case unexpectedData

    var errorDescription: String? {
        switch self {
        case .saveError(let status):
            return "Keychain への保存に失敗しました (status: \(status))"
        case .loadError(let status):
            return "Keychain からの読み込みに失敗しました (status: \(status))"
        case .deleteError(let status):
            return "Keychain からの削除に失敗しました (status: \(status))"
        case .unexpectedData:
            return "Keychain から予期しないデータが返されました"
        }
    }
}

final class KeychainService: Sendable {
    static let shared = KeychainService()
    private init() {}

    // MARK: - Save

    func save(_ value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else { return }

        // 既存のアイテムを削除してから新規保存
        try? delete(forKey: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveError(status)
        }
    }

    // MARK: - Load

    func load(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }

        return value
    }

    // MARK: - Delete

    func delete(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        // errSecItemNotFound は「存在しなかっただけ」なので無視する
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteError(status)
        }
    }
}
