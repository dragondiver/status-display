import XCTest
@testable import StatusCore

final class RepoSelectionTests: XCTestCase {
    private let noDefaults: [String: RepoDefault] = [:]

    func testStateReadsFromPinnedOrHidden() {
        let pinned = ["github.com/a/b"]
        let hidden = ["github.com/a/c"]
        XCTAssertEqual(RepoSelection.state(for: "github.com/a/b", host: "github.com", pinned: pinned, hidden: hidden,
                                           shown: [], hostDefaults: noDefaults), .pinned)
        XCTAssertEqual(RepoSelection.state(for: "github.com/a/c", host: "github.com", pinned: pinned, hidden: hidden,
                                           shown: [], hostDefaults: noDefaults), .hidden)
        XCTAssertEqual(RepoSelection.state(for: "github.com/a/d", host: "github.com", pinned: pinned, hidden: hidden,
                                           shown: [], hostDefaults: noDefaults), .normal)
    }

    /// Ein Repo ist nie gleichzeitig in `pinnedRepos` und `hiddenRepos`/`shownRepos`: ein Wechsel
    /// entfernt es zuerst aus allen dreien, bevor er es ggf. wieder in eine einträgt.
    func testSetStateKeepsListsExclusive() {
        let key = "github.com/a/b"
        var pinned: [String] = []
        var hidden: [String] = []
        var shown: [String] = []

        (pinned, hidden, shown) = RepoSelection.setState(.pinned, for: key, host: "github.com", pinned: pinned,
                                                          hidden: hidden, shown: shown, hostDefaults: noDefaults)
        XCTAssertEqual(pinned, [key])
        XCTAssertEqual(hidden, [])
        XCTAssertEqual(shown, [])

        (pinned, hidden, shown) = RepoSelection.setState(.hidden, for: key, host: "github.com", pinned: pinned,
                                                          hidden: hidden, shown: shown, hostDefaults: noDefaults)
        XCTAssertEqual(pinned, [])
        XCTAssertEqual(hidden, [key])
        XCTAssertEqual(shown, [])

        (pinned, hidden, shown) = RepoSelection.setState(.normal, for: key, host: "github.com", pinned: pinned,
                                                          hidden: hidden, shown: shown, hostDefaults: noDefaults)
        XCTAssertEqual(pinned, [])
        XCTAssertEqual(hidden, [])
        XCTAssertEqual(shown, [], "github.com ist standardmäßig normal: kein Eintrag in shownRepos nötig")
    }

    func testSetStateLeavesOtherRepoKeysUntouched() {
        let (pinned, hidden, shown) = RepoSelection.setState(.pinned, for: "github.com/a/b", host: "github.com",
                                                              pinned: ["github.com/x/y"], hidden: ["github.com/z/w"],
                                                              shown: [], hostDefaults: noDefaults)
        XCTAssertEqual(pinned, ["github.com/x/y", "github.com/a/b"])
        XCTAssertEqual(hidden, ["github.com/z/w"])
        XCTAssertEqual(shown, [])
    }

    func testFilterIsCaseInsensitiveSubstring() {
        let repos = ["Acme/Widgets", "acme/Gadgets", "other/thing"]
        XCTAssertEqual(RepoSelection.filter(repos, query: "acme"), ["Acme/Widgets", "acme/Gadgets"])
        XCTAssertEqual(RepoSelection.filter(repos, query: "WIDGET"), ["Acme/Widgets"])
    }

    func testFilterWithEmptyOrWhitespaceQueryReturnsAll() {
        let repos = ["a/b", "c/d"]
        XCTAssertEqual(RepoSelection.filter(repos, query: ""), repos)
        XCTAssertEqual(RepoSelection.filter(repos, query: "   "), repos)
    }

    func testRepositoryForKeyStripsHostPrefix() {
        XCTAssertEqual(RepoSelection.repository(forKey: "github.com/a/b", host: "github.com"), "a/b")
        XCTAssertNil(RepoSelection.repository(forKey: "ghe.firma.de/a/b", host: "github.com"))
        XCTAssertNil(RepoSelection.repository(forKey: "github.com/", host: "github.com"))
    }

