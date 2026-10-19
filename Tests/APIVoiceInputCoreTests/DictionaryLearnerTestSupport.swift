import XCTest
@testable import APIVoiceInputCore

/// テストで動かせる時計。
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ date: Date = Date(timeIntervalSince1970: 1_792_411_200)) {
        current = date
    }

    func now() -> Date {
        lock.withLock { current }
    }

    func advance(_ seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}

/// ログに出た行を集める。
final class LogBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ line: String) {
        lock.withLock { storage.append(line) }
    }

    var lines: [String] {
        lock.withLock { storage }
    }
}

/// 入り切りできるスイッチ（APIキーがある／無い、の再現に使う）。
final class TestSwitch: @unchecked Sendable {
    private let lock = NSLock()
    private var on: Bool

    init(_ on: Bool = true) {
        self.on = on
    }

    var isOn: Bool {
        get { lock.withLock { on } }
        set { lock.withLock { on = newValue } }
    }
}

/// 「普通の語」を決め打ちで答える。
struct FixedWordChecker: CommonWordChecker {
    let words: Set<String>

    init(_ words: Set<String> = []) {
        self.words = words
    }

    func isCommonWord(_ word: String) -> Bool {
        words.contains(word)
    }
}

/// 台本どおりに答える提案係。呼ばれた内容を覚えておく。
final class MockTermSuggestionProvider: TermSuggestionProvider, @unchecked Sendable {
    struct Call: Equatable {
        let texts: [String]
        let knownTerms: [String]
    }

    private let lock = NSLock()
    private var script: [Result<[TermSuggestion], Error>] = []
    private var recorded: [Call] = []

    func enqueue(_ result: Result<[TermSuggestion], Error>) {
        lock.withLock { script.append(result) }
    }

    var calls: [Call] {
        lock.withLock { recorded }
    }

    func suggest(texts: [String], knownTerms: [String]) async throws -> [TermSuggestion] {
        let next: Result<[TermSuggestion], Error> = lock.withLock {
            recorded.append(Call(texts: texts, knownTerms: knownTerms))
            return script.isEmpty ? .success([]) : script.removeFirst()
        }
        return try next.get()
    }
}

struct LearnerFixture {
    let learner: DictionaryLearner
    let dictionary: ReplacementDictionary
    let store: DictionaryLearningStore
    let provider: MockTermSuggestionProvider
    let clock: TestClock
    let log: LogBox
    let providerAvailable: TestSwitch
}

extension XCTestCase {
    /// 学習係と、その周り（辞書ファイル・提案係・時計・ログ）を一式作る。
    /// 3文たまったら聞く設定にしてある。
    func makeLearnerFixture(
        manual: String = "",
        commonWords: Set<String> = [],
        configure: (inout DictionaryLearner.Configuration) -> Void = { _ in }
    ) throws -> LearnerFixture {
        let directory = try makeTemporaryDirectory()
        let manualURL = directory.appendingPathComponent("dictionary.txt")
        try manual.write(to: manualURL, atomically: true, encoding: .utf8)
        let autoURL = directory.appendingPathComponent("dictionary-auto.txt")
        let stateURL = directory.appendingPathComponent("dictionary-learning.json")
        let dictionary = ReplacementDictionary(fileURL: manualURL, additionalFileURLs: [autoURL])
        let store = DictionaryLearningStore(autoDictionaryURL: autoURL, stateURL: stateURL)
        let provider = MockTermSuggestionProvider()
        let clock = TestClock()
        let log = LogBox()
        let providerAvailable = TestSwitch(true)
        var configuration = DictionaryLearner.Configuration()
        configuration.batchSize = 3
        configuration.maxWait = 600
        configuration.retryAfterFailure = 900
        configure(&configuration)
        let learner = DictionaryLearner(
            dictionary: dictionary,
            store: store,
            providerFactory: { providerAvailable.isOn ? provider : nil },
            commonWords: FixedWordChecker(commonWords),
            now: { clock.now() },
            log: { log.append($0) },
            configuration: configuration
        )
        return LearnerFixture(
            learner: learner,
            dictionary: dictionary,
            store: store,
            provider: provider,
            clock: clock,
            log: log,
            providerAvailable: providerAvailable
        )
    }
}
