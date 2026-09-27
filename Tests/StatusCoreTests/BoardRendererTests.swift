import XCTest
@testable import StatusCore

final class BoardRendererTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func state(prs: PRZone = .unknown, agents: [AgentActivity] = []) -> BoardState {
        BoardState(statusName: "Deep Focus", statusColor: RGBColor(hex: "#FF0000")!, statusSince: t0,
                   agents: agents, prs: prs, now: t0.addingTimeInterval(600))
    }

    func testSizeAndStatusColor() {
        let img = BoardRenderer.render(state())
        XCTAssertEqual(img.width, 1920)
        XCTAssertEqual(img.height, 462)
        XCTAssertTrue(isRed(pixel(img, 5, 5)), "Statuszone in Statusfarbe")
        XCTAssertFalse(isRed(pixel(img, 1000, 5)))
    }

    func testRedBorderWhenOwnCIFails() {
        let failing = PRZone(toReview: 1, mine: 2, ciFailing: 1, lastSuccess: t0, isStale: false)
        XCTAssertTrue(isRed(pixel(BoardRenderer.render(state(prs: failing)), 1246, 230)))
        let fine = PRZone(toReview: 1, mine: 2, ciFailing: 0, lastSuccess: t0, isStale: false)
        XCTAssertFalse(isRed(pixel(BoardRenderer.render(state(prs: fine)), 1246, 230)))
        let stale = PRZone(toReview: 1, mine: 2, ciFailing: 1, lastSuccess: t0, isStale: true)
        XCTAssertFalse(isRed(pixel(BoardRenderer.render(state(prs: stale)), 1246, 230)), "veraltet: kein Alarm")
    }

    func testWaitingAgentGetsHighlightBand() {
        let waiting = AgentActivity(id: "a", source: "x", name: "rundfunk", state: .waiting,
                                    since: t0, lastSeen: t0)
        let img = BoardRenderer.render(state(agents: [waiting]))
        let p = pixel(img, 1210, 110)
        XCTAssertGreaterThan(Int(p.r), Int(p.b) + 20, "gelblicher Hintergrund in der Zeile")
    }
}
