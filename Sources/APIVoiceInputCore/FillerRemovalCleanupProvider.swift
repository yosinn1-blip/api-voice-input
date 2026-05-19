import Foundation

public struct FillerRemovalCleanupProvider: CleanupProvider {
    public let id = "rule-based-filler-removal"

    private static let leadingFillers = [
        "えーっと", "えっと", "えーと", "えー", "ええと",
        "あのー", "あの", "うーん", "うー", "んー",
        "なんか", "まあ"
    ]

    private static let punctuationBoundedFillers = [
        "えーっと", "えっと", "えーと", "えー", "ええと",
        "あのー", "あの", "うーん", "うー", "んー", "なんか", "まあ"
    ]

    public init() {}

    public func clean(transcript: String, prompt: String) async throws -> String {
        Self.clean(transcript)
    }

    static func clean(_ transcript: String) -> String {
        var text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        text = removeLeadingFillers(from: text)
        text = removePunctuationBoundedFillers(from: text)
        text = normalizeSpacingAndPunctuation(text)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removeLeadingFillers(from input: String) -> String {
        var text = input
        var didRemove = true
        while didRemove {
            didRemove = false
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            for filler in leadingFillers {
                guard shouldStripLeadingFiller(filler, from: text) else { continue }
                text.removeFirst(filler.count)
                text = text.trimmingCharacters(in: CharacterSet(charactersIn: " 、,　\t\n\r"))
                didRemove = true
                break
            }
        }
        return text
    }

    private static func shouldStripLeadingFiller(_ filler: String, from text: String) -> Bool {
        guard text.hasPrefix(filler) else { return false }
        if filler == "まあ", text.hasPrefix("まあまあ") { return false }
        return true
    }

    private static func removePunctuationBoundedFillers(from input: String) -> String {
        var text = input
        for filler in punctuationBoundedFillers {
            let escaped = NSRegularExpression.escapedPattern(for: filler)
            let pattern = "([、。！？!?]\\s*)" + escaped + "[、,\\s　]*"
            text = text.replacingOccurrences(
                of: pattern,
                with: "$1",
                options: .regularExpression
            )
        }
        return text
    }

    private static func normalizeSpacingAndPunctuation(_ input: String) -> String {
        var text = input
        text = text.replacingOccurrences(of: "[ \\t　]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\s+([、。！？!?])", with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: "([、。！？!?])\\s+", with: "$1", options: .regularExpression)
        return text
    }
}
