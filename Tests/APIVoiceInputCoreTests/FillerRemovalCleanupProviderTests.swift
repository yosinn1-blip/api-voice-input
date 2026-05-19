import XCTest
@testable import APIVoiceInputCore

final class FillerRemovalCleanupProviderTests: XCTestCase {
    func testRemovesCommonLeadingJapaneseFillers() async throws {
        let provider = FillerRemovalCleanupProvider()

        let cleaned = try await provider.clean(transcript: "えーっと、あの今日はテストです", prompt: "")

        XCTAssertEqual(cleaned, "今日はテストです")
    }

    func testRemovesFillersAfterJapanesePunctuation() async throws {
        let provider = FillerRemovalCleanupProvider()

        let cleaned = try await provider.clean(transcript: "今日はテストです。えー次も試します", prompt: "")

        XCTAssertEqual(cleaned, "今日はテストです。次も試します")
    }

    func testRemovesCasualLeadingFillers() async throws {
        let provider = FillerRemovalCleanupProvider()

        let cleaned = try await provider.clean(transcript: "なんか今日はテストです", prompt: "")

        XCTAssertEqual(cleaned, "今日はテストです")
    }

    func testDoesNotRemoveMeaningfulWordsInsideSentence() async throws {
        let provider = FillerRemovalCleanupProvider()

        let cleaned = try await provider.clean(transcript: "これはまあまあ良い結果です", prompt: "")

        XCTAssertEqual(cleaned, "これはまあまあ良い結果です")
    }

    func testDoesNotRemoveLeadingMaamaa() async throws {
        let provider = FillerRemovalCleanupProvider()

        let cleaned = try await provider.clean(transcript: "まあまあ良い結果です", prompt: "")

        XCTAssertEqual(cleaned, "まあまあ良い結果です")
    }
}
