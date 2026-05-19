import XCTest
@testable import APIVoiceInputCore

final class RecordingStopPresentationTests: XCTestCase {
    func testHidesOverlayImmediatelyForSilentStop() {
        XCTAssertTrue(RecordingStopPresentation.shouldHideOverlayImmediately(maxRecordingLevel: 0.0))
        XCTAssertTrue(RecordingStopPresentation.shouldHideOverlayImmediately(maxRecordingLevel: 0.09))
        XCTAssertTrue(RecordingStopPresentation.shouldHideOverlayImmediately(maxRecordingLevel: 0.18))
    }

    func testKeepsOverlayVisibleForSpeechLikeEnterStop() {
        XCTAssertFalse(RecordingStopPresentation.shouldHideOverlayImmediately(maxRecordingLevel: 0.3, stopSource: "enter-stop"))
    }

    func testFnStopHidesImmediatelyButKeepsTranscriptionAsPasteOnly() {
        XCTAssertTrue(RecordingStopPresentation.shouldHideOverlayImmediately(maxRecordingLevel: 0.8, stopSource: "f19-hotkey"))
        XCTAssertTrue(RecordingStopPresentation.shouldHideOverlayImmediately(maxRecordingLevel: 0.8, stopSource: "direct-fn-eventtap"))
        XCTAssertFalse(RecordingStopPresentation.shouldCancelTranscription(stopSource: "f19-hotkey"))
        XCTAssertFalse(RecordingStopPresentation.shouldCancelTranscription(stopSource: "direct-fn-eventtap"))
        XCTAssertEqual(RecordingStopPresentation.pasteMode(stopSource: "f19-hotkey"), .pasteOnly)
        XCTAssertEqual(RecordingStopPresentation.pasteMode(stopSource: "direct-fn-eventtap"), .pasteOnly)
    }

    func testEnterStopTranscribesAndSends() {
        XCTAssertFalse(RecordingStopPresentation.shouldCancelTranscription(stopSource: "enter-stop"))
        XCTAssertEqual(RecordingStopPresentation.pasteMode(stopSource: "enter-stop"), .pasteThenEnter)
    }
    func testFnStopSkipsShortQuietStartupNoiseBeforeAPITranscription() {
        let startupNoise = AudioActivitySummary(durationSeconds: 0.57, rmsDBFS: -45.1, peakDBFS: -25.5)

        XCTAssertTrue(RecordingStopPresentation.shouldSkipTranscription(activity: startupNoise, stopSource: "f19-hotkey"))
        XCTAssertFalse(RecordingStopPresentation.shouldSkipTranscription(activity: startupNoise, stopSource: "enter-stop"))
    }

    func testFnStopKeepsLongerOrClearSpeechForPasteOnlyTranscription() {
        let longerQuietSpeech = AudioActivitySummary(durationSeconds: 2.0, rmsDBFS: -45.1, peakDBFS: -25.5)
        let clearSpeech = AudioActivitySummary(durationSeconds: 0.8, rmsDBFS: -36.0, peakDBFS: -18.0)

        XCTAssertFalse(RecordingStopPresentation.shouldSkipTranscription(activity: longerQuietSpeech, stopSource: "f19-hotkey"))
        XCTAssertFalse(RecordingStopPresentation.shouldSkipTranscription(activity: clearSpeech, stopSource: "f19-hotkey"))
    }
}
