import XCTest
@testable import APIVoiceInputCore

final class ReplacementDictionaryTests: XCTestCase {
    // MARK: 置き換えの動き

    func testReplacesWrongWordWithCorrectWord() throws {
        let dictionary = try makeReplacementDictionary("グロック\tGroq\n")

        let result = dictionary.apply(to: "グロックで文字起こしします")

        XCTAssertEqual(result.text, "Groqで文字起こしします")
        XCTAssertEqual(result.count, 1)
    }

    func testCountsEveryReplacement() throws {
        let dictionary = try makeReplacementDictionary("グロック\tGroq\n")

        let result = dictionary.apply(to: "グロックとグロック")

        XCTAssertEqual(result.text, "GroqとGroq")
        XCTAssertEqual(result.count, 2)
    }

    func testKeepsSpacesInsideTheCorrectWord() throws {
        let dictionary = try makeReplacementDictionary("クロードコード\tClaude Code\n")

        XCTAssertEqual(dictionary.apply(to: "クロードコードを使う").text, "Claude Codeを使う")
    }

    func testLeavesTextWithoutMatchesUntouched() throws {
        let dictionary = try makeReplacementDictionary("グロック\tGroq\n")

        let result = dictionary.apply(to: "今日はいい天気です")

        XCTAssertEqual(result.text, "今日はいい天気です")
        XCTAssertEqual(result.count, 0)
    }

    func testLongerWrongWordWinsRegardlessOfLineOrder() throws {
        let shortFirst = try makeReplacementDictionary("ギット\tGit\nギットハブ\tGitHub\n")
        let longFirst = try makeReplacementDictionary("ギットハブ\tGitHub\nギット\tGit\n")

        XCTAssertEqual(shortFirst.apply(to: "ギットハブとギットを使う").text, "GitHubとGitを使う")
        XCTAssertEqual(longFirst.apply(to: "ギットハブとギットを使う").text, "GitHubとGitを使う")
    }

    func testLongerWrongWordWinsOverAShorterOneThatOverlapsIt() throws {
        let dictionary = try makeReplacementDictionary("AB\t1\nBCD\t2\n")

        let result = dictionary.apply(to: "ABCD")

        XCTAssertEqual(result.text, "A2")
        XCTAssertEqual(result.count, 1)
    }

    func testOverlappingWrongWordsOfSameLengthUseTheEarlierLine() throws {
        let abcFirst = try makeReplacementDictionary("ABC\t1\nBCD\t2\n")
        let bcdFirst = try makeReplacementDictionary("BCD\t2\nABC\t1\n")

        XCTAssertEqual(abcFirst.apply(to: "ABCD").text, "1D")
        XCTAssertEqual(bcdFirst.apply(to: "ABCD").text, "A2")
    }

    func testWhenTheSameWrongWordIsListedTwiceTheFirstLineWins() throws {
        let dictionary = try makeReplacementDictionary("グロック\tGroq\nグロック\tGrok\n")

        XCTAssertEqual(dictionary.apply(to: "グロック").text, "Groq")
    }

    func testReplacedTextIsNotReplacedAgain() throws {
        let dictionary = try makeReplacementDictionary("猫\t犬\n犬\t猫\n")

        let result = dictionary.apply(to: "猫と犬")

        XCTAssertEqual(result.text, "犬と猫")
        XCTAssertEqual(result.count, 2)
    }

    func testCorrectWordContainingTheWrongWordDoesNotGrow() throws {
        let dictionary = try makeReplacementDictionary("ソフト\tAPIソフト\n")

        XCTAssertEqual(dictionary.apply(to: "ソフトとソフト").text, "APIソフトとAPIソフト")
    }

    func testTreatsEntriesAsPlainTextNotRegularExpressions() throws {
        let dictionary = try makeReplacementDictionary("a.c\tX\n価格\t$1 (税込)\n")

        XCTAssertEqual(dictionary.apply(to: "abc a.c").text, "abc X")
        XCTAssertEqual(dictionary.apply(to: "価格").text, "$1 (税込)")
    }

    func testMatchingIsCaseSensitive() throws {
        let dictionary = try makeReplacementDictionary("groq\tGroq\n")

        XCTAssertEqual(dictionary.apply(to: "Groq GROQ groq").text, "Groq GROQ Groq")
    }

    // MARK: 辞書ファイルの書き方

    func testIgnoresCommentsAndBlankLines() throws {
        let dictionary = try makeReplacementDictionary(
            "# メモ\n\n   \nグロック\tGroq\n# ソニオックス\tSoniox\n"
        )

        // コメント行の中身が「誤り」として使われないこと（そのまま文章に出てきても置き換わらない）
        XCTAssertEqual(dictionary.apply(to: "グロックと# ソニオックス").text, "Groqと# ソニオックス")
    }

