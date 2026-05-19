import XCTest
@testable import APIVoiceInputCore

final class YouTubePauseFallbackDecisionTests: XCTestCase {
    func testUsesMediaKeyWhenYouTubeTabsExistButJavaScriptPauseFails() {
        XCTAssertTrue(YouTubePauseFallbackDecision.shouldUseMediaKeyFallback(scriptOutput: "tabs=6 pausedVideos=0 errors=6"))
    }

    func testDoesNotUseMediaKeyWhenNoYouTubeTabsWereFound() {
        XCTAssertFalse(YouTubePauseFallbackDecision.shouldUseMediaKeyFallback(scriptOutput: "tabs=0 pausedVideos=0 errors=0"))
    }

    func testDoesNotUseMediaKeyWhenJavaScriptPausedVideo() {
        XCTAssertFalse(YouTubePauseFallbackDecision.shouldUseMediaKeyFallback(scriptOutput: "tabs=2 pausedVideos=1 errors=1"))
    }
}
