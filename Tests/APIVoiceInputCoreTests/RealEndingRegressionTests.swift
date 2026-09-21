import XCTest
@testable import APIVoiceInputCore

/// バグ①の再現テスト。実際に喋った語尾が幻聴として削られていないかを検証する。
final class RealEndingRegressionTests: XCTestCase {

    // 区切りなしで本当に言い切ったケース
    func testKeepsRealThanksWithoutDelimiter() {
        XCTAssertEqual(
            TranscriptHallucinationFilter.sanitize("今日は付き合ってくれてありがとうございました"),
            "今日は付き合ってくれてありがとうございました"
        )
    }

    func testKeepsRealPoliteThanksWithoutDelimiter() {
        XCTAssertEqual(
            TranscriptHallucinationFilter.sanitize("いつもありがとうございます"),
            "いつもありがとうございます"
        )
    }

    func testKeepsRealGochisousamaWithoutDelimiter() {
        XCTAssertEqual(
            TranscriptHallucinationFilter.sanitize("とても美味しかったごちそうさまでした"),
            "とても美味しかったごちそうさまでした"
        )
    }

    func testKeepsRealAppNameWithoutDelimiter() {
        XCTAssertEqual(
            TranscriptHallucinationFilter.sanitize("今使っているのはAPI音声ソフト"),
            "今使っているのはAPI音声ソフト"
        )
    }

    // 幻聴は従来どおり落ちること（退行防止）
    func testStillStripsViewingThanksAppendedToRealSpeech() {
        XCTAssertEqual(
            TranscriptHallucinationFilter.sanitize("このコメントを修正してください。ご視聴ありがとうございました"),
            "このコメントを修正してください。"
        )
    }
}