    func testIgnoresLinesWithoutTabOrWithAnEmptySide() throws {
        let dictionary = try makeReplacementDictionary(
            "タブなし Groq\n\tGroq\nソニオックス\t\nグロック\tGroq\n"
        )

        let result = dictionary.apply(to: "ソニオックスとタブなしとグロック")

        XCTAssertEqual(result.text, "ソニオックスとタブなしとGroq")
        XCTAssertEqual(result.count, 1)
    }

    func testToleratesWindowsLineEndingsBOMAndPaddingSpaces() throws {
        let dictionary = try makeReplacementDictionary(
            "\u{FEFF}グロック \t Groq\r\nギットハブ\t\tGitHub\r\n"
        )

        XCTAssertEqual(dictionary.apply(to: "グロックとギットハブ").text, "GroqとGitHub")
    }

    // MARK: ファイルの状態

    func testDoesNothingWhenFileDoesNotExist() throws {
        let fileURL = try makeTemporaryDirectory().appendingPathComponent("dictionary.txt")
        let dictionary = ReplacementDictionary(fileURL: fileURL)

        let result = dictionary.apply(to: "グロックを使う")

        XCTAssertEqual(result.text, "グロックを使う")
        XCTAssertEqual(result.count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testDoesNothingWhenFileHasNoEntries() throws {
        let dictionary = try makeReplacementDictionary("# コメントだけ\n\n")

        let result = dictionary.apply(to: "グロックを使う")

        XCTAssertEqual(result.text, "グロックを使う")
        XCTAssertEqual(result.count, 0)
    }

    func testDoesNothingWhenFileIsNotUTF8() throws {
        let fileURL = try makeTemporaryDirectory().appendingPathComponent("dictionary.txt")
        try Data([0xFF, 0xFE, 0x00, 0x81]).write(to: fileURL)
        let dictionary = ReplacementDictionary(fileURL: fileURL)

        let result = dictionary.apply(to: "グロックを使う")

        XCTAssertEqual(result.text, "グロックを使う")
        XCTAssertEqual(result.count, 0)
    }

    func testStopsReplacingWhenFileIsDeleted() throws {
        let dictionary = try makeReplacementDictionary("グロック\tGroq\n")
        XCTAssertEqual(dictionary.apply(to: "グロック").text, "Groq")

        try FileManager.default.removeItem(at: dictionary.fileURL)

        XCTAssertEqual(dictionary.apply(to: "グロック").text, "グロック")
    }

    func testReloadsWhenModificationDateChanges() throws {
        let dictionary = try makeReplacementDictionary("グロック\tGroq\n")
        try setModificationDate(1_000_000_000, of: dictionary.fileURL)
        XCTAssertEqual(dictionary.apply(to: "グロック").text, "Groq")

        try "グロック\tGROQ\n".write(to: dictionary.fileURL, atomically: true, encoding: .utf8)
        try setModificationDate(1_000_000_100, of: dictionary.fileURL)

        XCTAssertEqual(dictionary.apply(to: "グロック").text, "GROQ")
    }

    func testKeepsLoadedEntriesWhileModificationDateIsUnchanged() throws {
        let dictionary = try makeReplacementDictionary("グロック\tGroq\n")
        try setModificationDate(1_000_000_000, of: dictionary.fileURL)
        XCTAssertEqual(dictionary.apply(to: "グロック").text, "Groq")

        try "グロック\tGROQ\n".write(to: dictionary.fileURL, atomically: true, encoding: .utf8)
        try setModificationDate(1_000_000_000, of: dictionary.fileURL)

        XCTAssertEqual(dictionary.apply(to: "グロック").text, "Groq")
    }

    // MARK: 見本ファイル

    func testCreatesSampleFileWhenMissing() throws {
        let fileURL = try makeTemporaryDirectory()
            .appendingPathComponent("APIVoiceInput")
            .appendingPathComponent("dictionary.txt")
        let dictionary = ReplacementDictionary(fileURL: fileURL)

        XCTAssertTrue(dictionary.createSampleFileIfNeeded())

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        let result = dictionary.apply(to: "グロックとソニオックスとクロードコードとギットハブ")
        XCTAssertEqual(result.text, "GroqとSonioxとClaude CodeとGitHub")
        XCTAssertEqual(result.count, 4)
    }

    func testSampleFileStartsWithHowToWriteComments() {
        let firstLine = ReplacementDictionary.sampleContents.split(separator: "\n").first
        XCTAssertEqual(firstLine?.first, "#")
    }

    func testDoesNotOverwriteAnExistingFile() throws {
        let custom = try makeReplacementDictionary("自分の語\tMyWord\n")
        XCTAssertFalse(custom.createSampleFileIfNeeded())
        XCTAssertEqual(try String(contentsOf: custom.fileURL, encoding: .utf8), "自分の語\tMyWord\n")

        let empty = try makeReplacementDictionary("")
        XCTAssertFalse(empty.createSampleFileIfNeeded())
        XCTAssertEqual(try String(contentsOf: empty.fileURL, encoding: .utf8), "")
    }

    private func setModificationDate(_ secondsSince1970: TimeInterval, of fileURL: URL) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: secondsSince1970)],
            ofItemAtPath: fileURL.path
        )
    }
}
