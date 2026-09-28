import XCTest
@testable import StatusCore

/// status-display#36: Ohne `materialize()` (also ohne `show`) darf kein Fenster entstehen.
final class DeferredWindowTests: XCTestCase {
    private final class FakeWindow {
        var level = 0
    }

    private final class Factory {
        var created = 0
        func make() -> FakeWindow {
            created += 1
            return FakeWindow()
        }
    }

    func testNothingIsCreatedWithoutMaterialize() {
        let factory = Factory()
        let slot = DeferredWindow(make: factory.make)
        XCTAssertNil(slot.existing)
        var touched = false
        slot.ifExists { _ in touched = true }
        XCTAssertFalse(touched, "ifExists darf auf einem nicht erzeugten Fenster nichts tun")
        XCTAssertNil(slot.existing)
        XCTAssertEqual(factory.created, 0)
    }

    func testMaterializeCreatesExactlyOnce() {
        let factory = Factory()
        let slot = DeferredWindow(make: factory.make)
        let first = slot.materialize()
        let second = slot.materialize()
        XCTAssertTrue(first === second)
        XCTAssertTrue(slot.existing === first)
        XCTAssertEqual(factory.created, 1)
    }

    func testIfExistsActsOnCreatedWindowWithoutCreatingAnother() {
        let factory = Factory()
        let slot = DeferredWindow(make: factory.make)
        let window = slot.materialize()
        slot.ifExists { $0.level = 3 }
        XCTAssertEqual(window.level, 3)
        XCTAssertEqual(factory.created, 1)
    }

    /// Das Muster der Fenster-Controller: ein vor `show` gesetzter Wert wird gemerkt und beim
    /// Erzeugen angewendet, ein danach gesetzter direkt am vorhandenen Fenster.
    func testPendingValueIsAppliedOnCreationAndLaterDirectly() {
        var pendingLevel = 0
        let factory = Factory()
        let slot = DeferredWindow { () -> FakeWindow in
            let w = factory.make()
            w.level = pendingLevel
            return w
        }
        func setLevel(_ level: Int) {
            pendingLevel = level
            slot.ifExists { $0.level = level }
        }

        setLevel(5)
        XCTAssertEqual(factory.created, 0, "Einstellung vor show erzeugt kein Fenster")
        let window = slot.materialize()
        XCTAssertEqual(window.level, 5, "gemerkter Wert wird beim Erzeugen angewendet")
        setLevel(7)
        XCTAssertEqual(window.level, 7)
        XCTAssertEqual(factory.created, 1)
    }
}
