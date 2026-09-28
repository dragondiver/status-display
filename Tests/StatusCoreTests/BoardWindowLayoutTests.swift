import CoreGraphics
import XCTest
@testable import StatusCore

/// Layout und Zeichnen des Board-Fensters in Fenstergröße (status-display#38).
final class BoardWindowLayoutTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    private let strip = CGSize(width: 480, height: 110)

    private func agent(_ name: String, state: AgentState = .running, isStale: Bool = false) -> AgentActivity {
        AgentActivity(id: name, source: "x", name: name, state: state, since: t0, lastSeen: t0, isStale: isStale)
    }

    private func row(_ repository: String, ciFailing: Bool = false) -> PRRow {
        PRRow(repoKey: "github.com/f/\(repository)", repository: repository, toReview: 1, mine: 1, ciFailing: ciFailing)
    }

    private func hiddenReview(_ number: Int) -> PullRequest {
        PullRequest(number: number, title: "t", repository: "f/versteckt",
                    url: URL(string: "https://example.com/f/versteckt/pull/\(number)")!, ciFailing: false,
                    hasCodeOwnerRequestForMe: true)
    }

    private func state(name: String = "Deep Focus", agents: [AgentActivity] = [], rows: [PRRow] = [],
                       hidden: [PullRequest] = [], ciFailing: Int = 0, stale: Bool = false) -> BoardState {
        BoardState(statusName: name, statusColor: RGBColor(hex: "#FF0000")!, statusSince: t0, agents: agents,
                   prs: PRZone(rows: rows, ciFailingCount: ciFailing, lastSuccess: t0, isStale: stale,
                               hiddenReviews: hidden),
                   now: t0.addingTimeInterval(600))
    }

    // MARK: Zonen

    func testWithoutAgentsThePRTableTakesTheWholeRest() {
        let l = BoardWindowLayout(state: state(), size: strip)
        XCTAssertNil(l.agentsRect)
        XCTAssertEqual(l.statusRect, CGRect(x: 0, y: 0, width: 125, height: 110))
        XCTAssertEqual(l.prsRect, CGRect(x: 125, y: 0, width: 355, height: 110))
    }

    func testWithAgentsTheRestIsSplitBetweenAgentsAndPRs() {
        let l = BoardWindowLayout(state: state(agents: [agent("a")]), size: strip)
        XCTAssertEqual(l.agentsRect, CGRect(x: 125, y: 0, width: 160, height: 110))
        XCTAssertEqual(l.prsRect, CGRect(x: 285, y: 0, width: 195, height: 110))
    }

    func testZonesTileTheWindowWidthForNarrowAndWideWindows() {
        for width: CGFloat in [400, 480, 640, 900, 1600] {
            for agents in [[], [agent("a")]] {
                let size = CGSize(width: width, height: 120)
                let l = BoardWindowLayout(state: state(agents: agents), size: size)
                var edges = [l.statusRect]
                if let a = l.agentsRect { edges.append(a) }
                edges.append(l.prsRect)
                XCTAssertEqual(edges.first?.minX, 0)
                XCTAssertEqual(edges.last?.maxX, width, "Breite \(width)")
                for (left, right) in zip(edges, edges.dropFirst()) {
                    XCTAssertEqual(left.maxX, right.minX, "lückenlos, ohne Überlappung (Breite \(width))")
                }
                XCTAssertTrue(edges.allSatisfy { $0.height == 120 && $0.width > 0 })
            }
        }
    }

    func testStatusZoneWidthFollowsWindowWidthWithinBounds() {
        XCTAssertEqual(BoardWindowLayout.statusWidth(forWindowWidth: 400), 120)
        XCTAssertEqual(BoardWindowLayout.statusWidth(forWindowWidth: 480), 125)
        XCTAssertEqual(BoardWindowLayout.statusWidth(forWindowWidth: 700), 182)
        XCTAssertEqual(BoardWindowLayout.statusWidth(forWindowWidth: 1920), 220)
    }

    func testPRColumnsStayInsideThePRZone() {
        for agents in [[], [agent("a")]] {
            let l = BoardWindowLayout(state: state(agents: agents), size: BoardWindowLayout.minimumSize)
            XCTAssertLessThanOrEqual(l.prMineRight, l.prsRect.maxX)
            XCTAssertLessThan(l.prReviewRight, l.prMineRight)
            XCTAssertGreaterThan(l.prRepoX, l.prsRect.minX)
            XCTAssertGreaterThan(l.prRepoMaxX - l.prRepoX, 40, "Platz für einen gekürzten Repo-Namen")
        }
    }

    // MARK: Zeilen aus der Höhe

    func testRowCountFollowsWindowHeight() {
        XCTAssertEqual(BoardWindowLayout(state: state(), size: CGSize(width: 480, height: 90)).maxRows, 3)
        XCTAssertEqual(BoardWindowLayout(state: state(), size: BoardWindowLayout.minimumSize).maxRows, 4,
                       "Mindestgröße: Platz für Zeile, „+N weitere“ und Hinweiszeile")
        XCTAssertEqual(BoardWindowLayout(state: state(), size: strip).maxRows, 5)
        XCTAssertEqual(BoardWindowLayout(state: state(), size: CGSize(width: 480, height: 200)).maxRows, 10)
        XCTAssertEqual(BoardWindowLayout(state: state(), size: CGSize(width: 480, height: 20)).maxRows, 0)
    }

    func testLastRowBaselineFitsInsideTheWindow() {
        for height in stride(from: CGFloat(90), through: 400, by: 7) {
            let l = BoardWindowLayout(state: state(), size: CGSize(width: 480, height: height))
            XCTAssertLessThanOrEqual(BoardWindowLayout.rowBaseline(l.maxRows - 1), height - 5, "Höhe \(height)")
            XCTAssertGreaterThan(BoardWindowLayout.rowBaseline(l.maxRows), height - 5, "keine Zeile verschenkt")
        }
    }

    func testOverflowingPRRowsShowMoreLineWithinRowBudget() {
        let rows = (1...8).map { row("repo\($0)") }
        let l = BoardWindowLayout(state: state(rows: rows), size: strip)
        XCTAssertEqual(l.prRows.count, 4)
        XCTAssertEqual(l.prMore, 4)
        XCTAssertNil(l.prHiddenHint)

        let tall = BoardWindowLayout(state: state(rows: rows), size: CGSize(width: 480, height: 200))
        XCTAssertEqual(tall.prRows.count, 8, "hohes Fenster zeigt alle Zeilen")
        XCTAssertEqual(tall.prMore, 0)
    }

    func testHiddenHintKeepsItsOwnLastRow() {
        let rows = (1...8).map { row("repo\($0)") }
        let l = BoardWindowLayout(state: state(rows: rows, hidden: [hiddenReview(1), hiddenReview(2)]), size: strip)
        XCTAssertEqual(l.prRows.count, 3)
        XCTAssertEqual(l.prMore, 5)
        XCTAssertEqual(l.prHiddenHint, "Ausgeblendet · 2 zu reviewen")
        XCTAssertEqual(l.prRows.count + 1 + 1, l.maxRows, "Zeilen + „+N weitere“ + Hinweis = Zeilenbudget")
    }

    func testOverflowingAgentsShowMoreLine() {
        let agents = (1...7).map { agent("agent\($0)") }
        let l = BoardWindowLayout(state: state(agents: agents), size: strip)
        XCTAssertEqual(l.agentRows.count, 4)
        XCTAssertEqual(l.agentMore, 3)
        let few = BoardWindowLayout(state: state(agents: Array(agents.prefix(3))), size: strip)
        XCTAssertEqual(few.agentRows.count, 3)
        XCTAssertEqual(few.agentMore, 0)
    }

    // MARK: Schrift und Statuszone

    func testFontSizesAreFixedPointsIndependentOfWindowSize() {
        let small = BoardWindowLayout(state: state(), size: BoardWindowLayout.minimumSize)
        let large = BoardWindowLayout(state: state(), size: CGSize(width: 1800, height: 440))
        XCTAssertEqual(small.statusFontSize, 16)
        XCTAssertEqual(large.statusFontSize, 16)
        XCTAssertEqual(BoardWindowLayout.FontSize.row, 12)
        XCTAssertEqual(BoardWindowLayout.rowHeight, 17)
    }

    func testLongStatusWordShrinksButNotBelowMinimum() {
        let medium = BoardWindowLayout(state: state(name: "Besprechung"), size: strip)
        XCTAssertLessThan(medium.statusFontSize, 16)
        XCTAssertGreaterThanOrEqual(medium.statusFontSize, 11)
        let huge = BoardWindowLayout(state: state(name: "Donaudampfschifffahrtsgesellschaft"), size: strip)
        XCTAssertEqual(huge.statusFontSize, 11)
    }

    func testStatusNameUsesAtMostTwoLinesAndNeverOverlapsTheClock() {
        let l = BoardWindowLayout(state: state(name: "Sehr lange Besprechung heute"), size: BoardWindowLayout.minimumSize)
        XCTAssertEqual(l.statusWords, ["SEHR", "LANGE"])
        XCTAssertEqual(l.statusBaselines.count, 2)
        // Unterlänge des Namens (≈ 0,25 × Größe) endet über der Oberkante der Uhrziffern (≈ 0,75 × 16 pt).
        let nameBottom = l.statusBaselines.last! + 0.25 * l.statusFontSize
        let clockTop = l.clockBaseline - 0.75 * BoardWindowLayout.FontSize.clock
        XCTAssertLessThan(nameBottom, clockTop)
        XCTAssertLessThan(l.clockBaseline, l.sinceBaseline)
        XCTAssertLessThanOrEqual(l.sinceBaseline, BoardWindowLayout.minimumSize.height - 5)
    }

    // MARK: Zeichnen

    func testRenderUsesPointsTimesScale() {
        let img = BoardWindowRenderer.render(state(), size: strip, scale: 2)
        XCTAssertEqual(img.width, 960)
        XCTAssertEqual(img.height, 220)
        XCTAssertTrue(isRed(pixel(img, 5, 5)), "Statuszone in Statusfarbe")
        XCTAssertTrue(isRed(pixel(img, 2 * 125 - 2, 200)), "Statuszone bis zu ihrem rechten Rand")
        XCTAssertFalse(isRed(pixel(img, 2 * 125 + 40, 200)))
    }

    func testSeparatorOnlyWhenAgentZoneIsShown() {
        let with = BoardWindowRenderer.render(state(agents: [agent("a")]), size: strip, scale: 2)
        XCTAssertTrue(isSeparator(pixel(with, 2 * 285 - 1, 150)), "Trennlinie am rechten Rand der Agenten-Zone")
        let without = BoardWindowRenderer.render(state(), size: strip, scale: 2)
        XCTAssertFalse(isSeparator(pixel(without, 2 * 285 - 1, 150)))
    }

    func testRedBorderAroundPRZoneOnlyWhenFreshCIFails() {
        let failing = state(rows: [row("a", ciFailing: true)], ciFailing: 1)
        XCTAssertTrue(isRed(pixel(BoardWindowRenderer.render(failing, size: strip), 2 * (125 + 2), 150)))
        let fine = state(rows: [row("a")])
        XCTAssertFalse(isRed(pixel(BoardWindowRenderer.render(fine, size: strip), 2 * (125 + 2), 150)))
        let stale = state(rows: [row("a", ciFailing: true)], ciFailing: 1, stale: true)
        XCTAssertFalse(isRed(pixel(BoardWindowRenderer.render(stale, size: strip), 2 * (125 + 2), 150)),
                       "veraltet: kein Alarm")
    }

    func testWaitingAgentGetsHighlightBand() {
        let img = BoardWindowRenderer.render(state(agents: [agent("a", state: .waiting)]), size: strip)
        // Rechts in der ersten Agentenzeile, wo kein Text steht (Label ist kurz: „wartet …“ endet am Rand,
        // deshalb in der Mitte der Zone messen).
        let p = pixel(img, 2 * (125 + 70), 2 * 30)
        XCTAssertGreaterThan(Int(p.r), Int(p.b) + 20, "gelblicher Hintergrund in der Zeile")
    }

    func testTextIsDrawnInTheTargetStrip() {
        // Ohne Agenten: Repo-Name der ersten Zeile erscheint weiß im PR-Bereich, nicht nur Hintergrund.
        let img = BoardWindowRenderer.render(state(rows: [row("telefon")]), size: strip, scale: 2)
        let y0 = Int(2 * (BoardWindowLayout.rowBaseline(0) - 9))
        let y1 = Int(2 * BoardWindowLayout.rowBaseline(0))
        var sawWhite = false
        for y in y0...y1 {
            for x in stride(from: 2 * 145, to: 2 * 220, by: 1) where isWhitish(pixel(img, x, y)) {
                sawWhite = true
            }
        }
        XCTAssertTrue(sawWhite)
    }
}
