import XCTest
@testable import StatusCore

final class PRAggregatorTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func pr(_ n: Int, repository: String = "a/b", failing: Bool = false, draft: Bool = false) -> PullRequest {
        PullRequest(number: n, title: "t", repository: repository, url: URL(string: "https://x/\(n)")!,
                   ciFailing: failing, isDraft: draft)
    }

    func testEmptyIsUnknownAndStale() {
        XCTAssertEqual(PRAggregator().zone(now: t0, hosts: ["github.com"]), .unknown)
    }

    func testBuildsOneRowPerRepoAndSumsCounts() {
        var a = PRAggregator()
        a.record(PRSnapshot(host: "github.com", toReview: [pr(1, repository: "f/telefon-ai")],
                            mine: [pr(2, repository: "f/telefon-ai", failing: true)], fetchedAt: t0))
        a.record(PRSnapshot(host: "ghe", toReview: [pr(3, repository: "f/rundfunk"), pr(4, repository: "f/rundfunk")],
                            mine: [], fetchedAt: t0.addingTimeInterval(60)))
        let z = a.zone(now: t0.addingTimeInterval(100), hosts: ["github.com", "ghe"])
        XCTAssertEqual(z.ciFailingCount, 1)
        XCTAssertEqual(z.lastSuccess, t0)
        XCTAssertFalse(z.isStale)
        XCTAssertEqual(z.rows, [
            PRRow(repoKey: "ghe/f/rundfunk", repository: "rundfunk", toReview: 2, mine: 0, ciFailing: false),
            PRRow(repoKey: "github.com/f/telefon-ai", repository: "telefon-ai", toReview: 1, mine: 1, ciFailing: true),
        ])
        XCTAssertTrue(a.zone(now: t0.addingTimeInterval(361), hosts: ["github.com", "ghe"]).isStale)
    }

    func testErrorKeepsLastSnapshotAndRecoveryClearsError() {
        var a = PRAggregator()
        a.record(PRSnapshot(host: "ghe", toReview: [], mine: [], fetchedAt: t0))
        a.record(.http(502), host: "ghe")
        XCTAssertEqual(a.errors["ghe"], .http(502))
        XCTAssertNotNil(a.snapshots["ghe"])
        a.record(PRSnapshot(host: "ghe", toReview: [], mine: [], fetchedAt: t0))
        XCTAssertNil(a.errors["ghe"])
    }

    func testRetainDropsRemovedHosts() {
        var a = PRAggregator()
        a.record(PRSnapshot(host: "alt", toReview: [pr(1)], mine: [], fetchedAt: t0))
        a.record(.ghNotFound, host: "alt")
        a.retain(hosts: ["github.com"])
        XCTAssertTrue(a.snapshots.isEmpty)
        XCTAssertTrue(a.errors.isEmpty)
    }

    func testDraftPRWithFailingCIDoesNotCountButNonDraftDoes() {
        var a = PRAggregator()
        a.record(PRSnapshot(host: "github.com",
                            toReview: [],
                            mine: [pr(1, failing: true, draft: true), pr(2, failing: true)],
                            fetchedAt: t0))
        let z = a.zone(now: t0, hosts: ["github.com"])
        XCTAssertEqual(z.ciFailingCount, 1)
        XCTAssertEqual(z.rows, [PRRow(repoKey: "github.com/a/b", repository: "b", toReview: 0, mine: 2, ciFailing: true)])
    }

    func testConfiguredHostWithoutSnapshotMakesZoneStale() {
        var a = PRAggregator()
        a.record(PRSnapshot(host: "github.com", toReview: [pr(1)], mine: [], fetchedAt: t0))
        XCTAssertTrue(a.zone(now: t0.addingTimeInterval(10), hosts: ["github.com", "ghe"]).isStale)
        a.record(PRSnapshot(host: "ghe", toReview: [], mine: [], fetchedAt: t0))
        XCTAssertFalse(a.zone(now: t0.addingTimeInterval(10), hosts: ["github.com", "ghe"]).isStale)
    }

    // MARK: Sichtbarkeit und Sortierung (Issue #14)

    func testPinnedRepoAppearsWithZeroActivity() {
        var a = PRAggregator()
        a.record(PRSnapshot(host: "github.com", toReview: [], mine: [], fetchedAt: t0))
        let z = a.zone(now: t0, hosts: ["github.com"], pinned: ["github.com/f/heim-agent"])
        XCTAssertEqual(z.rows, [PRRow(repoKey: "github.com/f/heim-agent", repository: "heim-agent",
                                      toReview: 0, mine: 0, ciFailing: false)])
    }

    func testOtherRepoOnlyAppearsWithActivity() {
        var a = PRAggregator()
        a.record(PRSnapshot(host: "github.com", toReview: [], mine: [], fetchedAt: t0))
        XCTAssertTrue(a.zone(now: t0, hosts: ["github.com"]).rows.isEmpty, "kein Repo ohne Aktivität")
        a.record(PRSnapshot(host: "github.com", toReview: [pr(1, repository: "f/rundfunk")], mine: [], fetchedAt: t0))
        XCTAssertEqual(a.zone(now: t0, hosts: ["github.com"]).rows.map(\.repository), ["rundfunk"])
    }

    func testHiddenRepoNeverAppearsEvenIfPinnedOrActive() {
        var a = PRAggregator()
        a.record(PRSnapshot(host: "github.com", toReview: [pr(1, repository: "f/rundfunk")], mine: [], fetchedAt: t0))
        let z = a.zone(now: t0, hosts: ["github.com"], pinned: ["github.com/f/rundfunk"],
                       hidden: ["github.com/f/rundfunk"])
        XCTAssertTrue(z.rows.isEmpty)
    }

    func testSortsToReviewFirstThenPinnedThenRest() {
        var a = PRAggregator()
        a.record(PRSnapshot(host: "github.com",
                            toReview: [pr(1, repository: "f/zzz")],
                            mine: [pr(2, repository: "f/aaa"), pr(3, repository: "f/mmm")],
                            fetchedAt: t0))
        let z = a.zone(now: t0, hosts: ["github.com"], pinned: ["github.com/f/mmm"])
        XCTAssertEqual(z.rows.map(\.repository), ["zzz", "mmm", "aaa"],
                      "zu reviewen > 0 zuerst, dann angeheftet, dann der Rest")
    }

    func testMultipleHostsEachKeepTheirOwnRows() {
        var a = PRAggregator()
        a.record(PRSnapshot(host: "github.com", toReview: [pr(1, repository: "f/rundfunk")], mine: [], fetchedAt: t0))
        a.record(PRSnapshot(host: "ghe.firma.de", toReview: [pr(2, repository: "f/rundfunk")], mine: [],
                            fetchedAt: t0))
        let z = a.zone(now: t0, hosts: ["github.com", "ghe.firma.de"])
        XCTAssertEqual(Set(z.rows.map(\.repoKey)), ["github.com/f/rundfunk", "ghe.firma.de/f/rundfunk"])
        XCTAssertEqual(z.rows.count, 2, "gleicher Repo-Name auf zwei Hosts bleibt getrennt")
    }
}
