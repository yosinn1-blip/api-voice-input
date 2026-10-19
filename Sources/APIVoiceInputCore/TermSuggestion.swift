import Foundation

/// 「この誤りは、本当はこの綴りのはず」という提案。
public struct TermSuggestion: Equatable, Sendable {
    public let wrong: String
    public let correct: String
    /// AI 自身が「確信がある」と答えたか。確信がないときは、1回見つけただけでは足さない。
    public let isConfident: Bool

    public init(wrong: String, correct: String, isConfident: Bool = true) {
        self.wrong = wrong
        self.correct = correct
        self.isConfident = isConfident
    }

    /// 学習の記録（見つけた回数・消された語）で使う印。
    public var key: String {
        "\(wrong)\t\(correct)"
    }
}

/// 文章を読んで、崩れた固有名詞の提案を返す係（実体は Groq の AI）。
public protocol TermSuggestionProvider: Sendable {
    /// `texts` は音声認識の結果の文章、`knownTerms` は辞書に既にある正しい語（ヒント）。
    func suggest(texts: [String], knownTerms: [String]) async throws -> [TermSuggestion]
}

public enum TermSuggestionError: Error, Equatable, Sendable {
    /// 答えを読み取れなかった（形式が違う）
    case unreadableResponse
}

public enum TermSuggestionRejection: Equatable, Sendable {
    case empty
    case noRealChange
    case badCorrect
    case badWrong
    case notInTexts
    case alreadyKnown
    /// 辞書にある誤りを含む長い語を、同じ正しい語に直そうとしている（名前の一部が消える）
    case swallowsKnownWord
    case rejectedBefore
    case commonWord
}

/// AI の提案をそのまま信用せず、辞書に足してよい形かを機械的に確かめる。
public enum TermSuggestionFilter {
    /// 足してはいけない理由。足してよければ nil。
    public static func rejection(
        for suggestion: TermSuggestion,
        texts: [String],
        existingEntries: [ReplacementDictionary.Entry],
        rejectedKeys: Set<String>,
        commonWords: any CommonWordChecker
    ) -> TermSuggestionRejection? {
        let wrong = suggestion.wrong
        let correct = suggestion.correct
        if wrong.isEmpty || correct.isEmpty { return .empty }
        if wrong.lowercased() == correct.lowercased() { return .noRealChange }
        guard isPlainLatinName(correct) else { return .badCorrect }
        guard isPlausibleWrongWord(wrong) else { return .badWrong }
        guard texts.contains(where: { $0.contains(wrong) }) else { return .notInTexts }
        if existingEntries.contains(where: { $0.wrong == wrong || $0.correct == wrong }) { return .alreadyKnown }
        // 例: 「クロード→Claude」があるのに「クロードコート→Claude」を足すと、「コート」が消えてしまう。
        if existingEntries.contains(where: { $0.correct == correct && $0.wrong != wrong && wrong.contains($0.wrong) }) {
            return .swallowsKnownWord
        }
        if rejectedKeys.contains(suggestion.key) { return .rejectedBefore }
        if commonWords.isCommonWord(wrong) { return .commonWord }
        return nil
    }

    /// 正しい語: 半角の英数字（間に空白・.+-_ は可）で、前後は英数字。例: Groq, Claude Code, 1Password
    private static func isPlainLatinName(_ text: String) -> Bool {
        let scalars = Array(text.unicodeScalars)
        guard (2...40).contains(text.count), let first = scalars.first, let last = scalars.last else { return false }
        guard isASCIILetterOrDigit(first), isASCIILetterOrDigit(last) else { return false }
        var previousWasSpace = false
        for scalar in scalars {
            if scalar == " " {
                if previousWasSpace { return false }
                previousWasSpace = true
                continue
            }
            previousWasSpace = false
            guard isASCIILetterOrDigit(scalar) || ".+-_".unicodeScalars.contains(scalar) else { return false }
        }
        return scalars.contains(where: isASCIILetter)
    }

    /// 誤り: カタカナだけ（4字以上）か、英数字だけ（英字3つ以上・先頭は英字）。漢字・ひらがな・空白を含まない。
    private static func isPlausibleWrongWord(_ text: String) -> Bool {
        guard (3...30).contains(text.count) else { return false }
        let scalars = Array(text.unicodeScalars)
        if scalars.allSatisfy(isKatakana) {
            return text.count >= 4
        }
        guard let first = scalars.first, isASCIILetter(first), scalars.allSatisfy(isASCIILetterOrDigit) else {
            return false
        }
        return scalars.filter(isASCIILetter).count >= 3
    }

    private static func isKatakana(_ scalar: Unicode.Scalar) -> Bool {
        (0x30A1...0x30FA).contains(scalar.value) || scalar.value == 0x30FC
    }

    private static func isASCIILetter(_ scalar: Unicode.Scalar) -> Bool {
        (0x41...0x5A).contains(scalar.value) || (0x61...0x7A).contains(scalar.value)
    }

    private static func isASCIILetterOrDigit(_ scalar: Unicode.Scalar) -> Bool {
        isASCIILetter(scalar) || (0x30...0x39).contains(scalar.value)
    }
}

/// 学習のために AI へ送る文章を選ぶ。個人情報や鍵に見えるものは送らない。
public enum LearningTextScreen {
    private static let privateKeywords = ["パスワード", "暗証", "マイナンバー", "口座番号", "カード番号", "秘密鍵", "シークレット"]
    private static let privatePatterns = [
        #"https?://"#,
        #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#,
        #"[0-9][0-9\- ]{5,}[0-9]"#,
        #"[A-Za-z0-9_\-]{24,}"#
    ]

    /// 送ってよい文章を整えて返す。短すぎる・私的に見えるものは nil。長いものは前半だけにする。
    public static func prepare(_ text: String, maxCharacters: Int, minimumLength: Int) -> String? {
        // 番号つきの一覧で送るので、文章の中の改行は空白にする。
        let trimmed = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        guard trimmed.count >= minimumLength else { return nil }
        if privateKeywords.contains(where: { trimmed.contains($0) }) { return nil }
        if privatePatterns.contains(where: { trimmed.range(of: $0, options: .regularExpression) != nil }) { return nil }
        return trimmed.count > maxCharacters ? String(trimmed.prefix(maxCharacters)) : trimmed
    }
}
