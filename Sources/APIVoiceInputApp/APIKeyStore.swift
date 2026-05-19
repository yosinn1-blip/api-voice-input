import Foundation

struct APIKeyStore {
    static let secretsFileURL = AppSettings.applicationSupportDirectory.appendingPathComponent("secrets.env")

    static func loadGroqAPIKey() -> String? {
        if let fileKey = loadKeyFromSecretsFile(name: "GROQ_API_KEY"), fileKey.isEmpty == false {
            DebugLog.write("loaded Groq API key from secrets file")
            return fileKey
        }
        DebugLog.write("Groq API key not found in secrets file")
        return nil
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
