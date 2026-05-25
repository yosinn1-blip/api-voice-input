import XCTest
@testable import APIVoiceInputCore

final class GroqTranscriptionProviderTests: XCTestCase {
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
        XCTAssertTrue(client.requests[0].body.contains(Data("whisper-large-v3".utf8)))
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
