import XCTest
@testable import StatusCore

final class TimeSourceTests: XCTestCase {
    func testManualTimeAdvances() {
        let t = ManualTime(Date(timeIntervalSince1970: 100))
        t.advance(60)
        XCTAssertEqual(t.now, Date(timeIntervalSince1970: 160))
    }
}
