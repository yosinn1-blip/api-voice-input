import AVFoundation
import XCTest
@testable import APIVoiceInputCore

final class EmptyUtteranceGuardTests: XCTestCase {
    func testSilenceIsSkippedBeforeTranscription() {
        let guarder = EmptyUtteranceGuard()
        let activity = AudioActivitySummary(durationSeconds: 3.0, rmsDBFS: -120, peakDBFS: -90)

        XCTAssertTrue(guarder.shouldSkipTranscription(activity: activity))
    }

    func testShortTapIsSkippedBeforeTranscription() {
        let guarder = EmptyUtteranceGuard()
        let activity = AudioActivitySummary(durationSeconds: 0.1, rmsDBFS: -20, peakDBFS: -10)

        XCTAssertTrue(guarder.shouldSkipTranscription(activity: activity))
    }

    func testSpeechLikeAudioIsNotSkipped() {
        let guarder = EmptyUtteranceGuard()
        let activity = AudioActivitySummary(durationSeconds: 2.0, rmsDBFS: -24, peakDBFS: -8)

        XCTAssertFalse(guarder.shouldSkipTranscription(activity: activity))
    }

    func testCommonSilenceHallucinationIsSuppressedWhenAudioWasQuiet() {
        let guarder = EmptyUtteranceGuard()
        let activity = AudioActivitySummary(durationSeconds: 3.0, rmsDBFS: -48, peakDBFS: -32)

        XCTAssertTrue(guarder.shouldSuppressTranscript("ありがとうございました。", activity: activity))
    }

    func testCommonPhraseIsNotSuppressedWhenAudioWasActive() {
        let guarder = EmptyUtteranceGuard()
        let activity = AudioActivitySummary(durationSeconds: 3.0, rmsDBFS: -20, peakDBFS: -6)

        XCTAssertFalse(guarder.shouldSuppressTranscript("ありがとうございました。", activity: activity))
    }


    func testGoshichoDesuAndGochisouVariantsAreSuppressedWhenQuiet() {
        let guarder = EmptyUtteranceGuard()
        let quiet = AudioActivitySummary(durationSeconds: 3.0, rmsDBFS: -48, peakDBFS: -32)
        let active = AudioActivitySummary(durationSeconds: 3.0, rmsDBFS: -20, peakDBFS: -6)

        XCTAssertTrue(guarder.shouldSuppressTranscript("ご視聴ありがとうございましたです", activity: quiet))
        XCTAssertTrue(guarder.shouldSuppressTranscript("ごちそうさまでした。", activity: quiet))
        XCTAssertTrue(guarder.shouldSuppressTranscript("ごちそうさま", activity: quiet))
        XCTAssertTrue(guarder.shouldSuppressTranscript("ごちしょう", activity: quiet))
        XCTAssertTrue(guarder.shouldSuppressTranscript("ごちそう", activity: quiet))
        XCTAssertFalse(guarder.shouldSuppressTranscript("ご視聴ありがとうございましたです", activity: active))
    }

    func testConcatenatedClosingsAreSuppressedWhenQuiet() {
        let guarder = EmptyUtteranceGuard()
        let quiet = AudioActivitySummary(durationSeconds: 3.0, rmsDBFS: -48, peakDBFS: -32)

        XCTAssertTrue(guarder.shouldSuppressTranscript("ごちしょうありがとうございました", activity: quiet))
        XCTAssertTrue(guarder.shouldSuppressTranscript("ご視聴ありがとうございましたですありがとうございました", activity: quiet))
        XCTAssertFalse(guarder.shouldSuppressTranscript("このコメントを修正してください。ご視聴ありがとうございましたです", activity: quiet))
    }

    func testAudioActivityAnalyzerSeparatesSilenceFromTone() throws {
        let analyzer = AudioActivityAnalyzer()
        let silenceURL = try writeCAF(name: "silence", amplitude: 0)
        let toneURL = try writeCAF(name: "tone", amplitude: 0.2)

        let silence = try analyzer.analyze(audioFileURL: silenceURL)
        let tone = try analyzer.analyze(audioFileURL: toneURL)

        XCTAssertLessThan(silence.rmsDBFS, -100)
        XCTAssertGreaterThan(tone.rmsDBFS, -20)
        XCTAssertGreaterThan(tone.peakDBFS, -15)
    }

    private func writeCAF(name: String, amplitude: Float) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("APIVoiceInput-\(name)-\(UUID().uuidString)")
            .appendingPathExtension("caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frameCount = AVAudioFrameCount(16_000)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let samples = buffer.floatChannelData![0]
        for index in 0..<Int(frameCount) {
            let phase = Float(index) / 16_000.0 * 440.0 * 2.0 * Float.pi
            samples[index] = amplitude == 0 ? 0 : sin(phase) * amplitude
        }
        try file.write(from: buffer)
        return url
    }
}
