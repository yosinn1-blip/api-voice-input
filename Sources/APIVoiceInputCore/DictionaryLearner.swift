import Foundation

/// 使いながら辞書を育てる係。貼り付けた文章をためておき、ある程度たまったら裏でAIに読ませて、
/// 崩れた固有名詞を「自動で覚えた語」のファイルに足す。貼り付けの速さには関わらない。
///
/// 足す条件: 機械的な検査に通り、かつ（同じ組を2回見つけた、または辞書に既にある正しい語の別の崩れ方）。
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
        /// 失敗したあと、次に聞くまで待つ秒数
        public var retryAfterFailure: TimeInterval = 15 * 60

        public init() {}
    }

    private let dictionary: ReplacementDictionary
    private let store: DictionaryLearningStore
    private let providerFactory: @Sendable () -> (any TermSuggestionProvider)?
    private let commonWords: any CommonWordChecker
    private let now: @Sendable () -> Date
    private let log: @Sendable (String) -> Void
    private let configuration: Configuration

    private var queue: [String] = []
    private var queuedSince: Date?
    private var retryNotBefore = Date.distantPast
    private var isAsking = false

    /// `providerFactory` は、聞く直前に呼ぶ。APIキーが無いときは nil を返す（たまった文章はそのまま残る）。
    public init(
        dictionary: ReplacementDictionary,
        store: DictionaryLearningStore,
        providerFactory: @escaping @Sendable () -> (any TermSuggestionProvider)?,
        commonWords: any CommonWordChecker = SystemDictionaryWordChecker(),
        now: @escaping @Sendable () -> Date = { Date() },
        log: @escaping @Sendable (String) -> Void = { _ in },
        configuration: Configuration = Configuration()
    ) {
        self.dictionary = dictionary
        self.store = store
        self.providerFactory = providerFactory
        self.commonWords = commonWords
        self.now = now
        self.log = log
        self.configuration = configuration
    }

    /// 貼り付けた文章を1つ渡す。たまっていれば、その場で（裏のタスクとして）AIに聞く。
    public func record(_ text: String) async {
        guard let prepared = LearningTextScreen.prepare(
            text,
            maxCharacters: configuration.maxCharactersPerText,
            minimumLength: configuration.minimumTextLength
        ) else { return }
        queue.append(prepared)
        trimQueue()
        if queuedSince == nil {
            queuedSince = now()
        }
        guard shouldAsk() else { return }
        await ask()
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
        guard let provider = providerFactory() else { return }
        var state = store.loadState()
        let today = DictionaryLearningStore.dayString(now())
        if state.day != today {
            state.day = today
            state.requestsToday = 0
            state.promotionsToday = 0
        }
        guard state.requestsToday < configuration.maxRequestsPerDay else { return }

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

        let knownCorrectTerms = Set(known.map(\.correct))
        let rejectedKeys = Set(state.rejected)
        var seenKeys = Set<String>()
        var accepted = 0
        var learned: [TermSuggestion] = []
        for raw in suggestions {
            let suggestion = TermSuggestion(
                wrong: raw.wrong.trimmingCharacters(in: .whitespacesAndNewlines),
                correct: raw.correct.trimmingCharacters(in: .whitespacesAndNewlines),
                isConfident: raw.isConfident
            )
            let rejection = TermSuggestionFilter.rejection(
                for: suggestion,
                texts: texts,
                existingEntries: known,
                rejectedKeys: rejectedKeys,
                commonWords: commonWords
            )
            guard rejection == nil, seenKeys.insert(suggestion.key).inserted else { continue }
            accepted += 1

            let hits = texts.filter { $0.contains(suggestion.wrong) }.count
            let total = state.sightings[suggestion.key, default: 0] + hits
            let isConfidentVariantOfKnownTerm = suggestion.isConfident && knownCorrectTerms.contains(suggestion.correct)
            let isConvincing = total >= 2 || (total >= 1 && isConfidentVariantOfKnownTerm)
            if isConvincing, state.promotionsToday < configuration.maxPromotionsPerDay {
                learned.append(suggestion)
                state.promoted.append(suggestion.key)
                state.sightings[suggestion.key] = nil
                state.promotionsToday += 1
            } else {
                state.sightings[suggestion.key] = total
            }
        }
        store.appendEntries(learned, date: now())
        store.saveState(state)
        log("dictionary learning texts=\(texts.count) suggestions=\(suggestions.count) accepted=\(accepted) learned=\(learned.count)")
    }

    /// ユーザーが自動辞書から消した行は「二度と足さない」に移す。
    private func reconcileDeletedEntries(in state: inout DictionaryLearningState) {
        guard let present = store.readAutoEntries() else { return }
        let presentKeys = Set(present.map { TermSuggestion(wrong: $0.wrong, correct: $0.correct).key })
        let deleted = state.promoted.filter { presentKeys.contains($0) == false }
        guard deleted.isEmpty == false else { return }
        state.rejected.append(contentsOf: deleted)
        state.promoted.removeAll { presentKeys.contains($0) == false }
    }

    private func handleFailure(_ error: any Error, texts: [String]) {
        let kind: String
        var shouldRetryLater = true
        if let voiceError = error as? VoiceInputError {
            switch voiceError {
            case .providerRateLimited:
                kind = "rateLimited"
            default:
                kind = "http"
            }
        } else if let suggestionError = error as? TermSuggestionError, suggestionError == .unreadableResponse {
            kind = "unreadable"
            shouldRetryLater = false
        } else {
            kind = "network"
        }
        if shouldRetryLater {
            queue = texts + queue
            trimQueue()
            queuedSince = now()
            retryNotBefore = now().addingTimeInterval(configuration.retryAfterFailure)
        }
        log("dictionary learning failed kind=\(kind)")
    }

    /// AI への手がかり。辞書にある正しい語（重複なし・アルファベット順・多すぎれば先頭から）。
    private static func knownTerms(from entries: [ReplacementDictionary.Entry]) -> [String] {
        var seen = Set<String>()
        let unique = entries.map(\.correct).filter { seen.insert($0).inserted }
        let sorted = unique.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return Array(sorted.prefix(80))
    }
}
