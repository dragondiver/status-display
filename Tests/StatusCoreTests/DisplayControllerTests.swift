import XCTest
@testable import StatusCore

final class DisplayControllerTests: XCTestCase {
    func testAttachSendsScreenOnAndBrightness() {
        let c = DisplayController(brightness: 42)
        let w = FakeWriter()
        c.attach(w); c.flush()
        XCTAssertEqual(w.reports, [AKP02Protocol.screenOn(), AKP02Protocol.brightness(42)])
    }

    func testShowSendsFullFrame() {
        let c = DisplayController()
        let w = FakeWriter()
        c.attach(w); c.flush()
        w.reports.removeAll()
        c.show(jpeg: [1, 2, 3]); c.flush()
        XCTAssertEqual(w.reports, AKP02Protocol.fullFrameReports(jpeg: [1, 2, 3]))
    }

    func testReattachRestoresBrightnessAndLastFrame() {
        let c = DisplayController(brightness: 60)
        c.show(jpeg: [9, 9]) // noch kein Gerät: wird gemerkt
        c.setBrightness(30)
        let w = FakeWriter()
        c.attach(w); c.flush()
        XCTAssertEqual(w.reports, [AKP02Protocol.screenOn(), AKP02Protocol.brightness(30)]
                       + AKP02Protocol.fullFrameReports(jpeg: [9, 9]))
    }

    func testWriteFailureReportsOnceAndReattachRestores() {
        let c = DisplayController()
        let w = FakeWriter()
        w.failWhenCountReaches = 3
        let disconnected = expectation(description: "getrennt")
        let failed = expectation(description: "Schreibfehler gemeldet")
        var failures = 0
        var states: [DisplayController.State] = []
        c.onStateChange = { s in states.append(s); if s == .disconnected { disconnected.fulfill() } }
        c.onWriteFailure = { failures += 1; failed.fulfill() }
        c.attach(w)
        c.setBrightness(35)
        c.show(jpeg: [UInt8](repeating: 7, count: 3000)); c.flush()
        wait(for: [disconnected, failed], timeout: 1)
        let count = w.reports.count
        c.show(jpeg: [1]); c.flush()
        c.beat(); c.flush()
        XCTAssertEqual(w.reports.count, count, "nach Fehler wird nichts mehr geschrieben")
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(failures, 1, "Schreibfehler genau einmal gemeldet")

        let w2 = FakeWriter()
        c.attach(w2); c.flush()
        XCTAssertEqual(Array(w2.reports.prefix(2)), [AKP02Protocol.screenOn(), AKP02Protocol.brightness(35)])
        XCTAssertEqual(Array(w2.reports.dropFirst(2)), AKP02Protocol.fullFrameReports(jpeg: [1]))
    }

    func testReinitializeResendsScreenOnBrightnessAndLastFrame() {
        let c = DisplayController(brightness: 60)
        let w = FakeWriter()
        c.attach(w)
        c.setBrightness(25)
        c.show(jpeg: [4, 5, 6]); c.flush()
        w.reports.removeAll()
        c.reinitialize(); c.flush()
        XCTAssertEqual(w.reports, [AKP02Protocol.screenOn(), AKP02Protocol.brightness(25)]
                       + AKP02Protocol.fullFrameReports(jpeg: [4, 5, 6]))
    }

    func testHeartbeatWritesConnect() {
        let c = DisplayController()
        let w = FakeWriter()
        c.attach(w); c.flush()
        w.reports.removeAll()
        c.beat(); c.flush()
        XCTAssertEqual(w.reports, [AKP02Protocol.heartbeat()])
    }
}
