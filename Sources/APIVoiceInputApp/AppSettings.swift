import Foundation

struct AppSettings {
    static let bundleIdentifier = "com.yoshiki.APIVoiceInput"
    static let appName = "API音声ソフト"
    static let groqKeyAccount = "groq-api-key"
    static let geminiKeyAccount = "gemini-api-key"

    static var applicationSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("APIVoiceInput", isDirectory: true)
    }
}
