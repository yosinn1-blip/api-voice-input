import Foundation

public enum YouTubePauseFallbackAction: Equatable {
    case none
    case tryMediaRemotePause
}

public enum YouTubePauseFallbackDecision {
    public static func fallbackAction(scriptOutput: String) -> YouTubePauseFallbackAction {
        let values = parseCounters(from: scriptOutput)
        let tabs = values["tabs", default: 0]
        let pausedVideos = values["pausedVideos", default: 0]
        let errors = values["errors", default: 0]

        if tabs > 0 && pausedVideos == 0 && errors > 0 {
            return .tryMediaRemotePause
        }
        return .none
    }

    private static func parseCounters(from output: String) -> [String: Int] {
        var counters: [String: Int] = [:]
        for part in output.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }) {
            let pair = part.split(separator: "=", maxSplits: 1)
            guard pair.count == 2, let value = Int(pair[1]) else { continue }
            counters[String(pair[0])] = value
        }
        return counters
    }
}


/// MediaRemote へ pause を送った結果を「本当に止められた」と見なしてよいかの判定。
///
/// `snapshotDisplayID == nil` は「MediaRemote が再生元アプリを答えられなかった」という
/// 情報ゼロの状態であり、一時停止できた証拠ではない。ここを handled 扱いにすると
/// 呼び出し側が唯一実効性のある AppleScript タブ巡回を打ち切ってしまい、
/// 機能全体が無言で無効化される（2026-09-02〜09-13 に発生した回帰）。
public enum MediaRemotePauseHandlingDecision {
    public static func isHandledPause(
        sent: Bool,
        snapshotDisplayID: String?,
        snapshotIsPlaying: Bool?,
        targetDisplayID: String
    ) -> Bool {
        sent && snapshotDisplayID == targetDisplayID && snapshotIsPlaying == true
    }
}


/// MediaRemote の pause コマンドを実際に送ってよいかの判定。
///
/// 再生元が対象ブラウザだと確認できたときだけ送る。再生元不明のまま盲撃ちすると
/// Music や Spotify など、音声入力とは無関係なアプリの再生まで止めうる。
public enum MediaRemotePauseSendDecision {
    public static func shouldSendPause(
        snapshotDisplayID: String?,
        targetDisplayID: String
    ) -> Bool {
        snapshotDisplayID == targetDisplayID
    }
}
