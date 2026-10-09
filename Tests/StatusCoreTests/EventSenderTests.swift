import XCTest
@testable import StatusCore

final class EventSenderTests: XCTestCase {
    func testSendsToRunningServer() throws {
        var received: [AgentEvent] = []
        let router = IngressRouter(token: "t", knownPresets: Locked([]), onEvent: { received.append($0) }, onStatus: { _, _ in })
        let (server, port) = try startServer(handler: router.handle)
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
