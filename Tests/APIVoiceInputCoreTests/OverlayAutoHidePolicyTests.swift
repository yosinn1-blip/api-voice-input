import XCTest
@testable import APIVoiceInputCore

final class OverlayAutoHidePolicyTests: XCTestCase {
    /// 録音中・会話待機中は「ユーザーが止めるまで」出ているのが正しい。
    func testUserDrivenStatesStayVisible() {
        XCTAssertNil(OverlayAutoHidePolicy.autoHideSeconds(for: .recording))
        XCTAssertNil(OverlayAutoHidePolicy.autoHideSeconds(for: .conversationWaiting))
    }

    /// 2026-09-18 の回帰テスト本体。
    /// 失敗表示は `hide()` を呼ばない経路から出るため、自前で消えなければ
    /// アプリを再起動するまで画面に残る（オーバーレイはクリックも受け付けない）。
    func testTerminalStatesDisappearWithoutAnyoneCallingHide() {
        XCTAssertEqual(OverlayAutoHidePolicy.autoHideSeconds(for: .failed), OverlayAutoHidePolicy.terminalStateSeconds)
        XCTAssertEqual(OverlayAutoHidePolicy.autoHideSeconds(for: .canceled), OverlayAutoHidePolicy.terminalStateSeconds)
        XCTAssertEqual(OverlayAutoHidePolicy.autoHideSeconds(for: .pasted), OverlayAutoHidePolicy.completedStateSeconds)
    }

    /// 文字起こし中に処理が戻ってこなかった場合の保険。
    /// Groq のリクエストタイムアウトより長くないと、正常な待ち時間を途中で隠してしまう。
    func testProcessingStatesHaveWatchdogLongerThanNetworkTimeout() {
        for state in [OverlayPresentationState.transcribing, .cleaning, .pasting] {
            let seconds = OverlayAutoHidePolicy.autoHideSeconds(for: state)
            XCTAssertEqual(seconds, OverlayAutoHidePolicy.processingWatchdogSeconds, "\(state) の保険が外れている")
            XCTAssertGreaterThan(seconds ?? 0, 60, "\(state) が通信タイムアウトより先に消えると処理中の表示が失われる")
        }
    }

    /// 状態を追加したときに期限を書き忘れないための総当たり検査。
    /// ユーザー操作で終わる2状態以外は、すべて自分で消える期限を持たなければならない。
    func testEveryStateEitherIsUserDrivenOrExpiresOnItsOwn() {
        let userDriven: Set<OverlayPresentationState> = [.recording, .conversationWaiting]
        for state in OverlayPresentationState.allCases where userDriven.contains(state) == false {
            XCTAssertNotNil(
                OverlayAutoHidePolicy.autoHideSeconds(for: state),
                "\(state.rawValue) に自動消滅の期限がない。再起動でしか消せない表示になる"
            )
        }
    }

    func testTerminalStateIsLongEnoughToReadButNotAnnoying() {
        XCTAssertGreaterThanOrEqual(OverlayAutoHidePolicy.terminalStateSeconds, 2)
        XCTAssertLessThanOrEqual(OverlayAutoHidePolicy.terminalStateSeconds, 10)
    }
}
