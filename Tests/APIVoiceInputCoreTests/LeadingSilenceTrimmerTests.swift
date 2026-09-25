import AVFoundation
import XCTest
@testable import APIVoiceInputCore

final class LeadingSilenceTrimmerTests: XCTestCase {
    private let window = 0.02

    private func windows(silence: Double, speech: Double, noise: Double = -60, voice: Double = -20) -> [Double] {
        Array(repeating: noise, count: Int(silence / window)) + Array(repeating: voice, count: Int(speech / window))
    }

    func testLongLeadingSilenceIsTrimmedWithPadding() {
        let trim = LeadingSilenceTrimmer.leadingTrimSeconds(windowRMSDBFS: windows(silence: 10, speech: 5))
        XCTAssertEqual(trim, 10 - LeadingSilenceTrimmer.paddingSeconds, accuracy: 0.03)
    }

    func testShortLeadingSilenceIsKept() {
        XCTAssertEqual(LeadingSilenceTrimmer.leadingTrimSeconds(windowRMSDBFS: windows(silence: 1.0, speech: 5)), 0)
    }

    func testSpeechFromTheStartIsKept() {
        XCTAssertEqual(LeadingSilenceTrimmer.leadingTrimSeconds(windowRMSDBFS: windows(silence: 0, speech: 5)), 0)
    }

    func testAllSilenceIsNotTrimmed() {
        XCTAssertEqual(LeadingSilenceTrimmer.leadingTrimSeconds(windowRMSDBFS: windows(silence: 10, speech: 0)), 0)
    }

    func testSingleClickDoesNotCountAsSpeechStart() {
        var levels = windows(silence: 10, speech: 5)
        levels[Int(3.0 / window)] = -10
        let trim = LeadingSilenceTrimmer.leadingTrimSeconds(windowRMSDBFS: levels)
        XCTAssertEqual(trim, 10 - LeadingSilenceTrimmer.paddingSeconds, accuracy: 0.03)
    }

    func testNoisyRoomStillFindsSpeech() {
        let trim = LeadingSilenceTrimmer.leadingTrimSeconds(windowRMSDBFS: windows(silence: 8, speech: 4, noise: -42, voice: -22))
        XCTAssertEqual(trim, 8 - LeadingSilenceTrimmer.paddingSeconds, accuracy: 0.03)
    }

    func testTrimIfNeededWritesShorterFile() throws {
        let sampleRate = 16_000.0
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("trim-test-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            let total = Int(sampleRate * 7)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total))!
            buffer.frameLength = AVAudioFrameCount(total)
            let samples = buffer.floatChannelData![0]
            for index in 0..<total {
                let t = Double(index) / sampleRate
                samples[index] = t < 5 ? 0.0005 : Float(0.3 * sin(2 * Double.pi * 220 * t))
            }
            try file.write(from: buffer)
        }

        let result = try LeadingSilenceTrimmer().trimIfNeeded(audioFileURL: url)
        defer { if result.url != url { try? FileManager.default.removeItem(at: result.url) } }

        XCTAssertEqual(result.trimmedSeconds, 5 - LeadingSilenceTrimmer.paddingSeconds, accuracy: 0.05)
        let trimmedFile = try AVAudioFile(forReading: result.url)
        XCTAssertEqual(Double(trimmedFile.length) / sampleRate, 2 + LeadingSilenceTrimmer.paddingSeconds, accuracy: 0.05)
    }
}
