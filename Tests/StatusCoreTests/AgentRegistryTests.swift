import XCTest
@testable import StatusCore

final class AgentRegistryTests: XCTestCase {
    private let time = ManualTime()
    private lazy var registry = AgentRegistry(time: time)

    private func event(_ state: String, session: String = "s1", project: String? = "telefon-ai") -> AgentEvent {
        AgentEvent(source: "claude-code", session: session, state: state, name: nil, project: project, detail: nil, url: nil)
    }

    func testValidation() {
        XCTAssertThrowsError(try AgentEvent(source: "", session: "a", state: "running").validate()) {
            XCTAssertEqual($0 as? AgentEventError, .missingField("source"))
        }
        XCTAssertThrowsError(try AgentEvent(source: "x", session: "", state: "running").validate()) {
            XCTAssertEqual($0 as? AgentEventError, .missingField("session"))
        }
        XCTAssertThrowsError(try AgentEvent(source: "x", session: "a", state: "busy").validate()) {
            XCTAssertEqual($0 as? AgentEventError, .unknownState("busy"))
        }
        XCTAssertNoThrow(try AgentEvent(source: "x", session: "a", state: "ended").validate())
    }

    func testRunningEntryUsesProjectAsName() throws {
        try registry.apply(event("running"))
        let a = registry.snapshot()
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(a[0].id, "claude-code:s1")
        XCTAssertEqual(a[0].name, "telefon-ai")
        XCTAssertEqual(a[0].state, .running)
    }

    func testSameStateKeepsSinceButRefreshesLastSeen() throws {
        try registry.apply(event("running"))
        let start = time.now
        time.advance(100)
        try registry.apply(event("running"))
        let a = registry.snapshot()[0]
        XCTAssertEqual(a.since, start)
        XCTAssertEqual(a.lastSeen, time.now)
    }

    func testStateChangeResetsSince() throws {
        try registry.apply(event("running"))
        time.advance(100)
        try registry.apply(event("waiting"))
        XCTAssertEqual(registry.snapshot()[0].since, time.now)
    }

    func testEndedRemoves() throws {
        try registry.apply(event("running"))
        try registry.apply(event("ended"))
        XCTAssertTrue(registry.snapshot().isEmpty)
    }

    func testDoneDisappearsAfterTenMinutes() throws {
        try registry.apply(event("done"))
        time.advance(599)
        XCTAssertEqual(registry.snapshot().count, 1)
        time.advance(2)
        XCTAssertTrue(registry.snapshot().isEmpty)
    }

    func testRunningBecomesStaleThenRemoved() throws {
        try registry.apply(event("running"))
        time.advance(1801)
        XCTAssertTrue(registry.snapshot()[0].isStale)
        time.advance(14_400)
        XCTAssertTrue(registry.snapshot().isEmpty)
    }

    func testWaitingAndErrorStayUntilDismissed() throws {
        try registry.apply(event("waiting", session: "a"))
        try registry.apply(event("error", session: "b"))
        time.advance(100_000)
        let a = registry.snapshot()
        XCTAssertEqual(a.count, 2)
        XCTAssertFalse(a.contains { $0.isStale })
        registry.dismiss(id: "claude-code:a")
        XCTAssertEqual(registry.snapshot().map(\.id), ["claude-code:b"])
    }

    func testSortOrderWaitingErrorRunningStaleDone() throws {
        try registry.apply(event("running", session: "stale"))
        time.advance(1801)
        try registry.apply(event("done", session: "done"))
        try registry.apply(event("running", session: "run"))
        try registry.apply(event("error", session: "err"))
        try registry.apply(event("waiting", session: "wait2"))
        time.advance(1)
        try registry.apply(event("waiting", session: "wait1b"))
        XCTAssertEqual(registry.snapshot().map(\.id).map { $0.replacingOccurrences(of: "claude-code:", with: "") },
                       ["wait2", "wait1b", "err", "run", "stale", "done"])
    }

    func testInvalidEventThrowsAndChangesNothing() {
        XCTAssertThrowsError(try registry.apply(event("busy")))
        XCTAssertTrue(registry.snapshot().isEmpty)
    }

    func testURLAcceptsOnlyHTTPAndHTTPS() throws {
        func url(_ u: String) throws -> URL? {
            try registry.apply(AgentEvent(source: "x", session: u, state: "running", name: nil, project: nil,
                                          detail: nil, url: u))
            return registry.snapshot().first { $0.id == "x:\(u)" }?.url
        }
        XCTAssertNil(try url("file:///Applications/Calculator.app"))
        XCTAssertNil(try url("x-foo://bar"))
        XCTAssertEqual(try url("https://github.com/a/b/pull/1"), URL(string: "https://github.com/a/b/pull/1"))
        XCTAssertEqual(try url("HTTP://example.com"), URL(string: "HTTP://example.com"))
    }
}
