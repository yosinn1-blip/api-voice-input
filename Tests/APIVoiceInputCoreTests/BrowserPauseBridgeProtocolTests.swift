import XCTest
@testable import APIVoiceInputCore

final class BrowserPauseBridgeProtocolTests: XCTestCase {
    // MARK: Origin の検証

    /// ローカルサーバは同じマシンの任意のページから叩ける。
    /// ブラウザが自分で付ける Origin だけが偽装できない手がかりなので、
    /// YouTube 以外からの接続は受け付けない。
    func testAcceptsOnlyYouTubeOrigins() {
        for origin in [
            "https://www.youtube.com",
            "https://youtube.com",
            "https://m.youtube.com",
            "https://music.youtube.com"
        ] {
            XCTAssertTrue(BrowserPauseBridgeProtocol.isAllowedOrigin(origin), origin)
        }
    }

    func testRejectsOtherOrigins() {
        for origin in [
            "https://evil.example",
            "http://www.youtube.com.evil.example",
            "https://notyoutube.com",
            "https://www.youtube.com.attacker.jp",
            "null",
            ""
        ] {
            XCTAssertFalse(BrowserPauseBridgeProtocol.isAllowedOrigin(origin), origin)
        }
    }

    func testRejectsPlainHTTPYouTube() {
        // 平文 HTTP の YouTube は中間者が名乗れるので受けない。
        XCTAssertFalse(BrowserPauseBridgeProtocol.isAllowedOrigin("http://www.youtube.com"))
    }

    // MARK: リクエスト行の解釈

    func testParsesRequestLine() {
        let request = BrowserPauseBridgeProtocol.parseRequest(
            "GET /events HTTP/1.1\r\nHost: 127.0.0.1:47623\r\nOrigin: https://www.youtube.com\r\n\r\n"
        )
        XCTAssertEqual(request?.method, "GET")
        XCTAssertEqual(request?.path, "/events")
        XCTAssertEqual(request?.origin, "https://www.youtube.com")
    }

    func testParsesHeadersCaseInsensitively() {
        let request = BrowserPauseBridgeProtocol.parseRequest(
            "POST /paused HTTP/1.1\r\norigin: https://music.youtube.com\r\n\r\n3"
        )
        XCTAssertEqual(request?.method, "POST")
        XCTAssertEqual(request?.path, "/paused")
        XCTAssertEqual(request?.origin, "https://music.youtube.com")
        XCTAssertEqual(request?.body, "3")
    }

    func testReturnsNilForIncompleteRequest() {
        XCTAssertNil(BrowserPauseBridgeProtocol.parseRequest("GET /events HTTP/1.1\r\nOrigin: htt"))
        XCTAssertNil(BrowserPauseBridgeProtocol.parseRequest(""))
    }

    func testIgnoresQueryStringWhenRouting() {
        let request = BrowserPauseBridgeProtocol.parseRequest("GET /events?v=2 HTTP/1.1\r\n\r\n")
        XCTAssertEqual(request?.path, "/events")
    }

    // MARK: 応答の組み立て

    func testEventStreamHeaderKeepsConnectionOpenAndEchoesOrigin() {
        let header = BrowserPauseBridgeProtocol.eventStreamResponseHeader(origin: "https://www.youtube.com")
        XCTAssertTrue(header.contains("HTTP/1.1 200 OK"))
        XCTAssertTrue(header.contains("Content-Type: text/event-stream"))
        XCTAssertTrue(header.contains("Cache-Control: no-cache"))
        XCTAssertTrue(header.contains("Access-Control-Allow-Origin: https://www.youtube.com"))
        // Content-Length を付けるとブラウザが本文の終わりを待たずに閉じる。
        XCTAssertFalse(header.contains("Content-Length"))
        XCTAssertTrue(header.hasSuffix("\r\n\r\n"))
    }

    func testPauseEventIsASingleSSEMessage() {
        XCTAssertEqual(BrowserPauseBridgeProtocol.pauseEvent(), "data: pause\n\n")
    }

    func testKeepAliveIsAnSSECommentSoClientsIgnoreIt() {
        // コメント行は onmessage を呼ばずに接続だけ保つ。
        XCTAssertTrue(BrowserPauseBridgeProtocol.keepAliveEvent().hasPrefix(":"))
        XCTAssertTrue(BrowserPauseBridgeProtocol.keepAliveEvent().hasSuffix("\n\n"))
    }

    func testRejectionResponseIsClosedImmediately() {
        let response = BrowserPauseBridgeProtocol.forbiddenResponse()
        XCTAssertTrue(response.contains("403"))
        XCTAssertTrue(response.contains("Connection: close"))
    }

    // MARK: 拡張からの報告

    func testParsesPausedCountReport() {
        XCTAssertEqual(BrowserPauseBridgeProtocol.parsePausedCount("3"), 3)
        XCTAssertEqual(BrowserPauseBridgeProtocol.parsePausedCount(" 0 \n"), 0)
        XCTAssertNil(BrowserPauseBridgeProtocol.parsePausedCount("many"))
        XCTAssertNil(BrowserPauseBridgeProtocol.parsePausedCount(""))
        XCTAssertNil(BrowserPauseBridgeProtocol.parsePausedCount("-1"))
    }
}

extension BrowserPauseBridgeProtocolTests {
    /// Chrome の Private Network Access は、この許可がないとローカルへの接続を
    /// 無言で落とす。落ちても拡張側からは「繋がらない」としか見えないので、
    /// ヘッダの有無をテストで固定しておく。
    func testPreflightGrantsPrivateNetworkAccess() {
        let response = BrowserPauseBridgeProtocol.preflightResponse(origin: "https://www.youtube.com")
        XCTAssertTrue(response.contains("204"))
        XCTAssertTrue(response.contains("Access-Control-Allow-Private-Network: true"))
        XCTAssertTrue(response.contains("Access-Control-Allow-Origin: https://www.youtube.com"))
        XCTAssertTrue(response.contains("Access-Control-Allow-Methods: GET, POST, OPTIONS"))
    }
}
