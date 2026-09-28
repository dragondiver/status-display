import CoreGraphics
import XCTest
@testable import StatusCore

final class BoardWindowStatusZoneTests: XCTestCase {
    /// Fenster exakt im Bild-Seitenverhältnis (1920×462), also ohne Rand-„Balken“: hier ist die
    /// Skalierung 1:1 zu den Bild-Koordinaten, einfachster Fall.
    func testUnscaledWindowMatchesImageCoordinatesDirectly() {
        XCTAssertTrue(zone(x: 0, y: 0, viewWidth: 1920, viewHeight: 462))
        XCTAssertTrue(zone(x: 479, y: 461, viewWidth: 1920, viewHeight: 462))
        XCTAssertTrue(zone(x: 480, y: 231, viewWidth: 1920, viewHeight: 462)) // rechter Rand der Zone, inklusiv
        XCTAssertFalse(zone(x: 481, y: 231, viewWidth: 1920, viewHeight: 462))
        XCTAssertFalse(zone(x: 1919, y: 461, viewWidth: 1920, viewHeight: 462))
    }

    // MARK: Skaliertes Fenster (halbe Größe, gleiches Seitenverhältnis)

    func testHalfScaledWindowScalesTheZoneBoundaryToo() {
        // 960×231 = halbe Bildgröße; Zonenrand liegt dann bei 240, nicht mehr bei 480.
        XCTAssertTrue(zone(x: 0, y: 0, viewWidth: 960, viewHeight: 231))
        XCTAssertTrue(zone(x: 240, y: 115, viewWidth: 960, viewHeight: 231))
        XCTAssertFalse(zone(x: 241, y: 115, viewWidth: 960, viewHeight: 231))
        // Rechts im Bild, aber außerhalb der (mit-skalierten) Statuszone.
        XCTAssertFalse(zone(x: 959, y: 230, viewWidth: 960, viewHeight: 231))
    }

    // MARK: Breiteres Fenster als das Bild → Rand-Balken links/rechts

    func testWiderWindowLettersboxesLeftAndRightOfTheImage() {
        // viewWidth 2000 bei unveränderter Höhe 462 → scale bleibt 1 (höhenbegrenzt), Bild ist
        // mittig mit 40 px Rand links und rechts.
        XCTAssertFalse(zone(x: 0, y: 231, viewWidth: 2000, viewHeight: 462)) // linker Rand-Balken
        XCTAssertFalse(zone(x: 39, y: 231, viewWidth: 2000, viewHeight: 462))
        XCTAssertTrue(zone(x: 40, y: 231, viewWidth: 2000, viewHeight: 462)) // Bild beginnt hier
        XCTAssertTrue(zone(x: 520, y: 231, viewWidth: 2000, viewHeight: 462)) // 40 + 480
        XCTAssertFalse(zone(x: 521, y: 231, viewWidth: 2000, viewHeight: 462))
        XCTAssertFalse(zone(x: 1999, y: 231, viewWidth: 2000, viewHeight: 462)) // rechter Rand-Balken
    }

    // MARK: Höheres Fenster als das Bild → Rand-Balken oben/unten

    func testTallerWindowLettersboxesAboveAndBelowTheImage() {
        // viewWidth 960 (halbe Bildbreite), viewHeight 400 statt der passenden 231 → scale bleibt
        // breitenbegrenzt bei 0.5, das Bild sitzt mittig mit 84.5 px Rand oben und unten.
        XCTAssertFalse(zone(x: 100, y: 0, viewWidth: 960, viewHeight: 400)) // oberer Rand-Balken
        XCTAssertFalse(zone(x: 100, y: 84, viewWidth: 960, viewHeight: 400))
        XCTAssertTrue(zone(x: 100, y: 85, viewWidth: 960, viewHeight: 400)) // Bild beginnt hier
        XCTAssertTrue(zone(x: 100, y: 315, viewWidth: 960, viewHeight: 400)) // 84.5 + 231 - 0.5
        XCTAssertFalse(zone(x: 100, y: 400, viewWidth: 960, viewHeight: 400)) // unterer Rand-Balken
    }

    // MARK: Randfälle

    func testZeroOrNegativeViewSizeIsNeverAHit() {
        XCTAssertFalse(zone(x: 0, y: 0, viewWidth: 0, viewHeight: 462))
        XCTAssertFalse(zone(x: 0, y: 0, viewWidth: 1920, viewHeight: 0))
        XCTAssertFalse(zone(x: 0, y: 0, viewWidth: -100, viewHeight: 462))
    }

    func testClickOutsideStatusZoneButStillOnImageIsNoHit() {
        XCTAssertFalse(zone(x: 1000, y: 231, viewWidth: 1920, viewHeight: 462))
    }

    private func zone(x: CGFloat, y: CGFloat, viewWidth: CGFloat, viewHeight: CGFloat) -> Bool {
        BoardWindowStatusZone.isStatusZone(clickPoint: CGPoint(x: x, y: y),
                                           viewSize: CGSize(width: viewWidth, height: viewHeight))
    }
}
