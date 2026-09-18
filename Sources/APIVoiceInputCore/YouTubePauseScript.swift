import Foundation

/// 録音開始時にブラウザの YouTube 動画を一時停止する AppleScript の生成。
///
/// 設計上の制約（2026-09-13、実測にもとづく）:
///
/// - **各ウィンドウのアクティブタブしか触らない。** 全タブを巡回して
///   `execute javascript` を撃つと、Chrome がメモリ破棄済みの背面タブを
///   1枚ずつ復帰させるため、タブ1枚あたり数十秒かかる。実機（120タブ / うち
///   YouTube 47タブ）では巡回全体が数十分に膨らみ、debug.log 上の所要時間中央値は
///   2026-05 の 1秒から 2026-09 には 842秒まで悪化していた。
///   アクティブタブだけなら実測1秒で、実際に再生中の動画を捉えられる。
/// - **壁時計の締切を持つ。** ウィンドウ数が増えても巡回が青天井にならないようにし、
///   打ち切ったことを `timedOut=1` として呼び出し側へ返す。
/// - **再生中の video だけを pause する。** 止まっている動画に触らないことで、
///   ユーザーが自分で止めた動画を勝手に操作しない。
public enum YouTubePauseScript {
    /// 巡回を打ち切るまでの秒数。AppleScript の `current date` は秒精度なので実効は 3〜4 秒。
    public static let deadlineSeconds = 3

    public static func chromium(bundleIdentifier: String) -> String {
        script(bundleIdentifier: bundleIdentifier, activeTabExpression: "active tab of w", executeJavaScript: { js in
            "set jsResult to execute t javascript \(js)"
        })
    }

    public static func safari(bundleIdentifier: String) -> String {
        script(bundleIdentifier: bundleIdentifier, activeTabExpression: "current tab of w", executeJavaScript: { js in
            "set jsResult to do JavaScript \(js) in t"
        })
    }

    private static let pauseJavaScript = """
    "(() => { const host = location.hostname.toLowerCase(); if (!(host === 'youtu.be' || host === 'youtube.com' || host.endsWith('.youtube.com'))) return 0; let count = 0; for (const video of document.querySelectorAll('video')) { if (!video.paused) { video.pause(); count += 1; } } return count; })();"
    """

    private static func script(
        bundleIdentifier: String,
        activeTabExpression: String,
        executeJavaScript: (String) -> String
    ) -> String {
        """
        set matchedTabs to 0
        set pausedVideos to 0
        set errorCount to 0
        set timedOut to 0
        set deadlineSeconds to \(deadlineSeconds)
        set startedAt to current date
        tell application id "\(bundleIdentifier)"
            repeat with w in windows
                if ((current date) - startedAt) ≥ deadlineSeconds then
                    set timedOut to 1
                    exit repeat
                end if
                try
                    set t to \(activeTabExpression)
                    set tabURL to URL of t as text
                    if my isYouTubeURL(tabURL) then
                        set matchedTabs to matchedTabs + 1
                        try
                            \(executeJavaScript(pauseJavaScript.trimmingCharacters(in: .whitespacesAndNewlines)))
                            try
                                set pausedVideos to pausedVideos + (jsResult as integer)
                            end try
                        on error
                            set errorCount to errorCount + 1
                        end try
                    end if
                end try
            end repeat
        end tell
        return "tabs=" & (matchedTabs as text) & " pausedVideos=" & (pausedVideos as text) & " errors=" & (errorCount as text) & " timedOut=" & (timedOut as text) & " scope=activeTabs"

        on isYouTubeURL(tabURL)
            return tabURL starts with "https://youtube.com/" or tabURL starts with "http://youtube.com/" or tabURL starts with "https://www.youtube.com/" or tabURL starts with "http://www.youtube.com/" or tabURL starts with "https://m.youtube.com/" or tabURL starts with "http://m.youtube.com/" or tabURL starts with "https://music.youtube.com/" or tabURL starts with "http://music.youtube.com/" or tabURL starts with "https://youtu.be/" or tabURL starts with "http://youtu.be/"
        end isYouTubeURL
        """
    }
}
