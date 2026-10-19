import CoreServices
import XCTest
@testable import APIVoiceInputCore

final class TermSuggestionFilterTests: XCTestCase {
    private func rejection(
        _ wrong: String,
        _ correct: String,
        texts: [String] = ["今日はオブシリアンにメモした", "今はGlogを使っている", "後藤さんとカーソルを動かす"],
        existing: [ReplacementDictionary.Entry] = [],
        rejectedKeys: Set<String> = [],
        commonWords: Set<String> = []
    ) -> TermSuggestionRejection? {
        TermSuggestionFilter.rejection(
            for: TermSuggestion(wrong: wrong, correct: correct),
            texts: texts,
            existingEntries: existing,
            rejectedKeys: rejectedKeys,
            commonWords: FixedWordChecker(commonWords)
        )
    }

    func testAcceptsAKatakanaMisrecognitionOfALatinName() {
        XCTAssertNil(rejection("オブシリアン", "Obsidian"))
    }

    func testAcceptsAGarbledLatinName() {
        XCTAssertNil(rejection("Glog", "Groq"))
    }

    func testAcceptsCorrectWordsWithSpacesDigitsAndSymbols() {
        XCTAssertNil(rejection("クロードコート", "Claude Code", texts: ["クロードコートを使う"]))
        XCTAssertNil(rejection("ワンパスワード", "1Password", texts: ["ワンパスワードに保存した"]))
        XCTAssertNil(rejection("ノードジェイエス", "Node.js", texts: ["ノードジェイエスで動かす"]))
    }

    func testRejectsAnEmptyOrUnchangedSuggestion() {
        XCTAssertEqual(rejection("オブシリアン", ""), .empty)
        XCTAssertEqual(rejection("", "Obsidian"), .empty)
        XCTAssertEqual(rejection("Glog", "Glog"), .noRealChange)
    }

    func testRejectsAChangeOfLetterCaseOnly() {
        XCTAssertEqual(rejection("glog", "Glog", texts: ["glogを使う"]), .noRealChange)
    }

    func testRejectsWrongWordsThatAreNotPlainKatakanaOrLatin() {
        XCTAssertEqual(rejection("後藤", "Goto"), .badWrong)
        XCTAssertEqual(rejection("ごとに", "Goto"), .badWrong)
        XCTAssertEqual(rejection("オブシリアンを", "Obsidian", texts: ["オブシリアンを使う"]), .badWrong)
        XCTAssertEqual(rejection("Glog です", "Groq", texts: ["Glog ですね"]), .badWrong)
    }

    func testRejectsWrongWordsThatAreTooShortOrTooLong() {
        XCTAssertEqual(rejection("BI", "API", texts: ["BIを使う"]), .badWrong)
        XCTAssertEqual(rejection("mgo", "Mongo", texts: ["mgoを使う"]), .badWrong)
        XCTAssertEqual(rejection("ソニ", "Soni", texts: ["ソニを使う"]), .badWrong)
        XCTAssertEqual(rejection("ソニョ", "Soni", texts: ["ソニョを使う"]), .badWrong)
        let long = String(repeating: "ア", count: 31)
        XCTAssertEqual(rejection(long, "Long", texts: [long]), .badWrong)
    }

    func testRejectsCorrectWordsThatAreNotPlainLatin() {
        XCTAssertEqual(rejection("オブシリアン", "オブシディアン"), .badCorrect)
        XCTAssertEqual(rejection("オブシリアン", "黒曜石"), .badCorrect)
        XCTAssertEqual(rejection("オブシリアン", "Obsidian です"), .badCorrect)
        XCTAssertEqual(rejection("オブシリアン", "O"), .badCorrect)
        XCTAssertEqual(rejection("オブシリアン", " Obsidian"), .badCorrect)
        XCTAssertEqual(rejection("オブシリアン", "Obsidian\nApp"), .badCorrect)
    }

    func testRejectsAWrongWordThatIsNotInTheTexts() {
        XCTAssertEqual(rejection("ソニョックス", "Soniox"), .notInTexts)
    }

