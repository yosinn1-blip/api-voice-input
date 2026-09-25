import Foundation

/// ブラウザ拡張とアプリの間の、ごく小さな取り決め。
///
/// なぜローカルサーバなのか（2026-09-18）:
/// AppleScript には「どのタブが鳴っているか」を知る手段がない。全タブへ JavaScript を
/// 撃つと Chrome が破棄済みタブを1枚ずつ復帰させるため実測で842秒まで膨らみ、
/// アクティブタブだけに絞ると背面タブの再生を取りこぼす。どちらも失敗する。
/// YouTube のページ側に居る content script なら、生きているタブだけが自分で反応でき、
/// 破棄済みタブを起こすこともない。そのための一方向の合図だけをここで定義する。
public enum BrowserPauseBridgeProtocol {
    public struct Request: Equatable, Sendable {
        public let method: String
        public let path: String
        public let query: String
        public let origin: String?
        public let body: String
    }

    /// 合図を受け取ってよいページ。
    /// 平文 HTTP を除くのは、中間者が YouTube を名乗れてしまうため。
    public static let allowedOrigins: Set<String> = [
        "https://www.youtube.com",
        "https://youtube.com",
        "https://m.youtube.com",
        "https://music.youtube.com"
    ]

    public static func isAllowedOrigin(_ origin: String?) -> Bool {
        guard let origin else { return false }
        return allowedOrigins.contains(origin)
    }

    /// ヘッダ終端まで届いていなければ nil を返す（届いた分だけで判断しない）。
    public static func parseRequest(_ raw: String) -> Request? {
        guard let headerEnd = raw.range(of: "\r\n\r\n") else { return nil }
        let head = String(raw[raw.startIndex..<headerEnd.lowerBound])
        let body = String(raw[headerEnd.upperBound...])
        var lines = head.components(separatedBy: "\r\n")
        guard lines.isEmpty == false else { return nil }
        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: true)
        guard requestLine.count >= 2 else { return nil }

        var origin: String?
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            guard name == "origin" else { continue }
            origin = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }

        let fullPath = String(requestLine[1])
        let parts = fullPath.split(separator: "?", maxSplits: 1)
        let path = parts.first.map(String.init) ?? fullPath
        let query = parts.count > 1 ? String(parts[1]) : ""

        return Request(method: String(requestLine[0]).uppercased(), path: path, query: query, origin: origin, body: body)
    }

    /// SSE を開くときの応答ヘッダ。
    /// `Content-Length` を付けると本文の終わりが確定してブラウザが接続を閉じてしまうため付けない。
    public static func eventStreamResponseHeader(origin: String) -> String {
        [
            "HTTP/1.1 200 OK",
            "Content-Type: text/event-stream; charset=utf-8",
            "Cache-Control: no-cache",
            "Connection: keep-alive",
            "Access-Control-Allow-Origin: \(origin)",
            "X-Content-Type-Options: nosniff",
            "", ""
        ].joined(separator: "\r\n")
    }

    public static func okResponse(origin: String, body: String = "ok") -> String {
        [
            "HTTP/1.1 200 OK",
            "Content-Type: text/plain; charset=utf-8",
            "Content-Length: \(body.utf8.count)",
            "Access-Control-Allow-Origin: \(origin)",
            "Connection: close",
            "",
            body
        ].joined(separator: "\r\n")
    }

    public static func forbiddenResponse() -> String {
        [
            "HTTP/1.1 403 Forbidden",
            "Content-Length: 0",
            "Connection: close",
            "", ""
        ].joined(separator: "\r\n")
    }

    /// Chrome は公開サイトからローカルアドレスへの通信に事前確認（Private Network Access）を
    /// 要求することがある。許可を返さないと EventSource も fetch も無言で失敗するため、
    /// OPTIONS には必ずこの応答を返す。
    public static func preflightResponse(origin: String) -> String {
        [
            "HTTP/1.1 204 No Content",
            "Access-Control-Allow-Origin: \(origin)",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "Access-Control-Allow-Headers: Content-Type",
            "Access-Control-Allow-Private-Network: true",
            "Access-Control-Max-Age: 86400",
            "Connection: close",
            "", ""
        ].joined(separator: "\r\n")
    }

    /// 再生を止めてほしいという合図。
    public static func pauseEvent() -> String { "data: pause\n\n" }

    /// 接続を維持するだけのコメント行。`onmessage` は呼ばれない。
    public static func keepAliveEvent() -> String { ": keep-alive\n\n" }

    /// クエリ文字列から値を取り出す。
    public static func queryValue(_ name: String, in query: String) -> String? {
        for pair in query.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard kv.count == 2, String(kv[0]) == name else { continue }
            return String(kv[1])
        }
        return nil
    }

    /// 拡張が「何本止めたか」を返してくる報告。検証できるようにするためだけに存在する。
    ///
    /// GET で受けるのは、Chrome が POST の fetch をローカルアドレス宛に送らない（プリフライト前に
    /// 止まる）場面を実機で踏んだため。EventSource と同じ GET なら同じ経路で通る。
    public static func parsePausedCount(_ body: String) -> Int? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, let value = Int(trimmed), value >= 0 else { return nil }
        return value
    }
}
