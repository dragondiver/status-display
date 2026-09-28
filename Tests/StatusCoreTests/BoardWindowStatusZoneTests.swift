import CoreGraphics
import XCTest
@testable import StatusCore

/// Seit status-display#38 zeichnet das Board-Fenster ein eigenes Layout in Fenstergröße; die
/// Statuszone ist der linke Streifen in voller Höhe (`BoardWindowLayout.statusWidth`), ohne
/// Rand-„Balken“ wie beim früher eingepassten 1920×462-Bild.
final class BoardWindowStatusZoneTests: XCTestCase {
    /// Zielgröße aus dem Issue: 480×110 pt → Statuszone 125 pt breit (26 % von 480, gerundet).
    func testTargetStripHasStatusZoneOf125Points() {
        XCTAssertEqual(BoardWindowStatusZone.rect(viewSize: CGSize(width: 480, height: 110)),
                       CGRect(x: 0, y: 0, width: 125, height: 110))
        XCTAssertTrue(zone(x: 0, y: 0, viewWidth: 480, viewHeight: 110))
        XCTAssertTrue(zone(x: 124, y: 109, viewWidth: 480, viewHeight: 110))
        XCTAssertTrue(zone(x: 125, y: 55, viewWidth: 480, viewHeight: 110)) // rechter Rand der Zone, inklusiv
        XCTAssertFalse(zone(x: 126, y: 55, viewWidth: 480, viewHeight: 110))
        XCTAssertFalse(zone(x: 479, y: 109, viewWidth: 480, viewHeight: 110))
    }

    // MARK: Schmales Fenster → Mindestbreite der Statuszone

    func testNarrowWindowKeepsMinimumStatusWidth() {
        // 400 pt (Mindestbreite): 26 % wären 104 pt – die Zone bleibt 120 pt breit, damit Uhr und
        // „seit 12:59 h“ passen.
        XCTAssertTrue(zone(x: 120, y: 50, viewWidth: 400, viewHeight: 100))
        XCTAssertFalse(zone(x: 121, y: 50, viewWidth: 400, viewHeight: 100))
    }

    // MARK: Breites Fenster → Statuszone wächst mit, bis zur Obergrenze

    func testWiderWindowGrowsStatusZoneUpToCap() {
        // Kein Rand-Balken mehr: Treffer beginnen direkt bei x = 0.
        XCTAssertTrue(zone(x: 0, y: 55, viewWidth: 700, viewHeight: 110))
        XCTAssertTrue(zone(x: 182, y: 55, viewWidth: 700, viewHeight: 110)) // 26 % von 700
        XCTAssertFalse(zone(x: 183, y: 55, viewWidth: 700, viewHeight: 110))
        // Sehr breit: höchstens 220 pt.
        XCTAssertTrue(zone(x: 220, y: 55, viewWidth: 2000, viewHeight: 462))
        XCTAssertFalse(zone(x: 221, y: 55, viewWidth: 2000, viewHeight: 462))
    }

    // MARK: Hohes Fenster → Zone in voller Höhe

    func testTallerWindowHitsOverFullHeight() {
        XCTAssertTrue(zone(x: 50, y: 0, viewWidth: 480, viewHeight: 400))
        XCTAssertTrue(zone(x: 50, y: 400, viewWidth: 480, viewHeight: 400))
        XCTAssertFalse(zone(x: 50, y: 401, viewWidth: 480, viewHeight: 400)) // unterhalb der Ansicht
        XCTAssertFalse(zone(x: -1, y: 50, viewWidth: 480, viewHeight: 400)) // links außerhalb
    }

    // MARK: Randfälle

    func testZeroOrNegativeViewSizeIsNeverAHit() {
        XCTAssertFalse(zone(x: 0, y: 0, viewWidth: 0, viewHeight: 462))
        XCTAssertFalse(zone(x: 0, y: 0, viewWidth: 1920, viewHeight: 0))
        XCTAssertFalse(zone(x: 0, y: 0, viewWidth: -100, viewHeight: 462))
    }

    func testClickOutsideStatusZoneButInsideWindowIsNoHit() {
        XCTAssertFalse(zone(x: 300, y: 55, viewWidth: 480, viewHeight: 110))
    }

    /// Die Trefferprüfung trifft genau das Rechteck, das das Layout als Statuszone zeichnet – mit und
    /// ohne Agenten (die Agenten-Zone verschiebt nur, was rechts der Statuszone liegt).
    func testHitRectMatchesTheDrawnStatusRect() {
        let t0 = Date(timeIntervalSince1970: 1_790_000_000)
        let agent = AgentActivity(id: "a", source: "x", name: "a", state: .running, since: t0, lastSeen: t0)
        for size in [CGSize(width: 400, height: 100), CGSize(width: 480, height: 110), CGSize(width: 1200, height: 300)] {
            for agents in [[], [agent]] {
                let state = BoardState(statusName: "Frei", statusColor: RGBColor(hex: "#00FF00")!, statusSince: t0,
                                       agents: agents, prs: .unknown, now: t0)
                XCTAssertEqual(BoardWindowLayout(state: state, size: size).statusRect,
                               BoardWindowStatusZone.rect(viewSize: size), "\(size), Agenten: \(agents.count)")
            }
        }
    }

    private func zone(x: CGFloat, y: CGFloat, viewWidth: CGFloat, viewHeight: CGFloat) -> Bool {
        BoardWindowStatusZone.isStatusZone(clickPoint: CGPoint(x: x, y: y),
                                           viewSize: CGSize(width: viewWidth, height: viewHeight))
    }
}
