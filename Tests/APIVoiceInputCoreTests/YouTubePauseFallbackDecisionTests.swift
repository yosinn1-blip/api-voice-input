import XCTest
@testable import APIVoiceInputCore

final class YouTubePauseFallbackDecisionTests: XCTestCase {
    func testTriesMediaRemotePauseWhenYouTubeTabsExistButJavaScriptPauseFails() {
        XCTAssertEqual(YouTubePauseFallbackDecision.fallbackAction(scriptOutput: "tabs=6 pausedVideos=0 errors=6"), .tryMediaRemotePause)
    }

    func testDoesNothingWhenNoYouTubeTabsWereFound() {
        XCTAssertEqual(YouTubePauseFallbackDecision.fallbackAction(scriptOutput: "tabs=0 pausedVideos=0 errors=0"), .none)
    }

    func testDoesNothingWhenJavaScriptPausedVideo() {
        XCTAssertEqual(YouTubePauseFallbackDecision.fallbackAction(scriptOutput: "tabs=2 pausedVideos=1 errors=1"), .none)
    }
}
