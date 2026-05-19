import Foundation

public enum PasteMode: String, Codable, Equatable, Sendable {
    case pasteOnly
    case pasteThenEnter
}

public struct VoiceProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var displayName: String
    public var sttLanguageHint: String
    public var transcriptionProviderID: String
    public var cleanupProviderID: String
    public var cleanupPrompt: String
    public var pasteMode: PasteMode

    public init(
        id: UUID = UUID(),
        displayName: String,
        sttLanguageHint: String,
        transcriptionProviderID: String,
        cleanupProviderID: String,
        cleanupPrompt: String,
        pasteMode: PasteMode
    ) {
        self.id = id
        self.displayName = displayName
        self.sttLanguageHint = sttLanguageHint
        self.transcriptionProviderID = transcriptionProviderID
        self.cleanupProviderID = cleanupProviderID
        self.cleanupPrompt = cleanupPrompt
        self.pasteMode = pasteMode
    }

    public static let defaultJapanese = VoiceProfile(
        displayName: "日本語 default",
        sttLanguageHint: "ja",
        transcriptionProviderID: "groq-whisper-large-v3-turbo",
        cleanupProviderID: "none",
        cleanupPrompt: "日本語として自然に整え、意味を変えず、余計な説明を追加しないでください。",
        pasteMode: .pasteOnly
    )
}