    func testRejectsWordsTheDictionaryAlreadyHas() {
        let knownWrong = ReplacementDictionary.Entry(wrong: "オブシリアン", correct: "Obsidian")
        let knownCorrect = ReplacementDictionary.Entry(wrong: "グロック", correct: "Glog")

        XCTAssertEqual(rejection("オブシリアン", "Obsidian", existing: [knownWrong]), .alreadyKnown)
        XCTAssertEqual(rejection("Glog", "Groq", existing: [knownCorrect]), .alreadyKnown)
    }

    func testRejectsALongerWordThatSwallowsAKnownWrongWordAndKeepsTheSameCorrectWord() {
        // 「クロードコート」(Claude Code の崩れ)を「Claude」だけに直すと、「コート」が消えてしまう
        let existing = [ReplacementDictionary.Entry(wrong: "クロード", correct: "Claude")]
        let texts = ["クロードコートで修正をお願いした"]

        XCTAssertEqual(rejection("クロードコート", "Claude", texts: texts, existing: existing), .swallowsKnownWord)
        XCTAssertNil(rejection("クロードコート", "Claude Code", texts: texts, existing: existing))
    }

    func testRejectsAWrongWordTheUserDeletedBeforeWhateverItWasChangedTo() {
        XCTAssertEqual(rejection("オブシリアン", "Obsidian", rejectedKeys: ["オブシリアン\tObsidian"]), .rejectedBefore)
        XCTAssertEqual(rejection("オブシリアン", "Obsidian Notes", rejectedKeys: ["オブシリアン\tObsidian"]), .rejectedBefore)
        XCTAssertNil(rejection("オブシリアン", "Obsidian", rejectedKeys: ["オブシデアン\tObsidian"]))
    }

    func testRejectsAWrongWordThatIsOnlyPartOfAKnownWord() {
        // 「Claud→Claude」を足すと、正しく書けた「Claude」が「Claudee」になってしまう
        let existing = [ReplacementDictionary.Entry(wrong: "クロード", correct: "Claude")]

        XCTAssertEqual(rejection("Claud", "Claude", texts: ["Claudを使う"], existing: existing), .partOfKnownWord)
    }

    func testRejectsAWrongWordThatOnlyAppearsInsideLongerWords() {
        XCTAssertEqual(rejection("グロース", "Groq", texts: ["グロースハックの本を読んだ"]), .notInTexts)
        XCTAssertNil(rejection("グロース", "Groq", texts: ["グロースハックの本とグロースの話"]))
        XCTAssertEqual(rejection("Glog", "Groq", texts: ["MyGlogとGlog2を使う"]), .notInTexts)
    }

    func testRejectsPairsThatDoNotSoundAlike() {
        // 実際の過去の発話で、AIが辞書の語に無理に当てはめた例
        XCTAssertEqual(rejection("セレブラス", "Cloudflare", texts: ["セレブラスのAPI設定"]), .notSoundAlike)
        XCTAssertEqual(rejection("フェイブル", "Firebase", texts: ["フェイブルがなくなった"]), .notSoundAlike)
        XCTAssertEqual(rejection("Glog", "GitHub", texts: ["Glogのキー"]), .notSoundAlike)
    }

    func testRejectsANewNameWhenAKnownNameSoundsJustAsClose() {
        // Glog は Groq とも Grok とも同じくらい近い。辞書に Groq があるのに Grok と決めつけない
        let existing = [ReplacementDictionary.Entry(wrong: "グロック", correct: "Groq")]

        XCTAssertEqual(rejection("Glog", "Grok", texts: ["Glogのキー"], existing: existing), .ambiguousWithKnownTerm)
        XCTAssertNil(rejection("Glog", "Groq", texts: ["Glogのキー"], existing: existing))
    }

    func testAcceptsANewNameWhenNoKnownNameIsClose() {
        let existing = [ReplacementDictionary.Entry(wrong: "グロック", correct: "Groq")]

        XCTAssertNil(rejection("ハギングフェイス", "HuggingFace", texts: ["ハギングフェイスに登録した"], existing: existing))
    }

