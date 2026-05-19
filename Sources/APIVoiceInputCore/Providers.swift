import Foundation

public enum VoiceInputError: Error, Equatable, LocalizedError, Sendable {
    case emptyTranscript
    case emptyCleanedText
    case providerRateLimited(String)
    case providerFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyTranscript:
            return "音声認識結果が空でした。"
        case .emptyCleanedText:
            return "清書結果が空でした。"
        case .providerRateLimited(let provider):
            return "\(provider) の無料枠またはレート制限に達しました。"
        case .providerFailed(let message):
            return message
        }
    }
}

public protocol TranscriptionProvider: Sendable {
    var id: String { get }
    func transcribe(audioFileURL: URL, languageHint: String) async throws -> String
}

public protocol CleanupProvider: Sendable {
    var id: String { get }
    func clean(transcript: String, prompt: String) async throws -> String
}

public struct NoCleanupProvider: CleanupProvider {
    public let id = "none"

    public init() {}

    public func clean(transcript: String, prompt: String) async throws -> String {
        transcript
    }
}
