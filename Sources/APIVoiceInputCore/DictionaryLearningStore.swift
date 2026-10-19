import Foundation

/// 学習の途中経過。文章は一切持たない（語の組と回数だけ）。
public struct DictionaryLearningState: Codable, Equatable, Sendable {
    /// まだ辞書に足していない候補が、何回見つかったか（"誤り\t正しい語" → 回数）
    public var sightings: [String: Int] = [:]
    /// 自動辞書に足した組
    public var promoted: [String] = []
    /// 自動辞書から消された組（二度と足さない）
    public var rejected: [String] = []
    /// 回数制限を数える日付（yyyy-MM-dd）
    public var day: String = ""
    public var requestsToday: Int = 0
    public var promotionsToday: Int = 0

    public init() {}

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sightings = try container.decodeIfPresent([String: Int].self, forKey: .sightings) ?? [:]
        promoted = try container.decodeIfPresent([String].self, forKey: .promoted) ?? []
        rejected = try container.decodeIfPresent([String].self, forKey: .rejected) ?? []
        day = try container.decodeIfPresent(String.self, forKey: .day) ?? ""
        requestsToday = try container.decodeIfPresent(Int.self, forKey: .requestsToday) ?? 0
        promotionsToday = try container.decodeIfPresent(Int.self, forKey: .promotionsToday) ?? 0
    }
}

/// 自動で覚えた語のファイル（dictionary-auto.txt）と、学習の途中経過（dictionary-learning.json）の読み書き。
public final class DictionaryLearningStore: Sendable {
    public let autoDictionaryURL: URL
    public let stateURL: URL

    /// 状態に残す候補の上限。多すぎるときは回数の多いものを残す。
    static let maximumSightings = 200

    private static let header = """
    # 自動で覚えた語（使いながら、AIが見つけたものがここに足されます）
    # 合わない行は消してください。消した語は二度と足されません。

    """

    public init(autoDictionaryURL: URL, stateURL: URL) {
        self.autoDictionaryURL = autoDictionaryURL
        self.stateURL = stateURL
    }

    public func loadState() -> DictionaryLearningState {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(DictionaryLearningState.self, from: data) else {
            return DictionaryLearningState()
        }
        return state
    }

    public func saveState(_ state: DictionaryLearningState) {
        var pruned = state
        if pruned.sightings.count > Self.maximumSightings {
            let strongest = pruned.sightings
                .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .prefix(Self.maximumSightings)
            pruned.sightings = Dictionary(uniqueKeysWithValues: strongest.map { ($0.key, $0.value) })
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(pruned) else { return }
        try? FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard (try? data.write(to: stateURL, options: [.atomic])) != nil else { return }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
    }

    public var autoDictionaryExists: Bool {
        FileManager.default.fileExists(atPath: autoDictionaryURL.path)
    }

    /// 自動辞書に足す。ファイルが無ければ見出しつきで作り、あれば末尾に足す（既存の行は触らない）。
    /// 書けたときだけ true（書けなかった語を「覚えた」ことにしないため）。
    @discardableResult
    public func appendEntries(_ entries: [TermSuggestion], date: Date) -> Bool {
        guard entries.isEmpty == false else { return true }
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(
                at: autoDictionaryURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            return false
        }
        let stamp = Self.dayString(date)
        let lines = entries.map { "# \(stamp) 自動で追加\n\($0.wrong)\t\($0.correct)\n" }.joined()

        guard autoDictionaryExists else {
            return fileManager.createFile(
                atPath: autoDictionaryURL.path,
                contents: Data((Self.header + lines).utf8),
                attributes: [.posixPermissions: 0o600]
            )
        }
        // 手で編集されて最後の改行が無くなっていても、行が混ざらないようにする。
        let existing = (try? Data(contentsOf: autoDictionaryURL)) ?? Data()
        let separator = existing.last == 0x0A || existing.isEmpty ? "" : "\n"
        do {
            let handle = try FileHandle(forWritingTo: autoDictionaryURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data((separator + lines).utf8))
            return true
        } catch {
            return false
        }
    }

    /// 自動辞書の中身。ファイルが無ければ空、あるのに読めなければ nil。
    public func readAutoEntries() -> [ReplacementDictionary.Entry]? {
        guard FileManager.default.fileExists(atPath: autoDictionaryURL.path) else { return [] }
        guard let contents = try? String(contentsOf: autoDictionaryURL, encoding: .utf8) else { return nil }
        return ReplacementDictionary.parse(contents)
    }

    static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
