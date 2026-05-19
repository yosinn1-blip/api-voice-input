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


final class MediaRemotePauseSuccessDecisionTests: XCTestCase {
    func testDoesNotTreatNilMediaRemoteSnapshotAsConfirmedPause() {
        XCTAssertFalse(MediaRemotePauseSuccessDecision.isConfirmedPause(
            sent: true,
            snapshotDisplayID: nil,
            snapshotIsPlaying: false,
            targetDisplayID: "com.google.Chrome"
        ))
    }

    func testTreatsTargetPlayingSnapshotAndSentCommandAsConfirmedPause() {
        XCTAssertTrue(MediaRemotePauseSuccessDecision.isConfirmedPause(
            sent: true,
            snapshotDisplayID: "com.google.Chrome",
            snapshotIsPlaying: true,
            targetDisplayID: "com.google.Chrome"
        ))
    }

    func testDoesNotTreatDifferentAppSnapshotAsConfirmedPause() {
        XCTAssertFalse(MediaRemotePauseSuccessDecision.isConfirmedPause(
            sent: true,
            snapshotDisplayID: "com.apple.Music",
            snapshotIsPlaying: true,
            targetDisplayID: "com.google.Chrome"
        ))
    }
}
