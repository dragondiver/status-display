import XCTest
@testable import StatusCore

final class AppSettingsTests: XCTestCase {
    func testDefaultsAndRoundTrip() {
        let d = UserDefaults(suiteName: "AppSettingsTests-\(UUID().uuidString)")!
        XCTAssertEqual(AppSettings.load(from: d), AppSettings())
        var s = AppSettings()
        s.hosts = ["ghe.firma.de"]
        s.brightness = 30
        s.save(to: d)
        XCTAssertEqual(AppSettings.load(from: d), s)
    }
}
