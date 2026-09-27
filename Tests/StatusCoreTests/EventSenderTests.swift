import XCTest
@testable import StatusCore

final class EventSenderTests: XCTestCase {
    func testSendsToRunningServer() throws {
        let port = UInt16.random(in: 50_000...59_000)
        var received: [AgentEvent] = []
        let router = IngressRouter(token: "t", knownPresets: Locked([]), onEvent: { received.append($0) }, onStatus: { _, _ in })
        let server = HTTPServer(port: port, handler: router.handle)
        let ready = expectation(description: "bereit")
        server.onStateChange = { if $0 == .ready { ready.fulfill() } }
        try server.start()
        wait(for: [ready], timeout: 3)
        defer { server.stop() }

        let event = AgentEvent(source: "claude-code", session: "s", state: "running")
        XCTAssertTrue(EventSender.send(event, endpoint: Endpoint(port: port), token: "t"))
        XCTAssertEqual(received, [event])
    }

    func testClosedPortFailsFast() {
        let start = Date()
        let ok = EventSender.send(AgentEvent(source: "a", session: "b", state: "running"),
                                  endpoint: Endpoint(port: 1), token: "t")
        XCTAssertFalse(ok)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }
}
