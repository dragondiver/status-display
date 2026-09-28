import XCTest
@testable import StatusCore

final class BoardWindowVisibilityTests: XCTestCase {
    // MARK: .always / .never sind absolut

    func testAlwaysIsAlwaysVisibleRegardlessOfEverythingElse() {
        for displayConnected in [true, false] {
            for inStartupGrace in [true, false] {
                for manuallyOpened in [true, false] {
                    XCTAssertTrue(BoardWindowVisibility.shouldShow(
                        mode: .always, displayConnected: displayConnected, inStartupGrace: inStartupGrace,
                        manuallyOpened: manuallyOpened))
                }
            }
        }
    }

    func testNeverIsNeverVisibleRegardlessOfEverythingElse() {
        for displayConnected in [true, false] {
            for inStartupGrace in [true, false] {
                for manuallyOpened in [true, false] {
                    XCTAssertFalse(BoardWindowVisibility.shouldShow(
                        mode: .never, displayConnected: displayConnected, inStartupGrace: inStartupGrace,
                        manuallyOpened: manuallyOpened))
                }
            }
        }
    }

    // MARK: .automatic – Display-Zustand

    func testAutomaticShowsWhenDisplayDisconnectedAndGraceOver() {
        XCTAssertTrue(BoardWindowVisibility.shouldShow(
            mode: .automatic, displayConnected: false, inStartupGrace: false, manuallyOpened: false))
    }

    func testAutomaticHidesWhenDisplayConnectedAndGraceOver() {
        XCTAssertFalse(BoardWindowVisibility.shouldShow(
            mode: .automatic, displayConnected: true, inStartupGrace: false, manuallyOpened: false))
    }

    // MARK: .automatic – Start-Karenz

    /// Direkt nach dem Start ist der Display-Zustand noch „nicht verbunden“ (IOKit hat sich noch
    /// nicht gemeldet); ohne Karenz würde das Fenster bei Nutzern mit Display kurz aufblitzen.
    func testAutomaticStaysHiddenDuringStartupGraceEvenIfDisplayLooksDisconnected() {
        XCTAssertFalse(BoardWindowVisibility.shouldShow(
            mode: .automatic, displayConnected: false, inStartupGrace: true, manuallyOpened: false))
    }

    func testAutomaticStaysHiddenDuringStartupGraceIfDisplayConnected() {
        XCTAssertFalse(BoardWindowVisibility.shouldShow(
            mode: .automatic, displayConnected: true, inStartupGrace: true, manuallyOpened: false))
    }

    // MARK: .automatic – manuell geöffnet

    /// Ein vom Nutzer über den Menüpunkt geöffnetes Fenster bleibt offen, auch wenn das Display
    /// danach verbindet – „Automatisch“ schließt es nicht selbstständig weg.
    func testAutomaticKeepsManuallyOpenedWindowVisibleEvenWhenDisplayConnects() {
        XCTAssertTrue(BoardWindowVisibility.shouldShow(
            mode: .automatic, displayConnected: true, inStartupGrace: false, manuallyOpened: true))
    }

    /// Manuelles Öffnen sticht sogar die Start-Karenz: ein bewusster Klick auf „Board-Fenster
    /// anzeigen“ soll sofort wirken, nicht erst nach 2 s.
    func testAutomaticShowsManuallyOpenedWindowEvenDuringStartupGrace() {
        XCTAssertTrue(BoardWindowVisibility.shouldShow(
            mode: .automatic, displayConnected: true, inStartupGrace: true, manuallyOpened: true))
    }

    func testAutomaticManuallyOpenedWithDisconnectedDisplayIsVisible() {
        XCTAssertTrue(BoardWindowVisibility.shouldShow(
            mode: .automatic, displayConnected: false, inStartupGrace: false, manuallyOpened: true))
    }
}