    func testRejectsOrdinaryWords() {
        XCTAssertEqual(rejection("カーソル", "Cursor", commonWords: ["カーソル"]), .commonWord)
        XCTAssertNil(rejection("カーソル", "Cursor"))
    }
}

final class LearningTextScreenTests: XCTestCase {
    func testKeepsOrdinarySentences() {
        XCTAssertEqual(
            LearningTextScreen.prepare("  今日はオブシリアンにメモしました\n", maxCharacters: 400, minimumLength: 6),
            "今日はオブシリアンにメモしました"
        )
    }

    func testTurnsLineBreaksIntoSpacesSoTheNumberedListStaysIntact() {
        XCTAssertEqual(
            LearningTextScreen.prepare("一行目です。\n二行目です。\r\n三行目です。", maxCharacters: 400, minimumLength: 6),
            "一行目です。 二行目です。 三行目です。"
        )
    }

    func testSkipsTextsThatAreTooShort() {
        XCTAssertNil(LearningTextScreen.prepare("はい", maxCharacters: 400, minimumLength: 6))
    }

    func testSkipsTextsThatLookPrivate() {
        let privateTexts = [
            "連絡先は090-1234-5678です",
            "メールアドレスは abc@example.com です",
            "https://example.com/page を見てください",
            "キーは sk-abcdefghijklmnopqrstuvwxyz1234 です",
            "パスワードは忘れてしまいました",
            "マイナンバーカードを作りに行く",
            "暗証番号を変更したい",
            "電話は０９０−１２３４−５６７８です",
            "住所は東京都の○○町です",
            "電話番号を教えてください",
            "生年月日を入力するところです",
            "APIキーを貼り付けた",
            "my password is secret"
        ]

        for text in privateTexts {
            XCTAssertNil(LearningTextScreen.prepare(text, maxCharacters: 400, minimumLength: 6), text)
        }
    }

    func testCutsLongTexts() throws {
        let prepared = try XCTUnwrap(
            LearningTextScreen.prepare(String(repeating: "あ", count: 1000), maxCharacters: 400, minimumLength: 6)
        )

        XCTAssertEqual(prepared.count, 400)
    }
}

/// 内蔵辞書に実際に入っているかは Mac によって違うので、入っていない Mac ではスキップする。
/// （前提の確認には、確かめたい実装ではなく OS の辞書引きを直接使う）
final class SystemDictionaryWordCheckerTests: XCTestCase {
    private func systemDictionaryHasEntry(_ word: String) -> Bool {
        DCSCopyTextDefinition(nil, word as CFString, CFRangeMake(0, (word as NSString).length)) != nil
    }

    func testKnowsOrdinaryJapaneseWordsButNotMisrecognitions() throws {
        try XCTSkipUnless(systemDictionaryHasEntry("プロジェクト"), "この Mac には日本語の辞書が入っていない")
        let checker = SystemDictionaryWordChecker()

        XCTAssertTrue(checker.isCommonWord("カーソル"))
        XCTAssertFalse(checker.isCommonWord("オブシリアン"))
        XCTAssertFalse(checker.isCommonWord("ソニョックス"))
    }

    func testKnowsOrdinaryEnglishWordsButNotGarbledNames() throws {
        try XCTSkipUnless(systemDictionaryHasEntry("cloud"), "この Mac には英語の辞書が入っていない")
        let checker = SystemDictionaryWordChecker()

        XCTAssertTrue(checker.isCommonWord("Cloud"))
        XCTAssertTrue(checker.isCommonWord("cursor"))
        XCTAssertFalse(checker.isCommonWord("Glog"))
        XCTAssertFalse(checker.isCommonWord("Opencode"))
    }

    func testDoesNotMatchWordsByTheirBeginningOnly() throws {
        try XCTSkipUnless(systemDictionaryHasEntry("カーソル"), "この Mac には日本語の辞書が入っていない")
        let checker = SystemDictionaryWordChecker()

        XCTAssertFalse(checker.isCommonWord("カーソルバー"))
        XCTAssertFalse(checker.isCommonWord("カーソルを"))
    }
}
