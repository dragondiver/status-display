import Foundation
import Network

/// Minimaler HTTP/1.1-Server nur auf 127.0.0.1, eine Anfrage pro Verbindung.
public final class HTTPServer {
    public enum State: Equatable { case stopped, ready, failed(String) }

    /// Puffer je Verbindung als Referenztyp: Anhängen ist amortisiert O(1),
    /// kein Kopieren des gesamten Puffers bei jedem Chunk.
    private final class ConnectionState {
        var data = Data()
        var closed = false
    }

    public var onStateChange: ((State) -> Void)?
    private let port: UInt16
    private let readTimeout: TimeInterval
    private let maxConnections: Int
    private let handler: (HTTPRequest) -> HTTPResponse
    private let queue = DispatchQueue(label: "status-display.http")
    private var listener: NWListener?
    private var openConnections = 0

    public init(port: UInt16, readTimeout: TimeInterval = 10, maxConnections: Int = 32,
                handler: @escaping (HTTPRequest) -> HTTPResponse) {
        self.port = port
        self.readTimeout = readTimeout
        self.maxConnections = maxConnections
        self.handler = handler
    }

    public func start() throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!)
        params.allowLocalEndpointReuse = true
        let l = try NWListener(using: params)
        l.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.onStateChange?(.ready)
            case .failed(let error): self?.onStateChange?(.failed("Port \(self?.port ?? 0): \(error)"))
            default: break
            }
        }
        l.newConnectionHandler = { [weak self] c in self?.serve(c) }
        l.start(queue: queue)
        listener = l
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        onStateChange?(.stopped)
    }

    private func serve(_ connection: NWConnection) {
        guard openConnections < maxConnections else {
            connection.cancel()
            return
        }
        openConnections += 1
        let state = ConnectionState()
        let timeoutItem = DispatchWorkItem { [weak self, weak connection] in
            connection?.cancel()
            self?.finish(state)
        }
        queue.asyncAfter(deadline: .now() + readTimeout, execute: timeoutItem)
        connection.start(queue: queue)
        receive(connection, state: state, timeoutItem: timeoutItem)
    }

    private func receive(_ c: NWConnection, state: ConnectionState, timeoutItem: DispatchWorkItem) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { c.cancel(); return }
            if let data { state.data.append(data) }
            switch HTTPParser.parse(state.data) {
            case .complete(let request):
                timeoutItem.cancel()
                self.respond(c, self.handler(request), state: state)
            case .invalid:
                timeoutItem.cancel()
                self.respond(c, .json(400, ["error": "ungültige Anfrage"]), state: state)
            case .incomplete:
                if isComplete || error != nil {
                    timeoutItem.cancel()
                    c.cancel()
                    self.finish(state)
                } else {
                    self.receive(c, state: state, timeoutItem: timeoutItem)
                }
            }
        }
    }

    private func respond(_ c: NWConnection, _ response: HTTPResponse, state: ConnectionState) {
        c.send(content: response.serialized(), completion: .contentProcessed { [weak self] _ in
            c.cancel()
            self?.finish(state)
        })
    }

    /// Läuft immer auf `queue` (Listener-, Verbindungs- und Timeout-Callbacks teilen sich die Queue),
    /// daher braucht `openConnections`/`state.closed` keine zusätzliche Synchronisierung.
    private func finish(_ state: ConnectionState) {
        guard !state.closed else { return }
        state.closed = true
        openConnections -= 1
    }
}
