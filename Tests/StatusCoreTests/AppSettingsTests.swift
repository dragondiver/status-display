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

    func testNormalizedHost() {
        XCTAssertEqual(AppSettings.normalizedHost("ghe.firma.de"), "ghe.firma.de")
        XCTAssertEqual(AppSettings.normalizedHost(" https://GHE.firma.de/ "), "ghe.firma.de")
        XCTAssertNil(AppSettings.normalizedHost("ghe firma.de"))
        XCTAssertNil(AppSettings.normalizedHost(""))
    }

    func testPinnedAndHiddenRoundTrip() {
        let d = UserDefaults(suiteName: "AppSettingsTests-\(UUID().uuidString)")!
        var s = AppSettings()
        s.pinnedRepos = ["github.com/florianhuber/rundfunk"]
        s.hiddenRepos = ["github.com/florianhuber/dotfiles"]
        s.save(to: d)
        XCTAssertEqual(AppSettings.load(from: d), s)
    }

    /// Vor Issue #14 gespeicherte Einstellungen kennen `pinnedRepos`/`hiddenRepos` noch nicht:
    /// das Dekodieren darf nicht scheitern, fehlende Schlüssel werden zu leeren Listen.
    func testMissingPinnedAndHiddenKeysDecodeToEmptyDefaults() throws {
        let json = """
        {"hosts":["github.com"],"brightness":60,"port":47615,"ghPath":""}
        """
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.pinnedRepos, [])
        XCTAssertEqual(decoded.hiddenRepos, [])
        XCTAssertEqual(decoded.hosts, ["github.com"])
    }

    /// Ein leeres JSON-Objekt (Extremfall) fällt auf `AppSettings()` in allen Feldern zurück.
    func testEmptyJSONDecodesToAllDefaults() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded, AppSettings())
    }
}
