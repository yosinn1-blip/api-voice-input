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
        let transcript = TranscriptHallucinationFilter.sanitize(try await transcriptionProvider
            .transcribe(audioFileURL: audioFileURL, languageHint: profile.sttLanguageHint)
            .trimmingCharacters(in: .whitespacesAndNewlines))
        guard transcript.isEmpty == false else {
            throw VoiceInputError.emptyTranscript
        }

        let cleaned = TranscriptHallucinationFilter.sanitize(try await cleanupProvider
            .clean(transcript: transcript, prompt: profile.cleanupPrompt)
            .trimmingCharacters(in: .whitespacesAndNewlines))
        guard cleaned.isEmpty == false else {
            throw VoiceInputError.emptyCleanedText
        }

        return VoiceInputResult(rawTranscript: transcript, finalText: cleaned)
    }
}

enum TranscriptHallucinationFilter {
    private static let thanksPhrases = ["ありがとうございました", "ありがとうございます"]
    // Longer phrases first so "API音声ソフト" wins over the shorter "音声ソフト" suffix.
    private static let appNamePhrases = ["API音声ソフト", "音声ソフト"]
    // Longer first so nested ご視聴 / ごちそう suffixes do not win over full closings.
    private static let viewingThanksPhrases = [
        "ご視聴ありがとうございましたです",
        "ご視聴ありがとうございました",
        "ご視聴ありがとうございます",
        "ごちそうさまでした",
        "ご視聴ありがとう",
        "ごちそうさま",
        "ごちしょう",
        "ごちそう",
        "ご視聴"
    ]
    private static let delimiterOnlyPhrases: Set<String> = ["ご視聴", "ごちそう"]
    private static let trailingPhrases = viewingThanksPhrases + thanksPhrases + appNamePhrases
    private static let terminalPunctuation = CharacterSet(charactersIn: "。！？!?.、, 　\t\n\r")

    /// Whisper can prefix or append stock phrases around an otherwise complete utterance,
    /// especially when the recording starts or ends in silence or the STT prompt mentions
    /// the app name. Preserve a standalone acknowledgement / app-name / viewing-thanks
    /// utterance; only remove the phrase when it is affixed to actual content.
    /// Trailing phrases are stripped repeatedly (longest-first). If that would empty the
    /// string, the original utterance is kept (the whole thing was a greeting).
    static func sanitize(_ text: String) -> String {
        var current = text
        while true {
            let next = removingTrailingHallucinations(from: removingLeadingViewingThanks(from: current))
            if next == current {
                break
            }
            current = next
        }
        let core = current.trimmingCharacters(in: terminalPunctuation.union(.whitespacesAndNewlines))
        // Whole utterance was greeting(s): keep original (including stacked closings).
        if core.isEmpty || trailingPhrases.contains(core) {
            return text
        }
        return current
    }

    static func removingAppendedThanks(from text: String) -> String {
        removingAppendedPhrase(from: text, phrases: thanksPhrases)
    }

    private static func removingTrailingHallucinations(from text: String) -> String {
        var current = text
        while true {
            let next = removingAppendedPhrase(from: current, phrases: trailingPhrases)
            if next == current {
                return current
            }
            current = next
        }
    }

    private static func removingAppendedPhrase(from text: String, phrases: [String]) -> String {
        let withoutTerminalPunctuation = text.trimmingCharacters(in: terminalPunctuation)
        for phrase in phrases where withoutTerminalPunctuation.hasSuffix(phrase) {
            let contentEnd = withoutTerminalPunctuation.index(withoutTerminalPunctuation.endIndex, offsetBy: -phrase.count)
            let precedingContent = String(withoutTerminalPunctuation[..<contentEnd])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Standalone utterance of this phrase (including nested shorter names like
            // "API音声ソフト"): keep the original text and do not fall through to a
            // shorter suffix that would wrongly strip part of the phrase.
            if precedingContent.isEmpty {
                return text
            }
            if delimiterOnlyPhrases.contains(phrase) && !endsWithDelimiter(precedingContent) {
                continue
            }
            return precedingContent
        }
        return text
    }

    private static func removingLeadingViewingThanks(from text: String) -> String {
        let withoutLeadingPunctuation = trim(text, set: terminalPunctuation, leading: true, trailing: false)
        for phrase in viewingThanksPhrases where withoutLeadingPunctuation.hasPrefix(phrase) {
            let contentStart = withoutLeadingPunctuation.index(withoutLeadingPunctuation.startIndex, offsetBy: phrase.count)
            let following = String(withoutLeadingPunctuation[contentStart...])
            let followingContent = trim(following, set: terminalPunctuation.union(.whitespacesAndNewlines), leading: true, trailing: false)
            if followingContent.isEmpty {
                return text
            }
            if delimiterOnlyPhrases.contains(phrase) && !startsWithDelimiter(following) {
                continue
            }
            return followingContent
        }
        return text
    }

    private static func startsWithDelimiter(_ text: String) -> Bool {
        guard let first = text.first else { return false }
        return terminalPunctuation.union(.whitespacesAndNewlines).isSuperset(of: CharacterSet(first.unicodeScalars))
    }

    private static func endsWithDelimiter(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return false }
        return terminalPunctuation.isSuperset(of: CharacterSet(last.unicodeScalars))
    }

    private static func trim(_ text: String, set: CharacterSet, leading: Bool, trailing: Bool) -> String {
        var start = text.startIndex
        var end = text.endIndex
        if leading {
            while start < end, set.isSuperset(of: CharacterSet(text[start].unicodeScalars)) {
                start = text.index(after: start)
            }
        }
        if trailing {
            while start < end {
                let previous = text.index(before: end)
                if set.isSuperset(of: CharacterSet(text[previous].unicodeScalars)) {
                    end = previous
                } else {
                    break
                }
            }
        }
        return String(text[start..<end])
    }
}
