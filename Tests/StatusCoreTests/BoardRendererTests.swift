import XCTest
@testable import StatusCore

final class BoardRendererTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func row(_ repository: String, toReview: Int = 0, mine: Int = 0, ciFailing: Bool = false) -> PRRow {
        PRRow(repoKey: "github.com/f/\(repository)", repository: repository, toReview: toReview, mine: mine,
             ciFailing: ciFailing)
    }

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
        let failing = PRZone(rows: [row("a", mine: 2, ciFailing: true)], ciFailingCount: 1, lastSuccess: t0,
                             isStale: false)
        XCTAssertTrue(isRed(pixel(BoardRenderer.render(state(prs: failing)), 1246, 230)))
        let fine = PRZone(rows: [row("a", mine: 2)], ciFailingCount: 0, lastSuccess: t0, isStale: false)
        XCTAssertFalse(isRed(pixel(BoardRenderer.render(state(prs: fine)), 1246, 230)))
        let stale = PRZone(rows: [row("a", mine: 2, ciFailing: true)], ciFailingCount: 1, lastSuccess: t0,
                           isStale: true)
        XCTAssertFalse(isRed(pixel(BoardRenderer.render(state(prs: stale)), 1246, 230)), "veraltet: kein Alarm")
    }

    func testWaitingAgentGetsHighlightBand() {
        let waiting = AgentActivity(id: "a", source: "x", name: "rundfunk", state: .waiting,
                                    since: t0, lastSeen: t0)
        let img = BoardRenderer.render(state(agents: [waiting]))
        let p = pixel(img, 1210, 110)
        XCTAssertGreaterThan(Int(p.r), Int(p.b) + 20, "gelblicher Hintergrund in der Zeile")
    }

    // MARK: PR-Tabelle und Uhr (Issue #14)

    func testClockIsBottomLeftOfStatusZone() {
        // 72 pt fett, unten links in der 480 px breiten Statuszone: weiße Glyphenpixel bei x<200,
        // deutlich unterhalb des Statusnamens (der jetzt nach oben rückt) und oberhalb des unteren Rands.
        let img = BoardRenderer.render(state())
        var sawWhite = false
        for y in 350...445 {
            for x in stride(from: 40, to: 200, by: 2) {
                if isWhitish(pixel(img, x, y)) { sawWhite = true }
            }
        }
        XCTAssertTrue(sawWhite, "Uhr zeichnet weiße Pixel unten links in der Statuszone")
        // Zwischen dem (nach oben gerückten) Statusnamen und der Uhr bleibt eine Lücke ohne Text,
        // die beiden Zonen überlappen also nicht.
        var sawWhiteInGap = false
        for y in 240...330 {
            for x in stride(from: 40, to: 400, by: 2) where isWhitish(pixel(img, x, y)) {
                sawWhiteInGap = true
            }
        }
        XCTAssertFalse(sawWhiteInGap, "Statusname und Uhr überlappen nicht")
    }

    func testOnlySingleSeparatorAt1240() {
        let img = BoardRenderer.render(state())
        // Trennlinie bei 1240 existiert weiterhin …
        XCTAssertTrue(isSeparator(pixel(img, 1240, 200)))
        // … die frühere zweite Trennlinie bei 1660 (alte Uhr-Zone) ist weg: dort steht jetzt Tabelleninhalt
        // oder Hintergrund, nicht die separate Trennfarbe über die volle Höhe.
        XCTAssertFalse(isSeparator(pixel(img, 1660, 41)))
    }

    func testRedDotBeforeRepoWhenOwnCIFails() {
        let failing = PRZone(rows: [row("telefon-ai", mine: 1, ciFailing: true)], ciFailingCount: 1,
                             lastSuccess: t0, isStale: false)
        let img = BoardRenderer.render(state(prs: failing))
        // Punkt liegt bei x0=1270, erste Zeile bei baseline 165, Durchmesser 26.
        XCTAssertTrue(isRed(pixel(img, 1280, 152)), "roter Punkt vor dem Repo-Namen")

        let fine = PRZone(rows: [row("telefon-ai", mine: 1, ciFailing: false)], ciFailingCount: 0,
                          lastSuccess: t0, isStale: false)
        XCTAssertFalse(isRed(pixel(BoardRenderer.render(state(prs: fine)), 1280, 152)))
    }

    func testStaleTableIsGreyNotWhite() {
        let fresh = PRZone(rows: [row("telefon-ai", toReview: 1)], ciFailingCount: 0, lastSuccess: t0, isStale: false)
        let stale = PRZone(rows: [row("telefon-ai", toReview: 1)], ciFailingCount: 0, lastSuccess: t0, isStale: true)
        let freshImg = BoardRenderer.render(state(prs: fresh))
        let staleImg = BoardRenderer.render(state(prs: stale))
        var freshSawWhite = false
        var staleSawWhite = false
        for x in stride(from: 1320, to: 1600, by: 2) {
            for y in 140...185 {
                if isWhitish(pixel(freshImg, x, y)) { freshSawWhite = true }
                if isWhitish(pixel(staleImg, x, y)) { staleSawWhite = true }
            }
        }
        XCTAssertTrue(freshSawWhite, "frische Tabelle zeichnet weißen Text")
        XCTAssertFalse(staleSawWhite, "veraltete Tabelle zeichnet grau, nicht weiß")
    }

    func testUnknownShowsQuestionMarkWhenNeverFetched() {
        let img = BoardRenderer.render(state(prs: .unknown))
        var sawWhiteOrGrey = false
        for x in stride(from: 1260, to: 1400, by: 2) {
            for y in 200...300 where isWhitish(pixel(img, x, y)) || isGreyish(pixel(img, x, y)) {
                sawWhiteOrGrey = true
            }
        }
        XCTAssertTrue(sawWhiteOrGrey, "Fragezeichen wird gezeichnet, wenn noch nie erfolgreich geladen wurde")
    }
}
