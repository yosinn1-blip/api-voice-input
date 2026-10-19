import XCTest
@testable import APIVoiceInputCore

final class DictionaryLearnerTests: XCTestCase {
    private let obsidian = TermSuggestion(wrong: "オブシリアン", correct: "Obsidian")
    private let soniox = TermSuggestion(wrong: "ソニョックス", correct: "Soniox")

    /// 3文を渡して、1回分の問い合わせを起こす。`word` を含むのは最初の1文だけ。
    private func feedOneBatch(_ fixture: LearnerFixture, mentioning word: String) async {
        for text in ["さっき\(word)を使ってみた", "夕飯はカレーにするつもり", "明日は雨になりそうです"] {
            await fixture.learner.record(text)
        }
    }

    // MARK: いつ聞くか

    func testWaitsUntilEnoughTextsAreQueued() async throws {
        let fixture = try makeLearnerFixture()

        await fixture.learner.record("今日はオブシリアンにメモを書いた")
        await fixture.learner.record("あとでオブシリアンを開く予定です")

        XCTAssertEqual(fixture.provider.calls.count, 0)
    }

    func testAsksOnceWhenTheBatchIsFullAndTellsTheKnownTerms() async throws {
        let fixture = try makeLearnerFixture(manual: "グロック\tGroq\nグロッグ\tGroq\nソニオックス\tSoniox\n")
        let texts = ["今日はオブシリアンにメモを書いた", "あとでオブシリアンを開く予定です", "夕飯はカレーにするつもり"]

        for text in texts {
            await fixture.learner.record(text)
        }

        XCTAssertEqual(fixture.provider.calls.count, 1)
        XCTAssertEqual(fixture.provider.calls.first?.texts, texts)
        XCTAssertEqual(fixture.provider.calls.first?.knownTerms, ["Groq", "Soniox"])
    }

    func testOnlyEnglishTermsAreSentAsHints() async throws {
        let fixture = try makeLearnerFixture(manual: "ざんねん\t残念\nくらたに\t倉谷\nグロック\tGroq\nじゃぱん\tJapan Post\n")

        for text in ["一つ目の文章です。", "二つ目の文章です。", "三つ目の文章です。"] {
            await fixture.learner.record(text)
        }

        XCTAssertEqual(fixture.provider.calls.first?.knownTerms, ["Groq", "Japan Post"])
    }

    func testAsksAfterWaitingLongEvenWithFewTexts() async throws {
        let fixture = try makeLearnerFixture()

        await fixture.learner.record("今日はオブシリアンにメモを書いた")
        fixture.clock.advance(601)
        await fixture.learner.record("あとでオブシリアンを開く予定です")

        XCTAssertEqual(fixture.provider.calls.count, 1)
        XCTAssertEqual(fixture.provider.calls.first?.texts.count, 2)
    }

    func testWaitsWithoutAnAPIKeyAndAsksAsSoonAsThereIsOne() async throws {
        let fixture = try makeLearnerFixture()
        fixture.providerAvailable.isOn = false

        for text in ["一つ目の文章です。", "二つ目の文章です。", "三つ目の文章です。"] {
            await fixture.learner.record(text)
        }
        XCTAssertEqual(fixture.provider.calls.count, 0)

        fixture.providerAvailable.isOn = true
        await fixture.learner.record("四つ目の文章です。")

        XCTAssertEqual(fixture.provider.calls.count, 1)
        XCTAssertEqual(fixture.provider.calls.first?.texts.count, 4)
    }

    func testIgnoresTheSameTextSaidTwice() async throws {
        let fixture = try makeLearnerFixture()

        for _ in 1...3 {
            await fixture.learner.record("さっきと同じことをもう一度言った")
        }
        XCTAssertEqual(fixture.provider.calls.count, 0, "同じ文は1つとして数える")

        await fixture.learner.record("別の文章を言ってみた")
        await fixture.learner.record("さらに別の文章も言った")

        XCTAssertEqual(fixture.provider.calls.count, 1)
        XCTAssertEqual(fixture.provider.calls.first?.texts.count, 3)
    }

