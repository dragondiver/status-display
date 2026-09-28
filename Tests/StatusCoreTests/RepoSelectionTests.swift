import XCTest
@testable import StatusCore

final class RepoSelectionTests: XCTestCase {
    func testStateReadsFromPinnedOrHidden() {
        let pinned = ["github.com/a/b"]
        let hidden = ["github.com/a/c"]
        XCTAssertEqual(RepoSelection.state(for: "github.com/a/b", pinned: pinned, hidden: hidden), .pinned)
        XCTAssertEqual(RepoSelection.state(for: "github.com/a/c", pinned: pinned, hidden: hidden), .hidden)
        XCTAssertEqual(RepoSelection.state(for: "github.com/a/d", pinned: pinned, hidden: hidden), .normal)
    }

    /// Ein Repo ist nie gleichzeitig in `pinnedRepos` und `hiddenRepos`: ein Wechsel entfernt es
    /// zuerst aus beiden Listen, bevor er es ggf. wieder in eine einträgt.
    func testSetStateKeepsListsExclusive() {
        let key = "github.com/a/b"
        var pinned: [String] = []
        var hidden: [String] = []

        (pinned, hidden) = RepoSelection.setState(.pinned, for: key, pinned: pinned, hidden: hidden)
        XCTAssertEqual(pinned, [key])
        XCTAssertEqual(hidden, [])

        (pinned, hidden) = RepoSelection.setState(.hidden, for: key, pinned: pinned, hidden: hidden)
        XCTAssertEqual(pinned, [])
        XCTAssertEqual(hidden, [key])

        (pinned, hidden) = RepoSelection.setState(.normal, for: key, pinned: pinned, hidden: hidden)
        XCTAssertEqual(pinned, [])
        XCTAssertEqual(hidden, [])
    }

    func testSetStateLeavesOtherRepoKeysUntouched() {
        let (pinned, hidden) = RepoSelection.setState(.pinned, for: "github.com/a/b",
                                                       pinned: ["github.com/x/y"], hidden: ["github.com/z/w"])
        XCTAssertEqual(pinned, ["github.com/x/y", "github.com/a/b"])
        XCTAssertEqual(hidden, ["github.com/z/w"])
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
}
