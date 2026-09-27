import XCTest
@testable import StatusCore

final class HTTPServerTests: XCTestCase {
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
