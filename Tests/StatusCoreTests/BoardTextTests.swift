import XCTest
@testable import StatusCore

final class BoardTextTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func agent(_ state: AgentState, stale: Bool = false, since: Date? = nil,
                       lastSeen: Date? = nil) -> AgentActivity {
        AgentActivity(id: UUID().uuidString, source: "x", name: "n", state: state,
                      since: since ?? t0, lastSeen: lastSeen ?? t0, isStale: stale)
    }

    func testSince() {
        XCTAssertEqual(BoardText.since(t0, now: t0.addingTimeInterval(47 * 60 + 30)), "seit 47 min")
        XCTAssertEqual(BoardText.since(t0, now: t0.addingTimeInterval(125 * 60)), "seit 2:05 h")
        XCTAssertEqual(BoardText.since(t0, now: t0.addingTimeInterval(-10)), "seit 0 min")
    }

    func testAgentLabel() {
        let now = t0.addingTimeInterval(4 * 60)
        XCTAssertEqual(BoardText.agentLabel(agent(.running), now: now), "läuft")
        XCTAssertEqual(BoardText.agentLabel(agent(.running, stale: true), now: now), "unklar seit 4 min")
        XCTAssertEqual(BoardText.agentLabel(agent(.waiting), now: now), "wartet 4 min")
        XCTAssertEqual(BoardText.agentLabel(agent(.error), now: now), "Fehler")
        XCTAssertEqual(BoardText.agentLabel(agent(.done), now: now), "fertig")
    }

    func testAgentLabelUsesHoursAndStaleAge() {
        let now = t0.addingTimeInterval(65 * 60)
        XCTAssertEqual(BoardText.agentLabel(agent(.waiting), now: now), "wartet 1:05 h")
        XCTAssertEqual(BoardText.agentLabel(agent(.waiting, since: now.addingTimeInterval(-59 * 60)), now: now),
                       "wartet 59 min")
        XCTAssertEqual(BoardText.agentLabel(agent(.running, stale: true, since: t0.addingTimeInterval(-3600),
                                                  lastSeen: now.addingTimeInterval(-45 * 60)), now: now),
                       "unklar seit 45 min")
        XCTAssertEqual(BoardText.agentLabel(agent(.running, stale: true, lastSeen: t0), now: now),
                       "unklar seit 1:05 h")
    }

    func testTruncate() {
        XCTAssertEqual(BoardText.truncate("telefon-ai", max: 20), "telefon-ai")
        XCTAssertEqual(BoardText.truncate("ein-sehr-langer-projektname-x", max: 12), "ein-sehr-la…")
    }

    func testVisibleAgents() {
        let four = (0..<4).map { _ in agent(.running) }
        XCTAssertEqual(BoardText.visibleAgents(four).rows.count, 4)
        XCTAssertEqual(BoardText.visibleAgents(four).more, 0)
        let six = (0..<6).map { _ in agent(.running) }
        XCTAssertEqual(BoardText.visibleAgents(six).rows.count, 3)
        XCTAssertEqual(BoardText.visibleAgents(six).more, 3)
    }

    func testVisiblePRRows() {
        func row(_ n: Int) -> PRRow {
            PRRow(repoKey: "github.com/f/r\(n)", repository: "r\(n)", toReview: 0, mine: 0, ciFailing: false)
        }
        let four = (0..<4).map(row)
        XCTAssertEqual(BoardText.visiblePRRows(four).rows.count, 4)
        XCTAssertEqual(BoardText.visiblePRRows(four).more, 0)
        let seven = (0..<7).map(row)
        XCTAssertEqual(BoardText.visiblePRRows(seven).rows.count, 4)
        XCTAssertEqual(BoardText.visiblePRRows(seven).more, 3)
    }

    func testStatusFontShrinksForLongWords() {
        XCTAssertEqual(BoardText.statusFontSize(for: "DEEP", width: 420, maxSize: 92), 92)
        XCTAssertLessThan(BoardText.statusFontSize(for: "VERFÜGBARKEIT", width: 420, maxSize: 92), 60)
    }

    func testClock() {
        XCTAssertEqual(BoardText.clock(t0, timeZone: TimeZone(identifier: "UTC")!), "14:13")
    }
}
