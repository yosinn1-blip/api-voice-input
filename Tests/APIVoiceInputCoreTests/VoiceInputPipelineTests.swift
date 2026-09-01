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

    func testPipelineRemovesHallucinatedThanksAppendedToTranscript() async throws {
        let result = try await runPipeline(
            transcript: "このコメントを修正してください。ありがとうございました。",
            cleaned: "このコメントを修正してください。ありがとうございました。"
        )
        XCTAssertEqual(result.rawTranscript, "このコメントを修正してください。")
        XCTAssertEqual(result.finalText, "このコメントを修正してください。")
        XCTAssertEqual(result.cleanupReceived, "このコメントを修正してください。")
    }

    func testPipelineRemovesAppendedGoshichoArigatogozaimashitadesu() async throws {
        let result = try await runPipeline(
            transcript: "このコメントを修正してください。ご視聴ありがとうございましたです",
            cleaned: "このコメントを修正してください。"
        )
        XCTAssertEqual(result.rawTranscript, "このコメントを修正してください。")
        XCTAssertEqual(result.finalText, "このコメントを修正してください。")
    }

    func testPipelineStripsStackedAppendedClosings() async throws {
        let result = try await runPipeline(
            transcript: "このコメントを修正してください。ご視聴ありがとうございましたです。ありがとうございました。音声ソフト。",
            cleaned: "このコメントを修正してください。ごちしょう。ごちそうさま。"
        )
        XCTAssertEqual(result.rawTranscript, "このコメントを修正してください。")
        XCTAssertEqual(result.finalText, "このコメントを修正してください。")
        XCTAssertEqual(result.cleanupReceived, "このコメントを修正してください。")
    }

    func testPipelineKeepsStandaloneThanksTranscript() async throws {
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("voice-standalone-thanks.m4a")
        try Data("fake".utf8).write(to: audioURL)
        let transcription = MockTranscriptionProvider(result: "ありがとうございました。")
        let pipeline = VoiceInputPipeline(transcriptionProvider: transcription, cleanupProvider: NoCleanupProvider())

        let result = try await pipeline.run(audioFileURL: audioURL, profile: .defaultJapanese)

        XCTAssertEqual(result.rawTranscript, "ありがとうございました。")
        XCTAssertEqual(result.finalText, "ありがとうございました。")
    }

    func testSanitizeKeepsWholeUtteranceWhenItIsOnlyStackedClosings() {
        let stacked = "ご視聴ありがとうございましたですありがとうございました"
        XCTAssertEqual(TranscriptHallucinationFilter.sanitize(stacked), stacked)
        XCTAssertEqual(TranscriptHallucinationFilter.sanitize("ごちそうさまでした"), "ごちそうさまでした")
    }

    func testSanitizeStripsGochisouOnlyWithDelimiter() {
        XCTAssertEqual(
            TranscriptHallucinationFilter.sanitize("今日のご飯はごちそう"),
            "今日のご飯はごちそう"
        )
        XCTAssertEqual(
            TranscriptHallucinationFilter.sanitize("今日のご飯は。ごちそう"),
            "今日のご飯は。"
        )
        XCTAssertEqual(
            TranscriptHallucinationFilter.sanitize("作業完了。ごちしょう"),
            "作業完了。"
        )
    }

    func testPipelineRemovesHallucinatedAppNameAppendedToTranscript() async throws {
        let result = try await runPipeline(
            transcript: "このコメントを修正してください。音声ソフト。",
            cleaned: "このコメントを修正してください。API音声ソフト。"
        )
        XCTAssertEqual(result.rawTranscript, "このコメントを修正してください。")
        XCTAssertEqual(result.finalText, "このコメントを修正してください。")
        XCTAssertEqual(result.cleanupReceived, "このコメントを修正してください。")
    }

    func testPipelineKeepsStandaloneAppNameTranscript() async throws {
        let result = try await runPipeline(transcript: "音声ソフト。", cleaned: "API音声ソフト")
        XCTAssertEqual(result.rawTranscript, "音声ソフト。")
        XCTAssertEqual(result.finalText, "API音声ソフト")
    }

    func testPipelineRemovesHallucinatedViewingThanksPrefixedToTranscript() async throws {
        let result = try await runPipeline(
            transcript: "ご視聴ありがとうございました。このコメントを修正してください。",
            cleaned: "ご視聴ありがとうございました。このコメントを修正してください。"
        )
        XCTAssertEqual(result.rawTranscript, "このコメントを修正してください。")
        XCTAssertEqual(result.finalText, "このコメントを修正してください。")
        XCTAssertEqual(result.cleanupReceived, "このコメントを修正してください。")
    }

    func testPipelineRemovesHallucinatedViewingThanksAppendedToTranscript() async throws {
        let result = try await runPipeline(
            transcript: "このコメントを修正してください。ご視聴ありがとうございました。",
            cleaned: "このコメントを修正してください。ご視聴ありがとうございます。"
        )
        XCTAssertEqual(result.rawTranscript, "このコメントを修正してください。")
        XCTAssertEqual(result.finalText, "このコメントを修正してください。")
        XCTAssertEqual(result.cleanupReceived, "このコメントを修正してください。")
    }

    func testPipelineKeepsRealSentenceContainingGoshichoInTheMiddle() async throws {
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("voice-middle-goshicho.m4a")
        try Data("fake".utf8).write(to: audioURL)
        let transcription = MockTranscriptionProvider(result: "この動画をご視聴ください。")
        let pipeline = VoiceInputPipeline(transcriptionProvider: transcription, cleanupProvider: NoCleanupProvider())

        let result = try await pipeline.run(audioFileURL: audioURL, profile: .defaultJapanese)

        XCTAssertEqual(result.rawTranscript, "この動画をご視聴ください。")
        XCTAssertEqual(result.finalText, "この動画をご視聴ください。")
    }

    func testPipelineKeepsGoshichoWhenItStartsARealSentence() async throws {
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("voice-goshicho-noue.m4a")
        try Data("fake".utf8).write(to: audioURL)
        let transcription = MockTranscriptionProvider(result: "ご視聴のうえご検討ください")
        let pipeline = VoiceInputPipeline(transcriptionProvider: transcription, cleanupProvider: NoCleanupProvider())

        let result = try await pipeline.run(audioFileURL: audioURL, profile: .defaultJapanese)

        XCTAssertEqual(result.rawTranscript, "ご視聴のうえご検討ください")
        XCTAssertEqual(result.finalText, "ご視聴のうえご検討ください")
    }

    func testPipelineKeepsStandaloneViewingThanksTranscript() async throws {
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("voice-standalone-goshicho.m4a")
        try Data("fake".utf8).write(to: audioURL)
        let transcription = MockTranscriptionProvider(result: "ご視聴ありがとうございました。")
        let pipeline = VoiceInputPipeline(transcriptionProvider: transcription, cleanupProvider: NoCleanupProvider())

        let result = try await pipeline.run(audioFileURL: audioURL, profile: .defaultJapanese)

        XCTAssertEqual(result.rawTranscript, "ご視聴ありがとうございました。")
        XCTAssertEqual(result.finalText, "ご視聴ありがとうございました。")
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

    private struct PipelineRun {
        let rawTranscript: String
        let finalText: String
        let cleanupReceived: String?
    }

    private func runPipeline(transcript: String, cleaned: String) async throws -> PipelineRun {
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString).m4a")
        try Data("fake".utf8).write(to: audioURL)
        let transcription = MockTranscriptionProvider(result: transcript)
        let cleanup = MockCleanupProvider(result: cleaned)
        let pipeline = VoiceInputPipeline(transcriptionProvider: transcription, cleanupProvider: cleanup)
        let result = try await pipeline.run(audioFileURL: audioURL, profile: .defaultJapanese)
        return PipelineRun(
            rawTranscript: result.rawTranscript,
            finalText: result.finalText,
            cleanupReceived: cleanup.receivedTranscript
        )
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
    var receivedTranscript: String?
    var receivedPrompt: String?
    var callCount = 0

    init(result: String) {
        self.result = result
    }

    func clean(transcript: String, prompt: String) async throws -> String {
        callCount += 1
        receivedTranscript = transcript
        receivedPrompt = prompt
        return result
    }
}
