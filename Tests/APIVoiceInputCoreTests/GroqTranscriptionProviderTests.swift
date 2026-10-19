import XCTest
@testable import APIVoiceInputCore

final class GroqTranscriptionProviderTests: XCTestCase {
    func testProviderIDMatchesConfiguredDefaultProfile() {
        let provider = GroqTranscriptionProvider(apiKey: "groq-key")
        XCTAssertEqual(provider.id, "groq-whisper-large-v3")
        XCTAssertEqual(provider.id, VoiceProfile.defaultJapanese.transcriptionProviderID)
        XCTAssertEqual(GroqTranscriptionProvider.modelName, "whisper-large-v3")
        XCTAssertNotEqual(GroqTranscriptionProvider.modelName, "whisper-large-v3-turbo")
    }

    func testResolvedLanguagePinsJapaneseWhenHintIsBlank() {
        XCTAssertEqual(GroqTranscriptionProvider.resolvedLanguage(from: "ja"), "ja")
        XCTAssertEqual(GroqTranscriptionProvider.resolvedLanguage(from: ""), "ja")
        XCTAssertEqual(GroqTranscriptionProvider.resolvedLanguage(from: "  "), "ja")
        XCTAssertEqual(GroqTranscriptionProvider.resolvedLanguage(from: "en"), "en")
    }

    func testGroqProviderParsesTextResponse() async throws {
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("groq-test.wav")
        try Data("audio".utf8).write(to: audioURL)
        let client = MockHTTPClient(response: HTTPResponse(statusCode: 200, data: Data(#"{"text":"こんにちは。"}"#.utf8)))
        let provider = GroqTranscriptionProvider(apiKey: "test-key", httpClient: client)

        let text = try await provider.transcribe(audioFileURL: audioURL, languageHint: "ja")

        XCTAssertEqual(text, "こんにちは。")
        XCTAssertEqual(client.requests.count, 1)
        XCTAssertEqual(client.requests[0].url.absoluteString, "https://api.groq.com/openai/v1/audio/transcriptions")
        XCTAssertEqual(client.requests[0].headers["Authorization"], "Bearer test-key")
        let bodyText = String(data: client.requests[0].body, encoding: .utf8) ?? ""
        XCTAssertTrue(bodyText.contains("whisper-large-v3"))
        XCTAssertFalse(bodyText.contains("whisper-large-v3-turbo"))
        XCTAssertTrue(bodyText.contains("name=\"language\""))
        XCTAssertTrue(bodyText.contains("ja"))
        XCTAssertTrue(bodyText.contains("name=\"temperature\""))
        XCTAssertTrue(bodyText.contains(GroqTranscriptionProvider.temperature))
        XCTAssertFalse(bodyText.contains("name=\"prompt\""))
        XCTAssertFalse(bodyText.contains("音声ソフト"))
    }

    func testGroqProviderFallsBackToJapaneseWhenLanguageHintIsEmpty() async throws {
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("groq-empty-lang.wav")
        try Data("audio".utf8).write(to: audioURL)
        let client = MockHTTPClient(response: HTTPResponse(statusCode: 200, data: Data(#"{"text":"テスト"}"#.utf8)))
        let provider = GroqTranscriptionProvider(apiKey: "test-key", httpClient: client)

        _ = try await provider.transcribe(audioFileURL: audioURL, languageHint: "")

        let bodyText = String(data: client.requests[0].body, encoding: .utf8) ?? ""
        XCTAssertTrue(bodyText.contains("name=\"language\"\r\n\r\nja\r\n"))
    }

    /// 2026-09-27 実測: 固有名詞ヒントを prompt に付けると、30秒を超える録音で後半が
    /// 「ご視聴ありがとうございました」に置き換わり語尾ごと消えた（66秒録音で49〜66秒が消失、
    /// 付けなければ全区間とも最後まで認識）。日本語・英語とも prompt は送らない。
    func testGroqProviderSendsNoPrompt() async throws {
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("groq-prompt-lang.wav")
        try Data("audio".utf8).write(to: audioURL)

        for hint in ["ja", "en"] {
            let client = MockHTTPClient(response: HTTPResponse(statusCode: 200, data: Data(#"{"text":"テスト"}"#.utf8)))
            _ = try await GroqTranscriptionProvider(apiKey: "test-key", httpClient: client)
                .transcribe(audioFileURL: audioURL, languageHint: hint)
            let body = String(data: client.requests[0].body, encoding: .utf8) ?? ""
            XCTAssertTrue(body.contains("name=\"language\"\r\n\r\n\(hint)\r\n"))
            XCTAssertFalse(body.contains("name=\"prompt\""), "prompt sent for \(hint)")
        }
    }

    func testGroqProviderMaps429ToRateLimit() async throws {
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("groq-429.wav")
        try Data("audio".utf8).write(to: audioURL)
        let client = MockHTTPClient(response: HTTPResponse(statusCode: 429, data: Data()))
        let provider = GroqTranscriptionProvider(apiKey: "test-key", httpClient: client)

        do {
            _ = try await provider.transcribe(audioFileURL: audioURL, languageHint: "ja")
            XCTFail("Expected rate limit")
        } catch VoiceInputError.providerRateLimited(let providerID) {
            XCTAssertEqual(providerID, "groq")
        }
    }
}
