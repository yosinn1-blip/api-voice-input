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
    public struct Entry: Equatable, Sendable {
        public let wrong: String
        public let correct: String

        public init(wrong: String, correct: String) {
            self.wrong = wrong
            self.correct = correct
        }
    }

    /// 手書きの辞書。メニューで開く・見本を作る対象で、`fileURLs` の先頭。
    public let fileURL: URL
    private let additionalFileURLs: [URL]
    private let lock = NSLock()
    private var loaded: (stamps: [Date?], entries: [Entry])?

    /// 読むファイルの全部。先に書いたファイルの行が優先される
    /// （同じ長さの「誤り」が重なるとき、同じ「誤り」が複数あるとき）。
    public var fileURLs: [URL] { [fileURL] + additionalFileURLs }

    public init(fileURL: URL, additionalFileURLs: [URL] = []) {
        self.fileURL = fileURL
        self.additionalFileURLs = additionalFileURLs
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

    /// 初回に作る辞書の中身。下の初期登録は、実際の発話（約2,200件）で崩れていた語や、
    /// 正式表記が英字の製品名から選んだ。長い「誤り」が先に使われるので、
    /// 「グロックボット」（Grok Bot）が「グロック」（Groq）より先に直る。
    static let sampleContents: String = {
        let header = [
            "# API音声ソフト 置き換え辞書",
            "# 書き方: 「誤り」と「正しい語」を Tab キーで区切って、1行に1つ書きます。",
            "# 先頭が # の行と空行は無視されます。長い「誤り」が先に使われます。",
            "# 保存すると、次に話したときから反映されます（再起動は不要です）。",
            "# 使いながら覚えた語は、別のファイル dictionary-auto.txt に自動で足されます。",
            "#",
            "# ここから下は、AI・開発まわりで崩れやすい語の初期登録です。いらない行は消してください。"
        ]
        let entries: [(wrong: String, correct: String)] = [
            ("グロック", "Groq"),
            ("グロッグ", "Groq"),
            ("グロックボット", "Grok Bot"),
            ("グロッグボット", "Grok Bot"),
            ("グログボット", "Grok Bot"),
            ("ソニオックス", "Soniox"),
            ("ソニョックス", "Soniox"),
            ("SonyOx", "Soniox"),
            ("クロードコード", "Claude Code"),
            ("クロード", "Claude"),
            ("コーデックス", "Codex"),
            ("ギットハブ", "GitHub"),
            ("オブシリアン", "Obsidian"),
            ("オブシディアン", "Obsidian"),
            ("オープンコード", "OpenCode"),
            ("オープンクロー", "OpenClaw"),
            ("オープンルーター", "OpenRouter"),
            ("クラウドフレア", "Cloudflare"),
            ("スパベース", "Supabase"),
            ("スパブエース", "Supabase"),
            ("スーパーベース", "Supabase"),
            ("ショピファイ", "Shopify"),
            ("ショーピーファイ", "Shopify"),
            ("カーサー", "Cursor"),
            ("ジェミニー", "Gemini"),
            ("ジェミニ", "Gemini"),
            ("ナノバナナ", "Nano Banana"),
            ("ワンパスワード", "1Password"),
            ("コンピュータユーズ", "Computer Use"),
            ("オーパス", "Opus"),
            ("アンリアルエンジン", "Unreal Engine"),
            ("アンリアル", "Unreal"),
            ("ロブロックス", "Roblox"),
            ("マックミニ", "Mac mini"),
            ("グーグルクローム", "Google Chrome"),
            ("グーグル", "Google"),
            ("クローム", "Chrome")
        ]
        return (header + entries.map { "\($0.wrong)\t\($0.correct)" } + [""]).joined(separator: "\n")
    }()

    /// いまの辞書の全項目。優先順（長い「誤り」が先、同じ長さなら先のファイルの行が先）。
    public func currentEntries() -> [Entry] {
        lock.withLock {
            let files = fileURLs
            let stamps = files.map { Self.modificationDate(of: $0) }
            if let loaded, loaded.stamps == stamps {
                return loaded.entries
            }
            var all: [Entry] = []
            var readFailed = false
            for (url, stamp) in zip(files, stamps) where stamp != nil {
                guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
                    readFailed = true
                    continue
                }
                all += Self.parse(contents)
            }
            let entries = Self.prioritized(all)
            // 読めなかったファイルがあるときは覚えない（次の呼び出しでもう一度読む）。
            loaded = readFailed ? nil : (stamps, entries)
            return entries
        }
    }

    /// URL の資源値はキャッシュされうるので、更新日時は都度パスから読む。
    private static func modificationDate(of url: URL) -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.modificationDate] as? Date
    }

    static func parse(_ contents: String) -> [Entry] {
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
        let present = Set(characters)
        var claimed = [Bool](repeating: false, count: characters.count)
        var spans: [(start: Int, length: Int, correct: String)] = []

        for entry in entries {
            let pattern = Array(entry.wrong)
            // 文章に出てこない文字で始まる項目は、探すまでもない（項目が増えても遅くならないように）
            guard let first = pattern.first, present.contains(first), pattern.count <= characters.count else { continue }
            var start = 0
            while start + pattern.count <= characters.count {
                let end = start + pattern.count
                // 英字の語は、前後が英数字でつながっているとき（Claud が Claude の中など）は置き換えない。
                if characters[start..<end].elementsEqual(pattern),
                   WordBoundary.isStandalone(characters, start: start, end: end, includingKatakana: false),
                   claimed[start..<end].contains(true) == false {
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
