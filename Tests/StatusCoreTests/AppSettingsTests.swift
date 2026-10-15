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
    /// `hostDefaults` bleibt dabei leer: für den einzigen Host `github.com` liefert
    /// `RepoSelection.hostDefault` ohnehin „normal“, ein Eintrag wäre nur unnötiger Ballast.
    func testEmptyJSONDecodesToAllDefaults() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded, AppSettings())
        XCTAssertEqual(decoded.hostDefaults, [:])
    }

    // MARK: Host-Standard (Issue #19)

    func testShownAndHostDefaultsRoundTrip() {
        let d = UserDefaults(suiteName: "AppSettingsTests-\(UUID().uuidString)")!
        var s = AppSettings()
        s.hosts = ["github.com", "ghe.firma.de"]
        s.shownRepos = ["ghe.firma.de/florianhuber/rundfunk"]
        s.hostDefaults = ["ghe.firma.de": .hidden]
        s.save(to: d)
        XCTAssertEqual(AppSettings.load(from: d), s)
    }

    /// Vor Issue #19 gespeicherte Einstellungen kennen weder `shownRepos` noch `hostDefaults`:
    /// github.com dekodiert weiterhin normal, jeder andere schon eingetragene Host wird beim
    /// Laden rückwirkend als ausgeblendet markiert (Entscheidung Florian, 28.09.2026).
    func testMissingHostDefaultsMigratesExistingNonGitHubHostsToHidden() throws {
        let json = """
        {"hosts":["github.com","ghe.firma.de","git.other.org"],"brightness":60,"port":47615,"ghPath":""}
        """
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.shownRepos, [])
        XCTAssertEqual(decoded.hostDefaults, ["ghe.firma.de": .hidden, "git.other.org": .hidden])
        XCTAssertEqual(RepoSelection.hostDefault(for: "github.com", hostDefaults: decoded.hostDefaults), .normal)
        XCTAssertEqual(RepoSelection.hostDefault(for: "ghe.firma.de", hostDefaults: decoded.hostDefaults), .hidden)
    }

    /// Migration alter Einstellungen mit nur `github.com`: kein Eintrag nötig, github.com bleibt
    /// über den Fallback normal.
    func testMissingHostDefaultsWithOnlyGitHubComStaysEmpty() throws {
        let json = """
        {"hosts":["github.com"],"brightness":60,"port":47615,"ghPath":""}
        """
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.hostDefaults, [:])
    }

    /// Ein neu hinzugefügter Host bekommt sofort den Standard „ausgeblendet“, github.com „normal“.
    func testAddHostSetsDefaultHiddenForNonGitHubHost() {
        var s = AppSettings()
        s.addHost("ghe.firma.de")
        XCTAssertEqual(s.hosts, ["github.com", "ghe.firma.de"])
        XCTAssertEqual(RepoSelection.hostDefault(for: "ghe.firma.de", hostDefaults: s.hostDefaults), .hidden)
        XCTAssertEqual(RepoSelection.hostDefault(for: "github.com", hostDefaults: s.hostDefaults), .normal)
    }

    func testAddHostIsNoOpForAlreadyConfiguredHost() {
        var s = AppSettings()
        s.addHost("github.com")
        XCTAssertEqual(s.hosts, ["github.com"], "github.com ist schon Standard-Host, kein doppelter Eintrag")
    }

    // MARK: Host-Standard umschalten (Issue #19 Nachbesserung)

    /// github.com ist ohne Eintrag normal (Fallback); Umschalten auf ausgeblendet legt den ersten
    /// expliziten Eintrag an und wirkt sich sofort auf die Zustandsauflösung aus.
    func testSetHostDefaultTogglesGitHubComFromFallbackNormalToExplicitHidden() {
        var s = AppSettings()
        XCTAssertEqual(RepoSelection.hostDefault(for: "github.com", hostDefaults: s.hostDefaults), .normal)
        s.setHostDefault(.hidden, for: "github.com")
        XCTAssertEqual(s.hostDefaults["github.com"], .hidden)
        XCTAssertEqual(RepoSelection.hostDefault(for: "github.com", hostDefaults: s.hostDefaults), .hidden)
        XCTAssertEqual(RepoSelection.state(for: "github.com/a/b", host: "github.com", pinned: [], hidden: [],
                                           shown: [], hostDefaults: s.hostDefaults), .hidden)
    }

    /// Umschalten von ausgeblendet auf normal wirkt sich auf die Zustandsauflösung aus und räumt
    /// `shownRepos` für diesen Host auf: die Einträge waren nur unter „ausgeblendet“ nötig, um
    /// einzelne Repos freizuschalten, und sollen nicht unbemerkt liegen bleiben, um bei einem
    /// späteren Zurückschalten wieder genau diese Repos freizuschalten.
    func testSetHostDefaultToNormalRemovesShownEntriesForThatHostOnly() {
        var s = AppSettings()
        s.addHost("ghe.firma.de")
        s.shownRepos = ["ghe.firma.de/a/b", "ghe.firma.de/c/d", "github.com/x/y"]
        s.setHostDefault(.normal, for: "ghe.firma.de")
        XCTAssertEqual(s.hostDefaults["ghe.firma.de"], .normal)
        XCTAssertEqual(s.shownRepos, ["github.com/x/y"], "nur die shown-Einträge des umgeschalteten Hosts verschwinden")
        XCTAssertEqual(RepoSelection.state(for: "ghe.firma.de/a/b", host: "ghe.firma.de", pinned: [], hidden: [],
                                           shown: s.shownRepos, hostDefaults: s.hostDefaults), .normal,
                       "a/b ist jetzt normal, weil der Host-Standard normal ist – nicht mehr wegen shownRepos")
    }

    /// Umschalten auf ausgeblendet fasst `shownRepos` nicht an (sie werden dort erst durch
    /// `RepoSelection.setState` gepflegt).
    func testSetHostDefaultToHiddenLeavesShownReposUntouched() {
        var s = AppSettings()
        s.shownRepos = ["ghe.firma.de/a/b"]
        s.setHostDefault(.hidden, for: "ghe.firma.de")
        XCTAssertEqual(s.shownRepos, ["ghe.firma.de/a/b"])
        XCTAssertEqual(RepoSelection.state(for: "ghe.firma.de/a/b", host: "ghe.firma.de", pinned: [], hidden: [],
                                           shown: s.shownRepos, hostDefaults: s.hostDefaults), .normal,
                       "explizit shown sticht weiterhin den ausgeblendeten Host-Standard")
    }

    // MARK: Board-Fenster (Issue #23)

    func testBoardWindowDefaults() {
        XCTAssertEqual(AppSettings().boardWindowMode, .automatic)
        XCTAssertEqual(AppSettings().boardWindowAlwaysOnTop, false)
    }

    func testBoardWindowSettingsRoundTrip() {
        let d = UserDefaults(suiteName: "AppSettingsTests-\(UUID().uuidString)")!
        var s = AppSettings()
        s.boardWindowMode = .always
        s.boardWindowAlwaysOnTop = true
        s.save(to: d)
        XCTAssertEqual(AppSettings.load(from: d), s)
    }

    /// Vor Issue #23 gespeicherte Einstellungen kennen `boardWindowMode`/`boardWindowAlwaysOnTop`
    /// noch nicht: das Dekodieren darf nicht scheitern, fehlende Schlüssel fallen auf die Defaults
    /// zurück (automatisch, nicht immer im Vordergrund).
    func testMissingBoardWindowKeysDecodeToDefaults() throws {
        let json = """
        {"hosts":["github.com"],"brightness":60,"port":47615,"ghPath":""}
        """
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.boardWindowMode, .automatic)
        XCTAssertEqual(decoded.boardWindowAlwaysOnTop, false)
    }

    // MARK: Jira-Felder (multi-server)

    func testJiraServersDefaultToEmpty() {
        XCTAssertEqual(AppSettings().jiraServers, [])
        XCTAssertFalse(AppSettings().jiraConfigured)
    }

    func testJiraConfiguredWhenServerPresent() {
        var s = AppSettings()
        s.jiraServers = [JiraServer(domain: "x.atlassian.net", email: "a@b.com", token: "tok")]
        XCTAssertTrue(s.jiraConfigured)
    }

    func testJiraServersRoundTrip() {
        let d = UserDefaults(suiteName: "AppSettingsTests-Jira-\(UUID().uuidString)")!
        var s = AppSettings()
        s.jiraServers = [
            JiraServer(domain: "a.atlassian.net", email: "a@firma.de", token: "tok1"),
            JiraServer(domain: "b.atlassian.net", email: "b@firma.de", token: "tok2"),
        ]
        s.save(to: d)
        XCTAssertEqual(AppSettings.load(from: d).jiraServers, s.jiraServers)
    }

    func testJiraServersDecodeFromOldSettingsWithoutJira() throws {
        let json = """
        {"hosts":["github.com"],"brightness":60,"port":47615,"ghPath":""}
        """
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.jiraServers, [])
        XCTAssertFalse(decoded.jiraConfigured)
    }
}
