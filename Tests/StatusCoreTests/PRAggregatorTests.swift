import XCTest
@testable import StatusCore

final class PRAggregatorTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func pr(_ n: Int, failing: Bool = false, draft: Bool = false) -> PullRequest {
        PullRequest(number: n, title: "t", repository: "a/b", url: URL(string: "https://x/\(n)")!,
                   ciFailing: failing, isDraft: draft)
    }

    func testEmptyIsUnknownAndStale() {
        XCTAssertEqual(PRAggregator().zone(now: t0, hosts: ["github.com"]), .unknown)
    }

    func testSumsHostsAndBecomesStale() {
        var a = PRAggregator()
        a.record(PRSnapshot(host: "github.com", toReview: [pr(1)], mine: [pr(2, failing: true)], fetchedAt: t0))
        a.record(PRSnapshot(host: "ghe", toReview: [pr(3), pr(4)], mine: [], fetchedAt: t0.addingTimeInterval(60)))
        let z = a.zone(now: t0.addingTimeInterval(100), hosts: ["github.com", "ghe"])
        XCTAssertEqual(z, PRZone(toReview: 3, mine: 1, ciFailing: 1, lastSuccess: t0, isStale: false))
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

    func testDraftPRWithFailingCIDoesNotCountInZoneButNonDraftDoes() {
        var a = PRAggregator()
        a.record(PRSnapshot(host: "github.com",
                            toReview: [],
                            mine: [pr(1, failing: true, draft: true), pr(2, failing: true)],
                            fetchedAt: t0))
        let z = a.zone(now: t0, hosts: ["github.com"])
        XCTAssertEqual(z.ciFailing, 1)
        XCTAssertEqual(z.mine, 2)
    }

    func testConfiguredHostWithoutSnapshotMakesZoneStale() {
        var a = PRAggregator()
        a.record(PRSnapshot(host: "github.com", toReview: [pr(1)], mine: [], fetchedAt: t0))
        XCTAssertTrue(a.zone(now: t0.addingTimeInterval(10), hosts: ["github.com", "ghe"]).isStale)
        a.record(PRSnapshot(host: "ghe", toReview: [], mine: [], fetchedAt: t0))
        XCTAssertFalse(a.zone(now: t0.addingTimeInterval(10), hosts: ["github.com", "ghe"]).isStale)
    }
}
