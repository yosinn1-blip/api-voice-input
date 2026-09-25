import Foundation

/// 画面下に出るオーバーレイの表示状態。`OverlayWindowController.State` と1対1で対応する。
public enum OverlayPresentationState: String, Sendable, CaseIterable {
    case recording
    case transcribing
    case cleaning
    case pasting
    case pasted
    case failed
    case canceled
    case conversationWaiting
}

/// オーバーレイを自分で消すまでの秒数。
///
/// 背景（2026-09-18）:
/// `process()` がエラーで終わる経路（catch、Groq API key 未設定、アクセシビリティ未許可、
/// 録音ファイルなし、録音開始失敗）では `overlay.show(.failed)` のあと `hide()` を
/// 呼ばないまま return していた。オーバーレイは `ignoresMouseEvents = true` なので
/// クリックでも消せず、消す手段がアプリの再起動しか無かった。
/// debug.log では実際に `process failed error=音声認識結果が空でした。` の直後に
/// ユーザーが再起動している記録が複数残っていた。
///
/// 表示を出す側が消し忘れても画面に残らないよう、期限は「表示する側」ではなく
/// 「状態そのもの」に持たせる。
public enum OverlayAutoHidePolicy {
    /// 失敗・音声なしを出しておく秒数。読める長さで、かつ居座らない長さ。
    public static let terminalStateSeconds: Double = 4

    /// 「貼り付けました」を出しておく秒数。
    public static let completedStateSeconds: Double = 2

    /// 処理中の表示が戻ってこなかったときの保険。
    /// Groq のリクエストタイムアウト（60秒）より長くしないと、正常な待ち時間の
    /// 途中で表示が消えてしまう。
    public static let processingWatchdogSeconds: Double = 90

    /// nil は「ユーザーが終わらせるまで出しっぱなしが正しい」を意味する。
    public static func autoHideSeconds(for state: OverlayPresentationState) -> Double? {
        switch state {
        case .recording, .conversationWaiting:
            return nil
        case .transcribing, .cleaning, .pasting:
            return processingWatchdogSeconds
        case .pasted:
            return completedStateSeconds
        case .failed, .canceled:
            return terminalStateSeconds
        }
    }
}
