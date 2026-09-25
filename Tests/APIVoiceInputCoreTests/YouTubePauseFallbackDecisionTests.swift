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

final class MediaRemotePauseHandlingDecisionTests: XCTestCase {
    // 2026-09-13: displayID=nil は「MediaRemoteが何も分からなかった」という意味であり、
    // 一時停止できた証拠ではない。これをhandled扱いにすると、実際に効いている
    // AppleScriptのタブ巡回が打ち切られて機能が丸ごと無効になる（09-02〜09-13の回帰）。
    func testDoesNotTreatSentPauseAsHandledWhenMediaRemoteCannotReportTheActiveApp() {
        XCTAssertFalse(MediaRemotePauseHandlingDecision.isHandledPause(
            sent: true,
            snapshotDisplayID: nil,
            snapshotIsPlaying: false,
            targetDisplayID: "com.google.Chrome"
        ))
    }

    func testDoesNotTreatSentPauseAsHandledWhenPlayingStateIsUnknown() {
        XCTAssertFalse(MediaRemotePauseHandlingDecision.isHandledPause(
            sent: true,
            snapshotDisplayID: nil,
            snapshotIsPlaying: nil,
            targetDisplayID: "com.google.Chrome"
        ))
    }

    func testTreatsTargetPlayingSnapshotAndSentCommandAsHandledPause() {
        XCTAssertTrue(MediaRemotePauseHandlingDecision.isHandledPause(
            sent: true,
            snapshotDisplayID: "com.google.Chrome",
            snapshotIsPlaying: true,
            targetDisplayID: "com.google.Chrome"
        ))
    }

    func testDoesNotTreatDifferentAppSnapshotAsHandledPause() {
        XCTAssertFalse(MediaRemotePauseHandlingDecision.isHandledPause(
            sent: true,
            snapshotDisplayID: "com.apple.Music",
            snapshotIsPlaying: true,
            targetDisplayID: "com.google.Chrome"
        ))
    }

    func testDoesNotTreatUnsentCommandAsHandledPause() {
        XCTAssertFalse(MediaRemotePauseHandlingDecision.isHandledPause(
            sent: false,
            snapshotDisplayID: "com.google.Chrome",
            snapshotIsPlaying: true,
            targetDisplayID: "com.google.Chrome"
        ))
    }
}


final class MediaRemotePauseSendDecisionTests: XCTestCase {
    // 対象ブラウザが再生元だと確認できたときだけ送る。
    // displayID=nil で盲撃ちすると、Music/Spotify など無関係なアプリを止めうる。
    func testSendsPauseOnlyWhenSnapshotPointsAtTheTargetBrowser() {
        XCTAssertTrue(MediaRemotePauseSendDecision.shouldSendPause(
            snapshotDisplayID: "com.google.Chrome",
            targetDisplayID: "com.google.Chrome"
        ))
    }

    func testDoesNotSendPauseWhenNowPlayingAppIsUnknown() {
        XCTAssertFalse(MediaRemotePauseSendDecision.shouldSendPause(
            snapshotDisplayID: nil,
            targetDisplayID: "com.google.Chrome"
        ))
    }

    func testDoesNotSendPauseWhenAnotherAppIsPlaying() {
        XCTAssertFalse(MediaRemotePauseSendDecision.shouldSendPause(
            snapshotDisplayID: "com.spotify.client",
            targetDisplayID: "com.google.Chrome"
        ))
    }
}
