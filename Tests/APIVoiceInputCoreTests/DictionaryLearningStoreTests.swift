import XCTest
@testable import APIVoiceInputCore

final class DictionaryLearningStoreTests: XCTestCase {
    // 2026-10-19 12:00 UTC（どのタイムゾーンでも 10/19）
    private let noon = Date(timeIntervalSince1970: 1_792_411_200)

    private func makeStore() throws -> DictionaryLearningStore {
        let directory = try makeTemporaryDirectory()
        return DictionaryLearningStore(
            autoDictionaryURL: directory.appendingPathComponent("dictionary-auto.txt"),
            stateURL: directory.appendingPathComponent("dictionary-learning.json")
        )
    }

    func testAppendCreatesTheFileWithAHeaderAndDatedEntries() throws {
        let store = try makeStore()

        store.appendEntries([TermSuggestion(wrong: "オブシリアン", correct: "Obsidian")], date: noon)

        let contents = try String(contentsOf: store.autoDictionaryURL, encoding: .utf8)
        XCTAssertEqual(contents.split(separator: "\n").first?.first, "#")
        XCTAssertTrue(contents.contains("# 2026-10-19 自動で追加\nオブシリアン\tObsidian\n"), contents)
    }

    func testAppendReportsWhetherItReallyWrote() throws {
        let store = try makeStore()
        XCTAssertFalse(store.autoDictionaryExists)
        XCTAssertTrue(store.appendEntries([TermSuggestion(wrong: "オブシリアン", correct: "Obsidian")], date: noon))
        XCTAssertTrue(store.autoDictionaryExists)

        let directory = try makeTemporaryDirectory()
        try Data("x".utf8).write(to: directory.appendingPathComponent("blocked"))
        let blockedStore = DictionaryLearningStore(
            autoDictionaryURL: directory.appendingPathComponent("blocked").appendingPathComponent("dictionary-auto.txt"),
            stateURL: directory.appendingPathComponent("state.json")
        )
        XCTAssertFalse(blockedStore.appendEntries([TermSuggestion(wrong: "オブシリアン", correct: "Obsidian")], date: noon))
    }

    func testAppendKeepsEarlierEntriesAndWritesTheHeaderOnce() throws {
        let store = try makeStore()

        store.appendEntries([TermSuggestion(wrong: "オブシリアン", correct: "Obsidian")], date: noon)
        store.appendEntries([TermSuggestion(wrong: "ソニョックス", correct: "Soniox")], date: noon)

        let contents = try String(contentsOf: store.autoDictionaryURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("オブシリアン\tObsidian"))
        XCTAssertTrue(contents.contains("ソニョックス\tSoniox"))
        XCTAssertEqual(contents.components(separatedBy: "自動で覚えた語").count - 1, 1, "見出しが2回書かれている")
    }

    func testAppendedEntriesWorkInTheDictionary() throws {
        let store = try makeStore()
        store.appendEntries(
            [TermSuggestion(wrong: "オブシリアン", correct: "Obsidian"), TermSuggestion(wrong: "ソニョックス", correct: "Soniox")],
            date: noon
        )
        let dictionary = ReplacementDictionary(
            fileURL: store.autoDictionaryURL.deletingLastPathComponent().appendingPathComponent("dictionary.txt"),
            additionalFileURLs: [store.autoDictionaryURL]
        )

        XCTAssertEqual(dictionary.apply(to: "オブシリアンとソニョックス").text, "ObsidianとSoniox")
    }

    func testReadAutoEntriesIsEmptyWhenTheFileIsMissingAndNilWhenUnreadable() throws {
        let store = try makeStore()
        XCTAssertEqual(store.readAutoEntries(), [])

        try Data([0xFF, 0xFE, 0x00, 0x81]).write(to: store.autoDictionaryURL)
        XCTAssertNil(store.readAutoEntries())

        try "# 見出し\nオブシリアン\tObsidian\n".write(to: store.autoDictionaryURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(store.readAutoEntries(), [ReplacementDictionary.Entry(wrong: "オブシリアン", correct: "Obsidian")])
    }

    func testStateStartsEmptyWhenTheFileIsMissingOrBroken() throws {
        let store = try makeStore()
        XCTAssertEqual(store.loadState(), DictionaryLearningState())

        try Data("これはJSONではない".utf8).write(to: store.stateURL)
        XCTAssertEqual(store.loadState(), DictionaryLearningState())
    }

    func testSavedStateComesBack() throws {
        let store = try makeStore()
        var state = DictionaryLearningState()
        state.sightings["オブシリアン\tObsidian"] = 1
        state.promoted = ["ソニョックス\tSoniox"]
        state.rejected = ["グロッグ\tGroq"]
        state.day = "2026-10-19"
        state.requestsToday = 3
        state.promotionsToday = 2

        store.saveState(state)

        XCTAssertEqual(store.loadState(), state)
    }

    func testSavedStateKeepsOnlyTheStrongestCandidates() throws {
        let store = try makeStore()
        var state = DictionaryLearningState()
        for index in 0..<300 {
            state.sightings["語\(index)\tWord\(index)"] = 1
        }
        state.sightings["残る語\tKeep"] = 5

        store.saveState(state)

        let loaded = store.loadState()
        XCTAssertEqual(loaded.sightings.count, DictionaryLearningStore.maximumSightings)
        XCTAssertEqual(loaded.sightings["残る語\tKeep"], 5)
    }

    func testFilesAreReadableOnlyByTheUser() throws {
        let store = try makeStore()

        store.appendEntries([TermSuggestion(wrong: "オブシリアン", correct: "Obsidian")], date: noon)
        store.saveState(DictionaryLearningState())

        for url in [store.autoDictionaryURL, store.stateURL] {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600, url.lastPathComponent)
        }
    }
}
