import XCTest
@testable import APIVoiceInputCore

final class DictionaryLearnerTests: XCTestCase {
    private let obsidian = TermSuggestion(wrong: "オブシリアン", correct: "Obsidian")

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

    // MARK: 覚える条件

    func testAddsAWordSeenInTwoTextsOfTheSameBatch() async throws {
        let fixture = try makeLearnerFixture()
        fixture.provider.enqueue(.success([obsidian]))

        await fixture.learner.record("今日はオブシリアンにメモを書いた")
        await fixture.learner.record("あとでオブシリアンを開く予定です")
        await fixture.learner.record("夕飯はカレーにするつもり")

        XCTAssertEqual(fixture.dictionary.apply(to: "オブシリアンを使う").text, "Obsidianを使う")
        let auto = try String(contentsOf: fixture.store.autoDictionaryURL, encoding: .utf8)
        XCTAssertTrue(auto.contains("オブシリアン\tObsidian"), auto)
        XCTAssertTrue(fixture.log.lines.contains { $0.contains("learned=1") }, "\(fixture.log.lines)")
    }

    func testNeedsASecondSightingInALaterBatch() async throws {
        let fixture = try makeLearnerFixture()
        fixture.provider.enqueue(.success([obsidian]))
        fixture.provider.enqueue(.success([obsidian]))

        for text in ["今日はオブシリアンにメモを書いた", "夕飯はカレーにするつもり", "明日は雨になりそうです"] {
            await fixture.learner.record(text)
        }
        XCTAssertEqual(fixture.dictionary.apply(to: "オブシリアン").text, "オブシリアン")
        XCTAssertEqual(fixture.store.loadState().sightings["オブシリアン\tObsidian"], 1)

        for text in ["またオブシリアンを開いた", "電車が少し遅れている", "駅前で買い物をした"] {
            await fixture.learner.record(text)
        }

        XCTAssertEqual(fixture.dictionary.apply(to: "オブシリアン").text, "Obsidian")
        XCTAssertNil(fixture.store.loadState().sightings["オブシリアン\tObsidian"])
        XCTAssertEqual(fixture.store.loadState().promoted, ["オブシリアン\tObsidian"])
    }

    func testAddsAVariantOfAKnownTermAtOnce() async throws {
        let fixture = try makeLearnerFixture(manual: "ソニオックス\tSoniox\n")
        fixture.provider.enqueue(.success([TermSuggestion(wrong: "ソニョックス", correct: "Soniox")]))

        for text in ["さっきソニョックスの料金を調べた", "夕飯はカレーにするつもり", "明日は雨になりそうです"] {
            await fixture.learner.record(text)
        }

        XCTAssertEqual(fixture.dictionary.apply(to: "ソニョックス").text, "Soniox")
    }

    func testAVariantOfAKnownTermNeedsTwoSightingsWhenTheAIWasNotSure() async throws {
        let fixture = try makeLearnerFixture(manual: "ソニオックス\tSoniox\n")
        fixture.provider.enqueue(.success([TermSuggestion(wrong: "ソニョックス", correct: "Soniox", isConfident: false)]))

        for text in ["さっきソニョックスの料金を調べた", "夕飯はカレーにするつもり", "明日は雨になりそうです"] {
            await fixture.learner.record(text)
        }

        XCTAssertEqual(fixture.dictionary.apply(to: "ソニョックス").text, "ソニョックス")
        XCTAssertEqual(fixture.store.loadState().sightings["ソニョックス\tSoniox"], 1)
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

    func testLimitsHowManyWordsAreAddedPerDay() async throws {
        let fixture = try makeLearnerFixture { $0.maxPromotionsPerDay = 1 }
        fixture.provider.enqueue(.success([obsidian, TermSuggestion(wrong: "ソニョックス", correct: "Soniox")]))

        for text in ["オブシリアンとソニョックスを比べた", "またオブシリアンとソニョックスの話をした", "夕飯はカレーにするつもり"] {
            await fixture.learner.record(text)
        }

        XCTAssertEqual(fixture.dictionary.apply(to: "オブシリアン").text, "Obsidian")
        XCTAssertEqual(fixture.dictionary.apply(to: "ソニョックス").text, "ソニョックス")
    }

    // MARK: 消された語・失敗

    func testNeverAddsAgainAWordTheUserDeleted() async throws {
        let fixture = try makeLearnerFixture()
        fixture.provider.enqueue(.success([obsidian]))
        fixture.provider.enqueue(.success([obsidian]))
        for text in ["今日はオブシリアンにメモを書いた", "あとでオブシリアンを開く予定です", "夕飯はカレーにするつもり"] {
            await fixture.learner.record(text)
        }
        XCTAssertEqual(fixture.dictionary.apply(to: "オブシリアン").text, "Obsidian")

        try "# 全部消した\n".write(to: fixture.store.autoDictionaryURL, atomically: true, encoding: .utf8)
        for text in ["またオブシリアンを開いた", "もう一度オブシリアンに書いた", "電車が少し遅れている"] {
            await fixture.learner.record(text)
        }

        XCTAssertEqual(fixture.dictionary.apply(to: "オブシリアン").text, "オブシリアン")
        XCTAssertEqual(fixture.store.loadState().rejected, ["オブシリアン\tObsidian"])
        XCTAssertEqual(fixture.store.loadState().promoted, [])
    }

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

    // MARK: ログ

    func testLogsCountsOnly() async throws {
        let fixture = try makeLearnerFixture()
        fixture.provider.enqueue(.success([obsidian]))

        for text in ["今日はオブシリアンにメモを書いた", "あとでオブシリアンを開く予定です", "夕飯はカレーにするつもり"] {
            await fixture.learner.record(text)
        }

        XCTAssertFalse(fixture.log.lines.isEmpty)
        let everything = fixture.log.lines.joined(separator: "\n")
        for secret in ["オブシリアン", "Obsidian", "カレー", "メモ"] {
            XCTAssertFalse(everything.contains(secret), secret)
        }
    }
}
