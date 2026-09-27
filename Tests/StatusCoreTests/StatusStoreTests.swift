import XCTest
@testable import StatusCore

final class StatusStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let time = ManualTime()

    override func setUp() {
        defaults = UserDefaults(suiteName: "StatusStoreTests-\(UUID().uuidString)")!
    }

    private func makeStore() -> StatusStore {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return StatusStore(defaults: defaults, time: time, calendar: cal)
    }

    func testStartsAvailable() {
        XCTAssertEqual(makeStore().effective().preset.id, "available")
    }

    func testSetAndPersist() {
        let s = makeStore()
        s.set("deep-focus")
        XCTAssertEqual(makeStore().effective().preset.id, "deep-focus")
        XCTAssertEqual(makeStore().effective().since, time.now)
    }

    func testDurationExpiresToAvailableAcrossRestart() {
        let s = makeStore()
        s.set("in-meeting", for: 3600)
        time.advance(3599)
        XCTAssertEqual(s.effective().preset.id, "in-meeting")
        time.advance(2)
        let reloaded = makeStore()
        let e = reloaded.effective()
        XCTAssertEqual(e.preset.id, "available")
        XCTAssertEqual(e.since, time.now.addingTimeInterval(-1), "seit dem Ablaufzeitpunkt")
    }

    func testUntilEndOfDay() {
        let s = makeStore()
        s.setUntilEndOfDay("deep-focus")
        let until = s.manual.until!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
        XCTAssertEqual(cal.component(.hour, from: until), 0)
        XCTAssertGreaterThan(until, time.now)
        XCTAssertLessThanOrEqual(until.timeIntervalSince(time.now), 86_400)
    }

    func testAutomaticOverridesAndReleases() {
        let s = makeStore()
        s.set("deep-focus")
        time.advance(10)
        s.setAutomatic("in-meeting", source: "teams")
        XCTAssertEqual(s.effective().preset.id, "in-meeting")
        XCTAssertEqual(s.effective().since, time.now)
        s.setAutomatic(nil, source: "teams")
        XCTAssertEqual(s.effective().preset.id, "deep-focus")
    }

    func testUnknownPresetFallsBack() {
        let s = makeStore()
        s.set("gibt-es-nicht")
        XCTAssertEqual(s.effective().preset.id, "available")
        s.setPresets([StatusPreset(id: "x", name: "X", colorHex: "#000000")])
        XCTAssertEqual(s.effective().preset.id, "x", "ohne 'available' gilt die erste Vorgabe")
    }

    func testEmptyPresetListIsRejected() {
        let s = makeStore()
        s.setPresets([])
        XCTAssertEqual(s.presets, StatusPreset.defaults)
    }
}
