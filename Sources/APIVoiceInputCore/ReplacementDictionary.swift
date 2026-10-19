import Foundation

/// 辞書で置き換えた結果。`count` は置き換えた箇所の数。
public struct ReplacementResult: Equatable, Sendable {
    public let text: String
    public let count: Int

    public init(text: String, count: Int) {
        self.text = text
        self.count = count
    }
}

/// 認識結果の「誤り → 正しい語」置き換え辞書。
///
/// 辞書ファイルは UTF-8 で、1行1件「誤り<タブ>正しい語」。`#` で始まる行はコメント、空行は無視する。
/// 置き換えは単純な文字列一致（正規表現は使わない）。長い「誤り」を先に使い、
/// 置き換えた結果はもう一度置き換えない。ファイルが無い・読めない・0件のときは何もしない。
/// ファイルの更新日時が変わったときだけ読み直す。
public final class ReplacementDictionary: @unchecked Sendable {
    private struct Entry {
        let wrong: String
        let correct: String
    }

    public let fileURL: URL
    private let lock = NSLock()
    private var loaded: (modifiedAt: Date, entries: [Entry])?

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func apply(to text: String) -> ReplacementResult {
        let entries = currentEntries()
        guard entries.isEmpty == false else {
            return ReplacementResult(text: text, count: 0)
        }
        return Self.replace(in: text, using: entries)
    }

    /// 辞書ファイルが無いときだけ、見本つきで作る。既にあれば（空でも）触らない。作ったときだけ true。
    @discardableResult
    public func createSampleFileIfNeeded() -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) == false else { return false }
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // .atomic と .withoutOverwriting は併用できない（Foundation が即クラッシュする）。
            try Data(Self.sampleContents.utf8).write(to: fileURL, options: [.withoutOverwriting])
            return true
        } catch {
            return false
        }
    }

    static let sampleContents = [
        "# API音声ソフト 置き換え辞書",
        "# 書き方: 「誤り」と「正しい語」を Tab キーで区切って、1行に1つ書きます。",
        "# 先頭が # の行と空行は無視されます。長い「誤り」が先に使われます。",
        "# 保存すると、次に話したときから反映されます（再起動は不要です）。",
        "グロック\tGroq",
        "ソニオックス\tSoniox",
        "クロードコード\tClaude Code",
        "ギットハブ\tGitHub",
        ""
    ].joined(separator: "\n")

    private func currentEntries() -> [Entry] {
        lock.withLock {
            guard let modifiedAt = modificationDate() else {
                loaded = nil
                return []
            }
            if let loaded, loaded.modifiedAt == modifiedAt {
                return loaded.entries
            }
            guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
                loaded = nil
                return []
            }
            let entries = Self.prioritized(Self.parse(contents))
            loaded = (modifiedAt, entries)
            return entries
        }
    }

    /// URL の資源値はキャッシュされうるので、更新日時は都度パスから読む。
    private func modificationDate() -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        return attributes?[.modificationDate] as? Date
    }

    private static func parse(_ contents: String) -> [Entry] {
        let text = contents.hasPrefix("\u{FEFF}") ? String(contents.dropFirst()) : contents
        var entries: [Entry] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let tab = line.firstIndex(of: "\t") else { continue }
            let wrong = line[..<tab].trimmingCharacters(in: .whitespaces)
            let correct = line[line.index(after: tab)...].trimmingCharacters(in: .whitespaces)
            // 行の前後は先に削ってあるので、タブが先頭・末尾にある行（片方が空の行）はここまで来ない。
            entries.append(Entry(wrong: wrong, correct: correct))
        }
        return entries
    }

    /// 長い「誤り」が先。同じ長さならファイルで先に書いた行が先。
    private static func prioritized(_ entries: [Entry]) -> [Entry] {
        entries.enumerated()
            .sorted { lhs, rhs in
                let (left, right) = (lhs.element.wrong.count, rhs.element.wrong.count)
                return left != right ? left > right : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// `entries` は優先順に並んでいる前提。優先順に、元の文章の上で一致する場所を確保していくので、
    /// 重なる場所は優先された方だけが置き換わり、置き換えた結果は再び置き換えられない。
    private static func replace(in text: String, using entries: [Entry]) -> ReplacementResult {
        let characters = Array(text)
        var claimed = [Bool](repeating: false, count: characters.count)
        var spans: [(start: Int, length: Int, correct: String)] = []

        for entry in entries {
            let pattern = Array(entry.wrong)
            guard pattern.isEmpty == false, pattern.count <= characters.count else { continue }
            var start = 0
            while start + pattern.count <= characters.count {
                let end = start + pattern.count
                if characters[start..<end].elementsEqual(pattern), claimed[start..<end].contains(true) == false {
                    for index in start..<end {
                        claimed[index] = true
                    }
                    spans.append((start, pattern.count, entry.correct))
                    start = end
                } else {
                    start += 1
                }
            }
        }

        guard spans.isEmpty == false else {
            return ReplacementResult(text: text, count: 0)
        }
        spans.sort { $0.start < $1.start }
        var output = ""
        var cursor = 0
        for span in spans {
            output += String(characters[cursor..<span.start])
            output += span.correct
            cursor = span.start + span.length
        }
        output += String(characters[cursor...])
        return ReplacementResult(text: output, count: spans.count)
    }
}
