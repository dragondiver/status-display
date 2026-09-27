import Foundation
import Network

/// Minimaler HTTP/1.1-Server nur auf 127.0.0.1, eine Anfrage pro Verbindung.
public final class HTTPServer {
    public enum State: Equatable { case stopped, ready, failed(String) }

    public var onStateChange: ((State) -> Void)?
    private let port: UInt16
    private let handler: (HTTPRequest) -> HTTPResponse
    private let queue = DispatchQueue(label: "status-display.http")
    private var listener: NWListener?

    public init(port: UInt16, handler: @escaping (HTTPRequest) -> HTTPResponse) {
        self.port = port
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
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ c: NWConnection, buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { c.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }
            switch HTTPParser.parse(buffer) {
            case .complete(let request): self.respond(c, self.handler(request))
            case .invalid: self.respond(c, .json(400, ["error": "ungültige Anfrage"]))
            case .incomplete:
                if isComplete || error != nil { c.cancel() } else { self.receive(c, buffer: buffer) }
            }
        }
    }

    private func respond(_ c: NWConnection, _ response: HTTPResponse) {
        c.send(content: response.serialized(), completion: .contentProcessed { _ in c.cancel() })
    }
}
