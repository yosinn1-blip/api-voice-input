import Foundation

public struct VoiceInputResult: Equatable, Sendable {
    public let rawTranscript: String
    public let finalText: String

    public init(rawTranscript: String, finalText: String) {
        self.rawTranscript = rawTranscript
        self.finalText = finalText
    }
}

public final class VoiceInputPipeline: Sendable {
    private let transcriptionProvider: any TranscriptionProvider
    private let cleanupProvider: any CleanupProvider

    public init(transcriptionProvider: any TranscriptionProvider, cleanupProvider: any CleanupProvider) {
        self.transcriptionProvider = transcriptionProvider
        self.cleanupProvider = cleanupProvider
    }

    public func run(audioFileURL: URL, profile: VoiceProfile) async throws -> VoiceInputResult {
        let transcript = try await transcriptionProvider
            .transcribe(audioFileURL: audioFileURL, languageHint: profile.sttLanguageHint)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard transcript.isEmpty == false else {
            throw VoiceInputError.emptyTranscript
        }

        let cleaned = try await cleanupProvider
            .clean(transcript: transcript, prompt: profile.cleanupPrompt)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.isEmpty == false else {
            throw VoiceInputError.emptyCleanedText
        }

        return VoiceInputResult(rawTranscript: transcript, finalText: cleaned)
    }
}
