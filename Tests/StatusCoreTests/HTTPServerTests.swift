import XCTest
import Network
@testable import StatusCore

final class HTTPServerTests: XCTestCase {
    func testClosesStalledConnectionAfterTimeout() throws {
        let port = UInt16.random(in: 50_000...59_000)
        let server = HTTPServer(port: port, readTimeout: 0.5) { req in .json(200, ["path": req.path]) }
        let ready = expectation(description: "bereit")
        server.onStateChange = { if $0 == .ready { ready.fulfill() } }
        try server.start()
        wait(for: [ready], timeout: 3)
        defer { server.stop() }

        let queue = DispatchQueue(label: "test-stalled-connection")
        let conn = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        let closed = expectation(description: "vom Server geschlossen")
        var fulfilled = false
        func awaitClosure() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, isComplete, error in
                if isComplete || error != nil {
                    if !fulfilled { fulfilled = true; closed.fulfill() }
                } else {
                    awaitClosure()
                }
            }
        }
        conn.stateUpdateHandler = { state in
            if case .ready = state {
                conn.send(content: Data("POST /v1/events HTTP/1.1\r\n".utf8), completion: .contentProcessed { _ in })
                awaitClosure()
            }
        }
        conn.start(queue: queue)
        wait(for: [closed], timeout: 5)
        conn.cancel()
    }

    func testServesOnLoopback() throws {
        let port = UInt16.random(in: 50_000...59_000)
        let server = HTTPServer(port: port) { req in .json(200, ["path": req.path]) }
        let ready = expectation(description: "bereit")
        server.onStateChange = { if $0 == .ready { ready.fulfill() } }
        try server.start()
        wait(for: [ready], timeout: 3)
        defer { server.stop() }

        let done = expectation(description: "Antwort")
        var body = ""
        URLSession.shared.dataTask(with: URL(string: "http://127.0.0.1:\(port)/v1/health")!) { data, _, _ in
            body = String(decoding: data ?? Data(), as: UTF8.self)
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 3)
        XCTAssertEqual(body, #"{"path":"\/v1\/health"}"#)
    }
}
