import XCTest
@testable import APIVoiceInputCore

final class VoiceInputPipelineTests: XCTestCase {
    func testPipelineTranscribesCleansAndReturnsFinalText() async throws {
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("voice.m4a")
        try Data("fake".utf8).write(to: audioURL)
        let transcription = MockTranscriptionProvider(result: "えー今日はテストです")
        let cleanup = MockCleanupProvider(result: "今日はテストです。")
        let pipeline = VoiceInputPipeline(transcriptionProvider: transcription, cleanupProvider: cleanup)

        let result = try await pipeline.run(audioFileURL: audioURL, profile: .defaultJapanese)

        XCTAssertEqual(result.rawTranscript, "えー今日はテストです")
        XCTAssertEqual(result.finalText, "今日はテストです。")
        XCTAssertEqual(transcription.receivedLanguageHint, "ja")
        XCTAssertEqual(cleanup.receivedPrompt, VoiceProfile.defaultJapanese.cleanupPrompt)
    }

    func testPipelineUsesRawTranscriptWhenCleanupProviderIsNone() async throws {
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("voice-none.m4a")
        try Data("fake".utf8).write(to: audioURL)
        let transcription = MockTranscriptionProvider(result: "そのまま貼ります")
        let pipeline = VoiceInputPipeline(transcriptionProvider: transcription, cleanupProvider: NoCleanupProvider())

        let result = try await pipeline.run(audioFileURL: audioURL, profile: .defaultJapanese)

        XCTAssertEqual(result.rawTranscript, "そのまま貼ります")
        XCTAssertEqual(result.finalText, "そのまま貼ります")
    }

    func testEmptyTranscriptFailsBeforeCleanup() async throws {
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("voice-empty.m4a")
        try Data("fake".utf8).write(to: audioURL)
        let transcription = MockTranscriptionProvider(result: "   ")
        let cleanup = MockCleanupProvider(result: "unused")
        let pipeline = VoiceInputPipeline(transcriptionProvider: transcription, cleanupProvider: cleanup)

        do {
            _ = try await pipeline.run(audioFileURL: audioURL, profile: .defaultJapanese)
            XCTFail("Expected emptyTranscript")
        } catch VoiceInputError.emptyTranscript {
            XCTAssertEqual(cleanup.callCount, 0)
        }
    }
}

private final class MockTranscriptionProvider: TranscriptionProvider, @unchecked Sendable {
    let id = "mock-stt"
    let result: String
    var receivedLanguageHint: String?

    init(result: String) {
        self.result = result
    }

    func transcribe(audioFileURL: URL, languageHint: String) async throws -> String {
        receivedLanguageHint = languageHint
        return result
    }
}

private final class MockCleanupProvider: CleanupProvider, @unchecked Sendable {
    let id = "mock-cleanup"
    let result: String
    var receivedPrompt: String?
    var callCount = 0

    init(result: String) {
        self.result = result
    }

    func clean(transcript: String, prompt: String) async throws -> String {
        callCount += 1
        receivedPrompt = prompt
        return result
    }
}
