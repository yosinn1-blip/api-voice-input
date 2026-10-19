import Foundation

/// 使いながら辞書を育てる係。貼り付けた文章をためておき、ある程度たまったら裏でAIに読ませて、
/// 崩れた固有名詞を「自動で覚えた語」のファイルに足す。貼り付けの速さには関わらない。
///
/// 誤登録で発話が壊れるのが一番の害なので、足す条件は厳しい:
/// - 機械的な検査（TermSuggestionFilter）を通ったものだけ
/// - 別々の問い合わせで2回見つけたとき（同じ問い合わせの中の2文では1回と数える）。
///   ただし、辞書にある誤りと1文字違いの崩れ方で、AIも確信しているときは1回で足す
/// - 同じ誤りに別々の正しい語が競っているときは足さない
/// 文章はメモリにしか置かず、ログにも出さない（件数だけ）。
public actor DictionaryLearner {
    public struct Configuration: Sendable {
        /// 何文たまったら聞くか
        public var batchSize = 6
        /// 最初の1文から、この秒数たったら少なくても聞く
        public var maxWait: TimeInterval = 20 * 60
        public var maxQueuedTexts = 40
        public var maxTextsPerRequest = 20
        public var maxCharactersPerText = 400
        public var minimumTextLength = 6
        public var maxRequestsPerDay = 40
        public var maxPromotionsPerDay = 10
        /// 自動辞書に溜める語の上限（置き換えが遅くならないように）
        public var maxLearnedEntries = 300
        /// 失敗したあと、次に聞くまで待つ秒数
        public var retryAfterFailure: TimeInterval = 15 * 60

        public init() {}
    }

    private let dictionary: ReplacementDictionary
    private let store: DictionaryLearningStore
    private let providerFactory: @Sendable () -> (any TermSuggestionProvider)?
    private let commonWords: any CommonWordChecker
    private let isEnabled: @Sendable () -> Bool
    private let onLearned: @Sendable ([TermSuggestion]) -> Void
    private let now: @Sendable () -> Date
    private let log: @Sendable (String) -> Void
    private let configuration: Configuration

    private var queue: [String] = []
    private var queuedSince: Date?
    private var retryNotBefore = Date.distantPast
    private var isAsking = false
    private var hasLoggedPause = false

    /// `providerFactory` は、聞く直前に呼ぶ。APIキーが無いときは nil を返す（たまった文章はそのまま残る）。
    /// `isEnabled` は「使いながら辞書を育てる」がオンかを、その時々に答える。オフの間は何もためない・送らない。
    /// `onLearned` は、辞書に語を足せたときに、足した語を知らせる（本人が気づけるようにするため。ログには出さない）。
    public init(
        dictionary: ReplacementDictionary,
        store: DictionaryLearningStore,
        providerFactory: @escaping @Sendable () -> (any TermSuggestionProvider)?,
        commonWords: any CommonWordChecker = SystemDictionaryWordChecker(),
        isEnabled: @escaping @Sendable () -> Bool = { true },
        onLearned: @escaping @Sendable ([TermSuggestion]) -> Void = { _ in },
        now: @escaping @Sendable () -> Date = { Date() },
        log: @escaping @Sendable (String) -> Void = { _ in },
        configuration: Configuration = Configuration()
    ) {
        self.dictionary = dictionary
        self.store = store
        self.providerFactory = providerFactory
        self.commonWords = commonWords
        self.isEnabled = isEnabled
        self.onLearned = onLearned
        self.now = now
        self.log = log
        self.configuration = configuration
    }

    /// 貼り付けた文章を1つ渡す。たまっていれば、その場で（裏のタスクとして）AIに聞く。
    public func record(_ text: String) async {
        guard isEnabled() else {
            clearQueue()
            return
        }
        guard let prepared = LearningTextScreen.prepare(
            text,
            maxCharacters: configuration.maxCharactersPerText,
            minimumLength: configuration.minimumTextLength
        ) else { return }
        // 同じ文の言い直し・重複は1つとして数える。
        guard queue.contains(prepared) == false else { return }
        queue.append(prepared)
        trimQueue()
        if queuedSince == nil {
            queuedSince = now()
        }
        guard shouldAsk() else { return }
        await ask()
    }

    /// ためてある文章を捨てる。学習をオフにしたとき、オフにする前の文章を、あとで再びオンにした時に送らないため。
    public func clearQueue() {
        queue.removeAll()
        queuedSince = nil
    }

    private func shouldAsk() -> Bool {
        guard isAsking == false, queue.isEmpty == false, now() >= retryNotBefore else { return false }
        if queue.count >= configuration.batchSize { return true }
        if let since = queuedSince, now().timeIntervalSince(since) >= configuration.maxWait { return true }
        return false
    }

    private func trimQueue() {
        if queue.count > configuration.maxQueuedTexts {
            queue.removeFirst(queue.count - configuration.maxQueuedTexts)
        }
    }

    private func ask() async {
        guard isEnabled() else {
            clearQueue()
            return
        }
        var state = store.loadState()
        let today = DictionaryLearningStore.dayString(now())
        if state.day != today {
            state.day = today
            state.requestsToday = 0
            state.promotionsToday = 0
        }
        // 上限の日は翌日まで待つ（貼り付けのたびに状態やAPIキーを読みにいかない）。
        guard state.requestsToday < configuration.maxRequestsPerDay else {
            retryNotBefore = Self.startOfNextDay(after: now())
            return
        }
        guard let provider = providerFactory() else { return }

        isAsking = true
        defer { isAsking = false }

        let texts = Array(queue.prefix(configuration.maxTextsPerRequest))
        queue.removeFirst(texts.count)
        queuedSince = queue.isEmpty ? nil : now()
        state.requestsToday += 1

        reconcileDeletedEntries(in: &state)
        let known = dictionary.currentEntries()

        let suggestions: [TermSuggestion]
        do {
            suggestions = try await provider.suggest(texts: texts, knownTerms: Self.knownTerms(from: known))
        } catch {
            handleFailure(error, texts: texts)
            store.saveState(state)
            return
        }
        // 聞いている間にオフにされたら、答えは使わない。
        guard isEnabled() else {
            store.saveState(state)
            return
        }

        // 1) 機械的な検査
        let rejectedKeys = Set(state.rejected)
        var rejections: [TermSuggestionRejection: Int] = [:]
        var accepted: [TermSuggestion] = []
        var seenKeys = Set<String>()
        for raw in suggestions {
            let suggestion = TermSuggestion(
                wrong: raw.wrong.trimmingCharacters(in: .whitespacesAndNewlines),
                correct: raw.correct.trimmingCharacters(in: .whitespacesAndNewlines),
                isConfident: raw.isConfident
            )
            if let reason = TermSuggestionFilter.rejection(
                for: suggestion,
                texts: texts,
                existingEntries: known,
                rejectedKeys: rejectedKeys,
                commonWords: commonWords
            ) {
                rejections[reason, default: 0] += 1
                continue
            }
            if seenKeys.insert(suggestion.key).inserted {
                accepted.append(suggestion)
            }
        }
        // 2) 同じ誤りに、別々の正しい語が競っているものは決めつけない
        let correctsByWrong = Dictionary(grouping: accepted, by: \.wrong).mapValues { Set($0.map(\.correct)) }

        // 3) 回数を数え、足してよいものを決める
        let canPromote = commonWords.isUsable
        if canPromote == false, hasLoggedPause == false {
            hasLoggedPause = true
            log("dictionary learning paused reason=noSystemDictionary")
        }
        var learned: [TermSuggestion] = []
        for suggestion in accepted {
            // 1回の問い合わせで数えるのは1回まで（同じ指示の言い直しや、1つの話題で2回言っただけで足さない）
            let total = state.sightings[suggestion.key, default: 0] + 1
            state.sightings[suggestion.key] = total
            let hasRival = (correctsByWrong[suggestion.wrong]?.count ?? 0) > 1
                || state.sightings.keys.contains { $0 != suggestion.key && $0.hasPrefix(suggestion.wrong + "\t") }
            let isCloseToAKnownForm = suggestion.isConfident && known.contains {
                $0.correct == suggestion.correct && Self.isWithinOneEdit($0.wrong, suggestion.wrong)
            }
            let isConvincing = total >= 2 || isCloseToAKnownForm
            guard canPromote, hasRival == false, isConvincing,
                  state.promotionsToday + learned.count < configuration.maxPromotionsPerDay,
                  state.promoted.count + learned.count < configuration.maxLearnedEntries else { continue }
            learned.append(suggestion)
        }

        // 4) 書けたものだけ「覚えた」ことにする
        if learned.isEmpty == false {
            if store.appendEntries(learned, date: now()) {
                for suggestion in learned {
                    state.promoted.append(suggestion.key)
                    state.sightings[suggestion.key] = nil
                }
                state.promotionsToday += learned.count
                onLearned(learned)
            } else {
                log("dictionary learning failed kind=write")
                learned = []
            }
        }
        store.saveState(state)

        var line = "dictionary learning texts=\(texts.count) suggestions=\(suggestions.count) accepted=\(accepted.count)"
        line += " learned=\(learned.count) entries=\(known.count + learned.count)"
        if rejections.isEmpty == false {
            let summary = rejections.sorted { $0.key.rawValue < $1.key.rawValue }
                .map { "\($0.key.rawValue):\($0.value)" }
                .joined(separator: ",")
            line += " rejected=\(summary)"
        }
        log(line)
    }

    /// ユーザーが自動辞書から消した行は「二度と足さない」に移す。ファイルごと消したときは、やり直し（拒否には入れない）。
    private func reconcileDeletedEntries(in state: inout DictionaryLearningState) {
        guard store.autoDictionaryExists else {
            state.promoted.removeAll()
            return
        }
        guard let present = store.readAutoEntries() else { return }
        let presentKeys = Set(present.map { TermSuggestion(wrong: $0.wrong, correct: $0.correct).key })
        let deleted = state.promoted.filter { presentKeys.contains($0) == false }
        guard deleted.isEmpty == false else { return }
        state.rejected.append(contentsOf: deleted)
        state.promoted.removeAll { presentKeys.contains($0) == false }
    }

    private func handleFailure(_ error: any Error, texts: [String]) {
        let kind: String
        var shouldKeepTexts = true
        var shouldWait = true
        if let voiceError = error as? VoiceInputError {
            if case .providerRateLimited = voiceError {
                kind = "rateLimited"
            } else {
                kind = "http"
            }
        } else if let suggestionError = error as? TermSuggestionError {
            switch suggestionError {
            case .unreadableResponse:
                kind = "unreadable"
                shouldKeepTexts = false
                shouldWait = false
            case .requestRejected:
                kind = "rejected"
                shouldKeepTexts = false
            }
        } else {
            kind = "network"
        }
        // 聞いている間にオフにされたなら、文章は戻さない。
        if shouldKeepTexts, isEnabled() {
            queue = texts + queue
            trimQueue()
            queuedSince = now()
        }
        if shouldWait {
            retryNotBefore = now().addingTimeInterval(configuration.retryAfterFailure)
        }
        log("dictionary learning failed kind=\(kind)")
    }

    private static func startOfNextDay(after date: Date) -> Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
            ?? date.addingTimeInterval(24 * 60 * 60)
    }

    /// 1文字の入れ替え・足し・引きで同じになるか（ソニオックス／ソニョックス のような崩れ方の違い）。
    private static func isWithinOneEdit(_ first: String, _ second: String) -> Bool {
        let left = Array(first)
        let right = Array(second)
        guard abs(left.count - right.count) <= 1 else { return false }
        if left == right { return true }
        var index = 0
        while index < min(left.count, right.count), left[index] == right[index] {
            index += 1
        }
        if left.count == right.count {
            return Array(left[(index + 1)...]) == Array(right[(index + 1)...])
        }
        let (longer, shorter) = left.count > right.count ? (left, right) : (right, left)
        return Array(longer[(index + 1)...]) == Array(shorter[index...])
    }

    /// AI への手がかり。辞書にある正しい語のうち英数字のもの（重複なし・アルファベット順・多すぎれば先頭から）。
    /// 日本語の正しい語（人名など）は送らない。
    private static func knownTerms(from entries: [ReplacementDictionary.Entry]) -> [String] {
        var seen = Set<String>()
        let unique = entries.map(\.correct).filter {
            TermSuggestionFilter.isPlainLatinName($0) && seen.insert($0).inserted
        }
        let sorted = unique.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return Array(sorted.prefix(80))
    }
}
