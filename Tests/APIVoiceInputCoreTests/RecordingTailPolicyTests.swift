import XCTest
@testable import APIVoiceInputCore

final class RecordingTailPolicyTests: XCTestCase {
    func testSilentTailStopsAfterMinimumGrace() {
        var policy = RecordingTailPolicy()
        XCTAssertFalse(policy.shouldStop(elapsed: 0.30, level: 0))
        XCTAssertTrue(policy.shouldStop(elapsed: 0.36, level: 0))
    }

    func testSpeechPastOldDeadlineIsPreserved() {
        var policy = RecordingTailPolicy()
        XCTAssertFalse(policy.shouldStop(elapsed: 0.30, level: 0.6))
        XCTAssertFalse(policy.shouldStop(elapsed: 0.40, level: 0.6))
        XCTAssertFalse(policy.shouldStop(elapsed: 0.70, level: 0.5))
        XCTAssertFalse(policy.shouldStop(elapsed: 0.90, level: 0))
        XCTAssertTrue(policy.shouldStop(elapsed: 1.06, level: 0))
    }

    func testSpeechResumingAfterShortPauseResetsQuietPeriod() {
        var policy = RecordingTailPolicy()
        XCTAssertFalse(policy.shouldStop(elapsed: 0.20, level: 0.5))
        XCTAssertFalse(policy.shouldStop(elapsed: 0.45, level: 0))
        XCTAssertFalse(policy.shouldStop(elapsed: 0.50, level: 0.5))
        XCTAssertFalse(policy.shouldStop(elapsed: 0.70, level: 0))
        XCTAssertTrue(policy.shouldStop(elapsed: 0.86, level: 0))
    }

    func testContinuousNoiseCannotKeepRecordingIndefinitely() {
        var policy = RecordingTailPolicy()
        XCTAssertFalse(policy.shouldStop(elapsed: 1.45, level: 0.9))
        XCTAssertTrue(policy.shouldStop(elapsed: 1.50, level: 0.9))
    }

    func testQuietFinalSyllableStillExtendsTail() {
        var policy = RecordingTailPolicy()
        XCTAssertFalse(policy.shouldStop(elapsed: 0.40, level: 0.26))
        XCTAssertTrue(policy.shouldStop(elapsed: 0.76, level: 0.1))
    }

    func testNewRecordingDoesNotInheritPreviousSpeech() {
        var first = RecordingTailPolicy()
        XCTAssertFalse(first.shouldStop(elapsed: 1.2, level: 0.8))
        var next = RecordingTailPolicy()
        XCTAssertTrue(next.shouldStop(elapsed: 0.36, level: 0))
    }
}
