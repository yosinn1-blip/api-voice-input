import APIVoiceInputCore
import Foundation
import Network

/// ブラウザ拡張へ「今から録音するので再生中の動画を止めて」と伝えるためだけの
/// 極小のローカルサーバ（127.0.0.1 のみで待ち受ける）。
///
/// 背景は `BrowserPauseBridgeProtocol` を参照。要点は、AppleScript では
/// 「どのタブが鳴っているか」が分からず、全タブ巡回は破棄済みタブを起こして
/// 数百秒かかり、アクティブタブのみでは背面タブを取りこぼす、という点。
/// ページ側の content script は生きているタブだけが反応するので、この2つを同時に避けられる。
final class BrowserPauseBridge: @unchecked Sendable {
    static let shared = BrowserPauseBridge()
    static let defaultPort: UInt16 = 47623

    private let queue = DispatchQueue(label: "com.yoshiki.APIVoiceInput.browser-pause-bridge")
    private var listener: NWListener?
    private var eventClients: [NWConnection] = []
    private var keepAliveTimer: DispatchSourceTimer?

    private init() {}

    /// SSE を張っている YouTube タブの数。0 なら拡張が入っていないか、YouTube を開いていない。
    var connectedTabCount: Int {
        queue.sync { eventClients.count }
    }

    func start(port: UInt16 = BrowserPauseBridge.defaultPort) {
        queue.async { [self] in
            guard listener == nil else { return }
            guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }

            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            // 外部インターフェースでは待ち受けない。
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: nwPort)

            do {
                let listener = try NWListener(using: parameters)
                listener.newConnectionHandler = { [weak self] connection in
                    self?.accept(connection)
                }
                listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        DebugLog.write("browser bridge listening port=\(port)")
                    case .failed(let error):
                        DebugLog.write("browser bridge failed error=\(error.localizedDescription)")
                    case .cancelled:
                        DebugLog.write("browser bridge cancelled")
                    default:
                        break
                    }
                }
                listener.start(queue: queue)
                self.listener = listener
                startKeepAlive()
            } catch {
                DebugLog.write("browser bridge start failed error=\(error.localizedDescription)")
            }
        }
    }

    /// 接続中の全タブへ pause を配る。戻り値は配った相手の数。
    /// 録音開始を待たせないよう、送信自体は非同期で進む。
    @discardableResult
    func broadcastPause() -> Int {
        queue.sync {
            let clients = eventClients
            for client in clients {
                send(BrowserPauseBridgeProtocol.pauseEvent(), on: client, closeAfterSending: false)
            }
            return clients.count
        }
    }

    // MARK: - 接続の処理

    private func accept(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.removeClient(connection)
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveRequest(on: connection, accumulated: "")
    }

    private func receiveRequest(on connection: NWConnection, accumulated: String) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if error != nil || (data == nil && isComplete) {
                self.removeClient(connection)
                connection.cancel()
                return
            }
            var text = accumulated
            if let data, let chunk = String(data: data, encoding: .utf8) {
                text += chunk
            }
            guard let request = BrowserPauseBridgeProtocol.parseRequest(text) else {
                guard text.utf8.count < 16 * 1024 else {
                    connection.cancel()
                    return
                }
                self.receiveRequest(on: connection, accumulated: text)
                return
            }
            self.handle(request, on: connection)
        }
    }

    private func handle(_ request: BrowserPauseBridgeProtocol.Request, on connection: NWConnection) {
        DebugLog.write("browser bridge request method=\(request.method) path=\(request.path) origin=\(request.origin ?? "nil")")
        guard BrowserPauseBridgeProtocol.isAllowedOrigin(request.origin), let origin = request.origin else {
            send(BrowserPauseBridgeProtocol.forbiddenResponse(), on: connection, closeAfterSending: true)
            return
        }

        switch (request.method, request.path) {
        case ("OPTIONS", _):
            send(BrowserPauseBridgeProtocol.preflightResponse(origin: origin), on: connection, closeAfterSending: true)
        case ("GET", "/events"):
            send(BrowserPauseBridgeProtocol.eventStreamResponseHeader(origin: origin), on: connection, closeAfterSending: false)
            eventClients.append(connection)
            DebugLog.write("browser bridge tab connected total=\(eventClients.count)")
        case ("GET", "/paused"), ("POST", "/paused"):
            // 値はクエリ（GET）か本文（POST）のどちらかで届く。
            // Chrome は POST の fetch をローカルアドレスへ送らないことがあるため GET を主経路にしている。
            let reported = BrowserPauseBridgeProtocol.queryValue("n", in: request.query) ?? request.body
            if let count = BrowserPauseBridgeProtocol.parsePausedCount(reported) {
                DebugLog.write("browser bridge extension paused=\(count)")
            }
            send(BrowserPauseBridgeProtocol.okResponse(origin: origin), on: connection, closeAfterSending: true)
        default:
            send(BrowserPauseBridgeProtocol.forbiddenResponse(), on: connection, closeAfterSending: true)
        }
    }

    private func send(_ text: String, on connection: NWConnection, closeAfterSending: Bool) {
        connection.send(content: Data(text.utf8), completion: .contentProcessed { [weak self] error in
            if error != nil {
                self?.removeClient(connection)
                connection.cancel()
                return
            }
            if closeAfterSending {
                connection.cancel()
            }
        })
    }

    private func removeClient(_ connection: NWConnection) {
        queue.async { [self] in
            let before = eventClients.count
            eventClients.removeAll { $0 === connection }
            if eventClients.count != before {
                DebugLog.write("browser bridge tab disconnected total=\(eventClients.count)")
            }
        }
    }

    /// 死んだ接続を溜め込まないよう、定期的にコメント行を流して切断を検出する。
    private func startKeepAlive() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 25, repeating: 25)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            for client in self.eventClients {
                self.send(BrowserPauseBridgeProtocol.keepAliveEvent(), on: client, closeAfterSending: false)
            }
        }
        timer.resume()
        keepAliveTimer = timer
    }
}