    // MARK: Host-Standard (Issue #19)

    func testHostDefaultIsGitHubComNormalAndOthersHiddenWithoutEntry() {
        XCTAssertEqual(RepoSelection.hostDefault(for: "github.com", hostDefaults: noDefaults), .normal)
        XCTAssertEqual(RepoSelection.hostDefault(for: "ghe.firma.de", hostDefaults: noDefaults), .hidden)
    }

    func testHostDefaultEntryOverridesFallback() {
        XCTAssertEqual(RepoSelection.hostDefault(for: "github.com", hostDefaults: ["github.com": .hidden]), .hidden)
        XCTAssertEqual(RepoSelection.hostDefault(for: "ghe.firma.de", hostDefaults: ["ghe.firma.de": .normal]),
                       .normal)
    }

    /// Ohne expliziten Eintrag gilt der Host-Standard – für beide Standards (normal/ausgeblendet).
    func testStateFallsBackToHostDefaultWhenNoExplicitEntry() {
        XCTAssertEqual(RepoSelection.state(for: "github.com/a/b", host: "github.com", pinned: [], hidden: [],
                                           shown: [], hostDefaults: noDefaults), .normal,
                       "github.com ist ohne Eintrag normal")
        XCTAssertEqual(RepoSelection.state(for: "ghe.firma.de/a/b", host: "ghe.firma.de", pinned: [], hidden: [],
                                           shown: [], hostDefaults: noDefaults), .hidden,
                       "andere Hosts sind ohne Eintrag ausgeblendet")
    }

    /// `shownRepos` ist der einzige Weg, ein Repo unter einem ausgeblendeten Host-Standard auf
    /// normal zu stellen.
    func testShownOverridesHiddenHostDefault() {
        XCTAssertEqual(RepoSelection.state(for: "ghe.firma.de/a/b", host: "ghe.firma.de", pinned: [], hidden: [],
                                           shown: ["ghe.firma.de/a/b"], hostDefaults: noDefaults), .normal)
    }

    func testSetStateUnderHiddenHostDefaultUsesShownList() {
        let (pinned, hidden, shown) = RepoSelection.setState(.normal, for: "ghe.firma.de/a/b", host: "ghe.firma.de",
                                                              pinned: [], hidden: [], shown: [],
                                                              hostDefaults: noDefaults)
        XCTAssertEqual(pinned, [])
        XCTAssertEqual(hidden, [])
        XCTAssertEqual(shown, ["ghe.firma.de/a/b"], "Standard ist ausgeblendet, also braucht normal einen Eintrag")
    }

    func testSetStateUnderHiddenHostDefaultToHiddenNeedsNoEntry() {
        let (pinned, hidden, shown) = RepoSelection.setState(.hidden, for: "ghe.firma.de/a/b", host: "ghe.firma.de",
                                                              pinned: [], hidden: [], shown: [],
                                                              hostDefaults: noDefaults)
        XCTAssertEqual(pinned, [])
        XCTAssertEqual(hidden, [], "ausgeblendet ist hier schon der Standard, kein expliziter Eintrag nötig")
        XCTAssertEqual(shown, [])
    }

    // MARK: Sammelaktion (Issue #19)

    func testSetStateForAllAppliesToEveryName() {
        let (pinned, hidden, shown) = RepoSelection.setStateForAll(.hidden, names: ["a/b", "a/c"], host: "github.com",
                                                                    pinned: [], hidden: [], shown: [],
                                                                    hostDefaults: noDefaults)
        XCTAssertEqual(Set(hidden), ["github.com/a/b", "github.com/a/c"])
        XCTAssertEqual(pinned, [])
        XCTAssertEqual(shown, [])
    }

    func testSetStateForAllOnEmptyNamesChangesNothing() {
        let (pinned, hidden, shown) = RepoSelection.setStateForAll(.pinned, names: [], host: "github.com",
                                                                    pinned: ["github.com/x/y"], hidden: [],
                                                                    shown: [], hostDefaults: noDefaults)
        XCTAssertEqual(pinned, ["github.com/x/y"])
        XCTAssertEqual(hidden, [])
        XCTAssertEqual(shown, [])
    }
}