    func testForgetsTheQueuedTextsWhenToldTo() async throws {
        let fixture = try makeLearnerFixture()
        await fixture.learner.record("一つ目の文章です。")
        await fixture.learner.record("二つ目の文章です。")

        await fixture.learner.clearQueue()
        let after = ["三つ目の文章です。", "四つ目の文章です。", "五つ目の文章です。"]
        for text in after {
            await fixture.learner.record(text)
        }

        XCTAssertEqual(fixture.provider.calls.count, 1)
        XCTAssertEqual(fixture.provider.calls.first?.texts, after)
    }

    func testSkipsTextsThatLookPrivate() async throws {
        let fixture = try makeLearnerFixture()
        let privateTexts = [
            "連絡先は090-1234-5678です", "メールは abc@example.com です", "https://example.com/page を見て",
            "パスワードを変更しておいた", "マイナンバーカードを作りに行く"
        ]
        for text in privateTexts {
            await fixture.learner.record(text)
        }
        XCTAssertEqual(fixture.provider.calls.count, 0)

        let plain = ["一つ目の文章です。", "二つ目の文章です。", "三つ目の文章です。"]
        for text in plain {
            await fixture.learner.record(text)
        }

        XCTAssertEqual(fixture.provider.calls.first?.texts, plain)
    }

    // MARK: オフにされたとき

    func testDoesNothingWhileLearningIsOff() async throws {
        let fixture = try makeLearnerFixture()
        fixture.learningEnabled.isOn = false

        for text in ["一つ目の文章です。", "二つ目の文章です。", "三つ目の文章です。"] {
            await fixture.learner.record(text)
        }
        XCTAssertEqual(fixture.provider.calls.count, 0)

        fixture.learningEnabled.isOn = true
        let after = ["四つ目の文章です。", "五つ目の文章です。", "六つ目の文章です。"]
        for text in after {
            await fixture.learner.record(text)
        }

        XCTAssertEqual(fixture.provider.calls.first?.texts, after, "オフの間の文章は残らない")
    }

    func testForgetsTextsThatWereBeingSentWhenLearningWasTurnedOff() async throws {
        let fixture = try makeLearnerFixture()
        let switchOff = fixture.learningEnabled
        fixture.provider.onNextCall { switchOff.isOn = false }
        fixture.provider.enqueue(.failure(VoiceInputError.providerRateLimited("groq")))
        for text in ["一つ目の文章です。", "二つ目の文章です。", "三つ目の文章です。"] {
            await fixture.learner.record(text)
        }
        XCTAssertEqual(fixture.provider.calls.count, 1)

        fixture.learningEnabled.isOn = true
        fixture.clock.advance(901)
        let after = ["四つ目の文章です。", "五つ目の文章です。", "六つ目の文章です。"]
        for text in after {
            await fixture.learner.record(text)
        }

        XCTAssertEqual(fixture.provider.calls.count, 2)
        XCTAssertEqual(fixture.provider.calls.last?.texts, after, "送信中にオフにした文章は、失敗しても戻さない")
    }

