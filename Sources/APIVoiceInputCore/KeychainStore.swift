import Foundation
import Security

public enum KeychainStoreError: Error, Equatable, Sendable {
    case encodingFailed
    case unexpectedStatus(OSStatus)
}

public final class KeychainStore: Sendable {
    private let service: String

    public init(service: String = "com.yoshiki.APIVoiceInput") {
        self.service = service
    }

    public func saveAPIKey(_ value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainStoreError.encodingFailed
        }
        try deleteAPIKey(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }

    public func loadAPIKey(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
        guard let data = item as? Data else {
            throw KeychainStoreError.encodingFailed
        }
        return String(data: data, encoding: .utf8)
    }

    public func deleteAPIKey(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }
}
