import APIVoiceInputCore
import Foundation

struct APIKeyStore {
    static let secretsFileURL = AppSettings.applicationSupportDirectory.appendingPathComponent("secrets.env")
    private static let keychain = KeychainStore(service: AppSettings.bundleIdentifier)

    static func loadGroqAPIKey() -> String? {
        let fileKey = loadKeyFromSecretsFile(name: "GROQ_API_KEY")
        if let normalizedFileKey = GroqAPIKeySetup.normalizedAPIKey(fileKey ?? "") {
            DebugLog.write("loaded Groq API key from secrets file")
            return normalizedFileKey
        }
        if GroqAPIKeySetup.shouldReadKeychainSecret(secretsFileKey: fileKey) {
            if let keychainKey = try? keychain.loadAPIKey(account: AppSettings.groqKeyAccount),
               let normalizedKey = GroqAPIKeySetup.normalizedAPIKey(keychainKey) {
                DebugLog.write("loaded Groq API key from Keychain")
                return normalizedKey
            }
        }
        DebugLog.write("Groq API key not found")
        return nil
    }

    static func hasGroqAPIKey() -> Bool {
        if let fileKey = loadKeyFromSecretsFile(name: "GROQ_API_KEY"),
           GroqAPIKeySetup.normalizedAPIKey(fileKey) != nil {
            return true
        }
        return (try? keychain.containsAPIKey(account: AppSettings.groqKeyAccount)) ?? false
    }

    static func saveGroqAPIKey(_ rawValue: String) throws {
        guard let normalizedKey = GroqAPIKeySetup.normalizedAPIKey(rawValue) else {
            throw APIKeyStoreError.emptyKey
        }
        try keychain.saveAPIKey(normalizedKey, account: AppSettings.groqKeyAccount)
        DebugLog.write("saved Groq API key to Keychain")
    }

    private static func loadKeyFromSecretsFile(name: String) -> String? {
        guard let contents = try? String(contentsOf: secretsFileURL, encoding: .utf8) else {
            return nil
        }
        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            guard parts[0].trimmingCharacters(in: .whitespacesAndNewlines) == name else { continue }
            return parts[1]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return nil
    }
}

enum APIKeyStoreError: LocalizedError {
    case emptyKey

    var errorDescription: String? {
        switch self {
        case .emptyKey:
            "APIキーが空です"
        }
    }
}