    func testIgnoresTheAnswerWhenLearningWasTurnedOffWhileAsking() async throws {
        let fixture = try makeLearnerFixture()
        let switchOff = fixture.learningEnabled
        fixture.provider.onNextCall { switchOff.isOn = false }
        fixture.provider.enqueue(.success([obsidian]))

        await feedOneBatch(fixture, mentioning: "オブシリアン")

        XCTAssertEqual(fixture.store.loadState().sightings, [:])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.store.autoDictionaryURL.path))
    }

    // MARK: 覚える条件

    func testDoesNotAddAWordJustBecauseTwoTextsOfOneBatchMentionedIt() async throws {
        let fixture = try makeLearnerFixture()
        fixture.provider.enqueue(.success([obsidian]))

        for text in ["今日はオブシリアンにメモを書いた", "あとでオブシリアンを開く予定です", "夕飯はカレーにするつもり"] {
            await fixture.learner.record(text)
        }

        XCTAssertEqual(fixture.dictionary.apply(to: "オブシリアン").text, "オブシリアン")
        XCTAssertEqual(fixture.store.loadState().sightings["オブシリアン\tObsidian"], 1, "1回の問い合わせでは1回と数える")
    }

    func testNeedsASecondSightingInALaterBatch() async throws {
        let fixture = try makeLearnerFixture()
        fixture.provider.enqueue(.success([obsidian]))
        fixture.provider.enqueue(.success([obsidian]))

        await feedOneBatch(fixture, mentioning: "オブシリアン")
        XCTAssertEqual(fixture.dictionary.apply(to: "オブシリアン").text, "オブシリアン")
        XCTAssertEqual(fixture.store.loadState().sightings["オブシリアン\tObsidian"], 1)

        await feedOneBatch(fixture, mentioning: "オブシリアン")

        XCTAssertEqual(fixture.dictionary.apply(to: "オブシリアン").text, "Obsidian")
        XCTAssertNil(fixture.store.loadState().sightings["オブシリアン\tObsidian"])
        XCTAssertEqual(fixture.store.loadState().promoted, ["オブシリアン\tObsidian"])
        let auto = try String(contentsOf: fixture.store.autoDictionaryURL, encoding: .utf8)
        XCTAssertTrue(auto.contains("オブシリアン\tObsidian"), auto)
        XCTAssertTrue(fixture.log.lines.contains { $0.contains("learned=1") }, "\(fixture.log.lines)")
    }

    func testAddsAVariantThatIsOneCharacterAwayFromAKnownFormAtOnce() async throws {
        let fixture = try makeLearnerFixture(manual: "ソニオックス\tSoniox\n")
        fixture.provider.enqueue(.success([soniox]))

        await feedOneBatch(fixture, mentioning: "ソニョックス")

        XCTAssertEqual(fixture.dictionary.apply(to: "ソニョックス").text, "Soniox")
    }

    func testDoesNotAddAFarVariantOfAKnownTermAtOnce() async throws {
        let fixture = try makeLearnerFixture(manual: "ソニオックス\tSoniox\n")
        fixture.provider.enqueue(.success([TermSuggestion(wrong: "ゾーニックス", correct: "Soniox")]))

        await feedOneBatch(fixture, mentioning: "ゾーニックス")

        XCTAssertEqual(fixture.dictionary.apply(to: "ゾーニックス").text, "ゾーニックス")
        XCTAssertEqual(fixture.store.loadState().sightings["ゾーニックス\tSoniox"], 1)
    }

    func testAVariantNeedsTwoSightingsWhenTheAIWasNotSure() async throws {
        let fixture = try makeLearnerFixture(manual: "ソニオックス\tSoniox\n")
        fixture.provider.enqueue(.success([TermSuggestion(wrong: "ソニョックス", correct: "Soniox", isConfident: false)]))

        await feedOneBatch(fixture, mentioning: "ソニョックス")

        XCTAssertEqual(fixture.dictionary.apply(to: "ソニョックス").text, "ソニョックス")
        XCTAssertEqual(fixture.store.loadState().sightings["ソニョックス\tSoniox"], 1)
    }

    func testDoesNotAddAWordWhenTwoDifferentAnswersCompeteInOneBatch() async throws {
        let fixture = try makeLearnerFixture()
        let both = [TermSuggestion(wrong: "ドッカー", correct: "Docker"), TermSuggestion(wrong: "ドッカー", correct: "Dokker")]
        fixture.provider.enqueue(.success(both))
        fixture.provider.enqueue(.success(both))

        await feedOneBatch(fixture, mentioning: "ドッカー")
        await feedOneBatch(fixture, mentioning: "ドッカー")

        XCTAssertEqual(fixture.dictionary.apply(to: "ドッカー").text, "ドッカー")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.store.autoDictionaryURL.path))
    }

    func testDoesNotAddAWordWhenAnEarlierBatchAnsweredSomethingElse() async throws {
        let fixture = try makeLearnerFixture()
        fixture.provider.enqueue(.success([TermSuggestion(wrong: "ドッカー", correct: "Dokker")]))
        fixture.provider.enqueue(.success([TermSuggestion(wrong: "ドッカー", correct: "Docker")]))
        fixture.provider.enqueue(.success([TermSuggestion(wrong: "ドッカー", correct: "Docker")]))

        await feedOneBatch(fixture, mentioning: "ドッカー")
        await feedOneBatch(fixture, mentioning: "ドッカー")
        await feedOneBatch(fixture, mentioning: "ドッカー")

        XCTAssertEqual(fixture.dictionary.apply(to: "ドッカー").text, "ドッカー")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.store.autoDictionaryURL.path))
    }

    func testIgnoresSuggestionsThatFailTheChecks() async throws {
        let fixture = try makeLearnerFixture(manual: "グロック\tGroq\n", commonWords: ["カーソル"])
        fixture.provider.enqueue(.success([
            TermSuggestion(wrong: "後藤", correct: "ごと"),
            TermSuggestion(wrong: "オブシリアン", correct: "オブシディアン"),
            TermSuggestion(wrong: "ソニョックス", correct: "Soniox"),
            TermSuggestion(wrong: "カーソル", correct: "Cursor"),
            TermSuggestion(wrong: "グロック", correct: "Groq")
        ]))

        for text in ["後藤さんがオブシリアンを使う", "カーソルを動かして", "グロックを呼び出す処理"] {
            await fixture.learner.record(text)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.store.autoDictionaryURL.path))
        XCTAssertTrue(fixture.log.lines.contains { $0.contains("accepted=0") }, "\(fixture.log.lines)")
        XCTAssertTrue(fixture.log.lines.contains { $0.contains("suggestions=5") }, "\(fixture.log.lines)")
    }

    func testLogsHowManyWereRejectedForEachReasonWithoutAnyText() async throws {
        let fixture = try makeLearnerFixture(manual: "グロック\tGroq\n", commonWords: ["カーソル"])
        fixture.provider.enqueue(.success([
            TermSuggestion(wrong: "後藤", correct: "ごと"),
            TermSuggestion(wrong: "ソニョックス", correct: "Soniox"),
            TermSuggestion(wrong: "カーソル", correct: "Cursor"),
            TermSuggestion(wrong: "グロック", correct: "Groq")
        ]))

        for text in ["後藤さんがオブシリアンを使う", "カーソルを動かして", "グロックを呼び出す処理"] {
            await fixture.learner.record(text)
        }

        let line = try XCTUnwrap(fixture.log.lines.first { $0.contains("rejected=") })
        for expected in ["badCorrect:1", "notInTexts:1", "commonWord:1", "alreadyKnown:1"] {
            XCTAssertTrue(line.contains(expected), line)
        }
        for secret in ["後藤", "ソニョックス", "カーソル", "グロック", "Groq"] {
            XCTAssertFalse(line.contains(secret), line)
        }
    }

    func testDoesNotShortenAnExtendedNameToItsFirstWord() async throws {
        let fixture = try makeLearnerFixture(manual: "クロード\tClaude\nクロードコード\tClaude Code\n")
        fixture.provider.enqueue(.success([TermSuggestion(wrong: "クロードコート", correct: "Claude")]))
        fixture.provider.enqueue(.success([TermSuggestion(wrong: "クロードコート", correct: "Claude")]))

        await feedOneBatch(fixture, mentioning: "クロードコート")
        await feedOneBatch(fixture, mentioning: "クロードコート")

        XCTAssertEqual(fixture.dictionary.apply(to: "クロードコートです").text, "Claudeコートです")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.store.autoDictionaryURL.path))
    }

    func testLimitsHowManyWordsAreAddedPerDay() async throws {
        let fixture = try makeLearnerFixture { $0.maxPromotionsPerDay = 1 }
        fixture.provider.enqueue(.success([obsidian, soniox]))
        fixture.provider.enqueue(.success([obsidian, soniox]))

        for _ in 1...2 {
            for text in ["オブシリアンとソニョックスを比べた", "夕飯はカレーにするつもり", "明日は雨になりそうです"] {
                await fixture.learner.record(text)
            }
        }

        XCTAssertEqual(fixture.dictionary.apply(to: "オブシリアン").text, "Obsidian")
        XCTAssertEqual(fixture.dictionary.apply(to: "ソニョックス").text, "ソニョックス")
    }

    func testStopsAddingWordsAtTheLimitOfLearnedEntries() async throws {
        let fixture = try makeLearnerFixture { $0.maxLearnedEntries = 1 }
        fixture.provider.enqueue(.success([obsidian, soniox]))
        fixture.provider.enqueue(.success([obsidian, soniox]))

        for _ in 1...2 {
            for text in ["オブシリアンとソニョックスを比べた", "夕飯はカレーにするつもり", "明日は雨になりそうです"] {
                await fixture.learner.record(text)
            }
        }

        XCTAssertEqual(fixture.dictionary.apply(to: "オブシリアン").text, "Obsidian")
        XCTAssertEqual(fixture.dictionary.apply(to: "ソニョックス").text, "ソニョックス")
        XCTAssertEqual(fixture.store.loadState().promoted.count, 1)
    }

    func testDoesNotAddWordsWhenTheSystemDictionaryCannotBeUsed() async throws {
        let fixture = try makeLearnerFixture(commonWordsUsable: false)
        fixture.provider.enqueue(.success([obsidian]))
        fixture.provider.enqueue(.success([obsidian]))

        await feedOneBatch(fixture, mentioning: "オブシリアン")
        await feedOneBatch(fixture, mentioning: "オブシリアン")

        XCTAssertEqual(fixture.dictionary.apply(to: "オブシリアン").text, "オブシリアン")
        XCTAssertEqual(fixture.store.loadState().sightings["オブシリアン\tObsidian"], 2, "数えるだけは続ける")
        XCTAssertEqual(fixture.log.lines.filter { $0.contains("paused") }.count, 1, "止めたことは1度だけ記録する")
    }

    // MARK: 書けなかったとき・消されたとき

    func testDoesNotRememberAWordItCouldNotWrite() async throws {
        let fixture = try makeLearnerFixture(autoDirectoryIsBlocked: true)
        fixture.provider.enqueue(.success([obsidian]))
        fixture.provider.enqueue(.success([obsidian]))

        await feedOneBatch(fixture, mentioning: "オブシリアン")
        await feedOneBatch(fixture, mentioning: "オブシリアン")

        XCTAssertEqual(fixture.store.loadState().promoted, [])
        XCTAssertEqual(fixture.store.loadState().rejected, [], "書けなかっただけで、消されたことにはしない")
        XCTAssertTrue(fixture.log.lines.contains { $0.contains("failed") && $0.contains("write") }, "\(fixture.log.lines)")
    }

    func testNeverAddsAgainAWordTheUserDeleted() async throws {
        let fixture = try makeLearnerFixture()
        for _ in 1...2 {
            fixture.provider.enqueue(.success([obsidian]))
        }
        await feedOneBatch(fixture, mentioning: "オブシリアン")
        await feedOneBatch(fixture, mentioning: "オブシリアン")
        XCTAssertEqual(fixture.dictionary.apply(to: "オブシリアン").text, "Obsidian")

        try "# 行を消した\n".write(to: fixture.store.autoDictionaryURL, atomically: true, encoding: .utf8)
        for _ in 1...3 {
            fixture.provider.enqueue(.success([TermSuggestion(wrong: "オブシリアン", correct: "Obsidian Notes")]))
            await feedOneBatch(fixture, mentioning: "オブシリアン")
        }

        XCTAssertEqual(fixture.dictionary.apply(to: "オブシリアン").text, "オブシリアン")
        XCTAssertEqual(fixture.store.loadState().rejected, ["オブシリアン\tObsidian"])
        XCTAssertEqual(fixture.store.loadState().promoted, [])
    }

    func testStartsOverWithoutBlacklistingWhenTheWholeFileIsDeleted() async throws {
        let fixture = try makeLearnerFixture()
        for _ in 1...2 {
            fixture.provider.enqueue(.success([obsidian]))
        }
        await feedOneBatch(fixture, mentioning: "オブシリアン")
        await feedOneBatch(fixture, mentioning: "オブシリアン")
        XCTAssertEqual(fixture.dictionary.apply(to: "オブシリアン").text, "Obsidian")

        try FileManager.default.removeItem(at: fixture.store.autoDictionaryURL)
        await feedOneBatch(fixture, mentioning: "別の話")
        XCTAssertEqual(fixture.store.loadState().promoted, [])
        XCTAssertEqual(fixture.store.loadState().rejected, [], "ファイルごと消したのは、やり直し")

        for _ in 1...2 {
            fixture.provider.enqueue(.success([obsidian]))
            await feedOneBatch(fixture, mentioning: "オブシリアン")
        }
        XCTAssertEqual(fixture.dictionary.apply(to: "オブシリアン").text, "Obsidian")
    }

    // MARK: 失敗

    func testKeepsTheTextsAndTriesAgainLaterAfterARateLimit() async throws {
        let fixture = try makeLearnerFixture()
        fixture.provider.enqueue(.failure(VoiceInputError.providerRateLimited("groq")))
        let first = ["一つ目の文章です。", "二つ目の文章です。", "三つ目の文章です。"]
        for text in first {
            await fixture.learner.record(text)
        }
        XCTAssertEqual(fixture.provider.calls.count, 1)

        await fixture.learner.record("四つ目の文章です。")
        XCTAssertEqual(fixture.provider.calls.count, 1, "待ち時間のあいだは聞かない")

        fixture.clock.advance(901)
        await fixture.learner.record("五つ目の文章です。")

        XCTAssertEqual(fixture.provider.calls.count, 2)
        XCTAssertEqual(fixture.provider.calls.last?.texts, first + ["四つ目の文章です。", "五つ目の文章です。"])
        XCTAssertTrue(fixture.log.lines.contains { $0.contains("failed") && $0.contains("rateLimited") }, "\(fixture.log.lines)")
    }

    func testDropsTheTextsWhenTheAnswerCannotBeRead() async throws {
        let fixture = try makeLearnerFixture()
        fixture.provider.enqueue(.failure(TermSuggestionError.unreadableResponse))
        for text in ["一つ目の文章です。", "二つ目の文章です。", "三つ目の文章です。"] {
            await fixture.learner.record(text)
        }

        let second = ["四つ目の文章です。", "五つ目の文章です。", "六つ目の文章です。"]
        for text in second {
            await fixture.learner.record(text)
        }

        XCTAssertEqual(fixture.provider.calls.count, 2)
        XCTAssertEqual(fixture.provider.calls.last?.texts, second)
    }

    func testDropsTheTextsAndWaitsWhenTheRequestIsRefused() async throws {
        let fixture = try makeLearnerFixture()
        fixture.provider.enqueue(.failure(TermSuggestionError.requestRejected))
        for text in ["一つ目の文章です。", "二つ目の文章です。", "三つ目の文章です。"] {
            await fixture.learner.record(text)
        }

        for text in ["四つ目の文章です。", "五つ目の文章です。", "六つ目の文章です。"] {
            await fixture.learner.record(text)
        }
        XCTAssertEqual(fixture.provider.calls.count, 1, "鍵やモデルが拒否されたときは、すぐには聞き直さない")

        fixture.clock.advance(901)
        await fixture.learner.record("七つ目の文章です。")

        XCTAssertEqual(fixture.provider.calls.count, 2)
        XCTAssertEqual(fixture.provider.calls.last?.texts.first, "四つ目の文章です。", "拒否された最初の3文は捨てる")
        XCTAssertTrue(fixture.log.lines.contains { $0.contains("failed") && $0.contains("rejected") }, "\(fixture.log.lines)")
    }

    func testStopsAskingAfterTheDailyLimit() async throws {
        let fixture = try makeLearnerFixture { $0.maxRequestsPerDay = 2 }
        for index in 1...9 {
            await fixture.learner.record("\(index)番目の文章です。")
        }
        XCTAssertEqual(fixture.provider.calls.count, 2)

        fixture.clock.advance(86_401)
        await fixture.learner.record("翌日の文章です。")

        XCTAssertEqual(fixture.provider.calls.count, 3)
    }

    func testDoesNotLookForTheKeyAgainOnceTheDailyLimitIsReached() async throws {
        let fixture = try makeLearnerFixture { $0.maxRequestsPerDay = 1 }

        for index in 1...9 {
            await fixture.learner.record("\(index)番目の文章です。")
        }

        XCTAssertEqual(fixture.provider.calls.count, 1)
        XCTAssertEqual(fixture.providerFactoryCalls.value, 1, "上限のあとは鍵を読みにいかない")
    }

    // MARK: ログ

    func testLogsCountsOnly() async throws {
        let fixture = try makeLearnerFixture()
        fixture.provider.enqueue(.success([obsidian]))
        fixture.provider.enqueue(.success([obsidian]))

        await feedOneBatch(fixture, mentioning: "オブシリアン")
        await feedOneBatch(fixture, mentioning: "オブシリアン")

        XCTAssertFalse(fixture.log.lines.isEmpty)
        XCTAssertTrue(fixture.log.lines.contains { $0.contains("entries=") }, "\(fixture.log.lines)")
        let everything = fixture.log.lines.joined(separator: "\n")
        for secret in ["オブシリアン", "Obsidian", "カレー", "メモ"] {
            XCTAssertFalse(everything.contains(secret), secret)
        }
    }
}
