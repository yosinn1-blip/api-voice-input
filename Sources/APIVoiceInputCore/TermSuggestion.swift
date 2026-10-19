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
    /// 問い合わせそのものを断られた（鍵が違う・モデルが無い・大きすぎる等。同じ内容を送り直しても通らない）
    case requestRejected
}

/// 足してはいけない理由。名前はログの集計（件数だけ）にそのまま使う。
public enum TermSuggestionRejection: String, Equatable, Sendable {
    case empty
    case noRealChange
    case badCorrect
    case badWrong
    case notInTexts
    case alreadyKnown
    /// 辞書にある誤りを含む長い語を、同じ正しい語に直そうとしている（名前の一部が消える）
    case swallowsKnownWord
    /// 辞書にある正しい語の一部（Claud は Claude の一部。足すと正しく書けた語が壊れる）
    case partOfKnownWord
    case rejectedBefore
    /// 誤りと正しい語の音が離れすぎている（AIが辞書の語へ無理に当てはめた）
    case notSoundAlike
    /// 辞書にある別の語のほうが、同じくらい音が近い（Glog は Groq とも Grok とも近い）
    case ambiguousWithKnownTerm
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
        // 「グロースハック」の中の「グロース」のように、別の語の一部としてしか出てこないものは数えない。
        guard texts.contains(where: { WordBoundary.standaloneCount(of: wrong, in: $0) > 0 }) else { return .notInTexts }
        if existingEntries.contains(where: { $0.wrong == wrong || $0.correct == wrong }) { return .alreadyKnown }
        // 例: 「クロード→Claude」があるのに「クロードコート→Claude」を足すと、「コート」が消えてしまう。
        if existingEntries.contains(where: { $0.correct == correct && $0.wrong != wrong && wrong.contains($0.wrong) }) {
            return .swallowsKnownWord
        }
        // 例: 「Claud→Claude」を足すと、正しく書けた「Claude」まで「Claudee」になってしまう。
        let lowercasedWrong = wrong.lowercased()
        if existingEntries.contains(where: { $0.correct.lowercased().contains(lowercasedWrong) }) { return .partOfKnownWord }
        // 消された語は、何に直す提案でも二度と足さない。
        if rejectedKeys.contains(where: { $0.hasPrefix(wrong + "\t") }) { return .rejectedBefore }
        let distance = PhoneticSimilarity.distance(wrong, correct)
        guard distance <= PhoneticSimilarity.maximumDistanceForSameName else { return .notSoundAlike }
        // 辞書に無い新しい名前は、辞書にある語のほうが近い（または同じくらい近い）ときは決めつけない。
        let knownCorrectTerms = Set(existingEntries.map(\.correct))
        if knownCorrectTerms.contains(correct) == false {
            let limit = min(distance, PhoneticSimilarity.maximumDistanceForSameName)
            if knownCorrectTerms.contains(where: { PhoneticSimilarity.distance(wrong, $0) <= limit }) {
                return .ambiguousWithKnownTerm
            }
        }
        if commonWords.isCommonWord(wrong) { return .commonWord }
        return nil
    }

    /// 正しい語: 半角の英数字（間に空白・.+-_ は可）で、前後は英数字。例: Groq, Claude Code, 1Password
    static func isPlainLatinName(_ text: String) -> Bool {
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

    /// 誤り: カタカナだけ（4字以上）か、英数字だけ（英字4つ以上・先頭は英字）。漢字・ひらがな・空白を含まない。
    private static func isPlausibleWrongWord(_ text: String) -> Bool {
        guard (4...30).contains(text.count) else { return false }
        let scalars = Array(text.unicodeScalars)
        if scalars.allSatisfy(isKatakana) {
            return text.count >= 4
        }
        guard let first = scalars.first, isASCIILetter(first), scalars.allSatisfy(isASCIILetterOrDigit) else {
            return false
        }
        return scalars.filter(isASCIILetter).count >= 4
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
    private static let privateKeywords = [
        "パスワード", "暗証", "マイナンバー", "口座番号", "カード番号", "秘密鍵", "シークレット",
        "住所", "電話番号", "生年月日", "クレジット", "APIキー"
    ]
    private static let privatePatterns = [
        #"https?://"#,
        #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#,
        #"[0-9０-９][0-9０-９\-−ー ]{5,}[0-9０-９]"#,
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
        if trimmed.lowercased().contains("password") { return nil }
        if privatePatterns.contains(where: { trimmed.range(of: $0, options: .regularExpression) != nil }) { return nil }
        return trimmed.count > maxCharacters ? String(trimmed.prefix(maxCharacters)) : trimmed
    }
}
