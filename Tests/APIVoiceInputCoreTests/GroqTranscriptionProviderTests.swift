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

    func testTranscriptionPromptBiasesConversationalJapaneseAndOmitsOutroSeeds() {
        let prompt = GroqTranscriptionProvider.transcriptionPrompt
        XCTAssertTrue(prompt.contains("日本語"))
        XCTAssertTrue(prompt.contains("書き起こし"))
        XCTAssertTrue(prompt.contains("定型文は付けない"))
        XCTAssertFalse(prompt.contains("ご視聴ありがとうございました"))
        XCTAssertFalse(prompt.contains("ご視聴ありがとうございましたです"))
        XCTAssertFalse(prompt.contains("音声ソフト"))
        XCTAssertFalse(prompt.contains("API音声ソフト"))
        for noun in ["Codex", "Claude", "ChatGPT", "Gemini", "YouTube", "GitHub", "Swift", "Xcode", "API"] {
            XCTAssertTrue(prompt.contains(noun), "missing proper-noun hint: \(noun)")
        }
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
        XCTAssertTrue(bodyText.contains(GroqTranscriptionProvider.transcriptionPrompt))
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
