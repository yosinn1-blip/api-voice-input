import Foundation

public enum GroqAPIKeySetup {
    public static let apiKeyURL = URL(string: "https://console.groq.com/keys")!
    public static let setupGuideURL = URL(string: "https://api-voice-input.vercel.app/")!

    public static func normalizedAPIKey(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func shouldShowOnboarding(hasAPIKey: Bool, dismissed: Bool) -> Bool {
        hasAPIKey == false && dismissed == false
    }

    public static func shouldReadKeychainSecret(secretsFileKey: String?) -> Bool {
        normalizedAPIKey(secretsFileKey ?? "") == nil
    }
}
