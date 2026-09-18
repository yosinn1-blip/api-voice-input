import XCTest
@testable import APIVoiceInputCore

/// 2026-09-13 の回帰対策。
///
/// このMacではChromeに120タブ・うちYouTube 47タブが常時開いている。
/// 全タブに `execute javascript` を撃つとChromeが破棄済みタブを1つずつ復帰させるため、
/// 実測でタブ1枚あたり数十秒かかり、巡回全体が数十分に膨らむ（debug.logの中央値:
/// 2026-05=1秒 → 06=4秒 → 07=6秒 → 09=842秒）。
/// 各ウィンドウのアクティブタブだけに限定すれば実測1秒で、実際に再生中の動画を捉えられる。
final class YouTubePauseScriptTests: XCTestCase {
    func testChromiumScriptOnlyTouchesTheActiveTabOfEachWindow() {
        let script = YouTubePauseScript.chromium(bundleIdentifier: "com.google.Chrome")
        XCTAssertTrue(script.contains("active tab of w"))
        XCTAssertFalse(script.contains("tabs of w"), "全タブ巡回は破棄済みタブを起こすため禁止")
    }

    func testSafariScriptOnlyTouchesTheCurrentTabOfEachWindow() {
        let script = YouTubePauseScript.safari(bundleIdentifier: "com.apple.Safari")
        XCTAssertTrue(script.contains("current tab of w"))
        XCTAssertFalse(script.contains("tabs of w"), "全タブ巡回は破棄済みタブを起こすため禁止")
    }

    func testScriptsCarryAWallClockDeadlineSoAScanCannotRunUnbounded() {
        for script in [
            YouTubePauseScript.chromium(bundleIdentifier: "com.google.Chrome"),
            YouTubePauseScript.safari(bundleIdentifier: "com.apple.Safari")
        ] {
            XCTAssertTrue(script.contains("deadlineSeconds"))
            XCTAssertTrue(script.contains("timedOut="))
        }
    }

    func testScriptsTargetTheRequestedBrowserBundle() {
        XCTAssertTrue(YouTubePauseScript.chromium(bundleIdentifier: "com.brave.Browser").contains("com.brave.Browser"))
        XCTAssertTrue(YouTubePauseScript.safari(bundleIdentifier: "com.apple.Safari").contains("com.apple.Safari"))
    }

    func testScriptsOnlyPauseVideosThatAreActuallyPlaying() {
        for script in [
            YouTubePauseScript.chromium(bundleIdentifier: "com.google.Chrome"),
            YouTubePauseScript.safari(bundleIdentifier: "com.apple.Safari")
        ] {
            XCTAssertTrue(script.contains("!video.paused"))
        }
    }
}


final class YouTubePauseTimedOutScanTests: XCTestCase {
    /// 締切で打ち切っただけの巡回を「JS失敗」と誤認してミュートへ落とさない。
    /// ミュートは過去に「戻らない」事故を起こした経路なので、根拠なく踏まない。
    func testTimedOutScanWithoutErrorsDoesNotEscalate() {
        XCTAssertEqual(
            YouTubePauseFallbackDecision.fallbackAction(scriptOutput: "tabs=1 pausedVideos=0 errors=0 timedOut=1"),
            .none
        )
    }

    func testScanThatPausedAVideoDoesNotEscalate() {
        XCTAssertEqual(
            YouTubePauseFallbackDecision.fallbackAction(scriptOutput: "tabs=1 pausedVideos=1 errors=0 timedOut=0"),
            .none
        )
    }
}
