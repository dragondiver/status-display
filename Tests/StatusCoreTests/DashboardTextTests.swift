import XCTest
@testable import StatusCore

final class DashboardTextTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func pr(extra: Bool = false, codeOwner: Bool = false, foreign: Bool = false, failing: Bool = false,
                    createdAt: Date? = nil, additions: Int? = nil, deletions: Int? = nil, files: Int? = nil,
                    mergeable: Mergeable? = nil, login: String? = nil, name: String? = nil,
                    checks: CheckSummary? = nil, reviews: [ReviewSummary] = []) -> PullRequest {
        PullRequest(number: 1, title: "t", repository: "acme/api", url: URL(string: "https://x/1")!,
                    ciFailing: failing, hasCodeOwnerRequestForMe: codeOwner, hasExtraRequestForMe: extra,
                    hasForeignApprovalOrChangesRequested: foreign, createdAt: createdAt, additions: additions,
                    deletions: deletions, changedFiles: files, mergeable: mergeable, authorLogin: login,
                    authorName: name, checks: checks, reviews: reviews)
    }

    func testShortAge() {
        XCTAssertEqual(DashboardText.shortAge(from: t0, now: t0.addingTimeInterval(12 * 60)), "12 min")
        XCTAssertEqual(DashboardText.shortAge(from: t0, now: t0.addingTimeInterval(3 * 3600 + 59 * 60)), "3 h")
        XCTAssertEqual(DashboardText.shortAge(from: t0, now: t0.addingTimeInterval(2 * 86_400 + 5)), "2 T")
        XCTAssertEqual(DashboardText.shortAge(from: t0, now: t0.addingTimeInterval(-60)), "0 min")
    }

    func testLongAge() {
        XCTAssertEqual(DashboardText.longAge(from: t0, now: t0.addingTimeInterval(20)), "gerade eben")
        XCTAssertEqual(DashboardText.longAge(from: t0, now: t0.addingTimeInterval(60)), "vor 1 Minute")
        XCTAssertEqual(DashboardText.longAge(from: t0, now: t0.addingTimeInterval(5 * 60)), "vor 5 Minuten")
        XCTAssertEqual(DashboardText.longAge(from: t0, now: t0.addingTimeInterval(3600)), "vor 1 Stunde")
        XCTAssertEqual(DashboardText.longAge(from: t0, now: t0.addingTimeInterval(86_400)), "vor 1 Tag")
        XCTAssertEqual(DashboardText.longAge(from: t0, now: t0.addingTimeInterval(2 * 86_400)), "vor 2 Tagen")
    }

    func testReason() {
        XCTAssertEqual(DashboardText.reason(pr(extra: true), isMine: false), "ausdrücklich als Reviewer angefragt")
        XCTAssertEqual(DashboardText.reason(pr(codeOwner: true), isMine: false),
                       "als Code-Owner angefragt, noch niemand hat reviewt")
        XCTAssertEqual(DashboardText.reason(pr(codeOwner: true, foreign: true), isMine: false),
                       "als Code-Owner angefragt, schon von anderen reviewt")
        XCTAssertEqual(DashboardText.reason(pr(), isMine: true), "dein PR")
    }

    func testAuthorPrefersDisplayNameAndToleratesMissingFields() {
        let created = t0.addingTimeInterval(-2 * 86_400)
        XCTAssertEqual(DashboardText.author(pr(createdAt: created, login: "dev-a", name: "Dev A"), now: t0),
                       "Dev A · vor 2 Tagen")
        XCTAssertEqual(DashboardText.author(pr(login: "dev-a"), now: t0), "dev-a")
        XCTAssertEqual(DashboardText.author(pr(), now: t0), "unbekannt")
    }

    func testReviews() {
        XCTAssertEqual(DashboardText.reviews(pr()), "noch keine Reviews")
        XCTAssertEqual(DashboardText.reviews(pr(reviews: [ReviewSummary(login: "dev-b", state: .approved),
                                                          ReviewSummary(login: "dev-c", state: .changesRequested),
                                                          ReviewSummary(login: "dev-d", state: .pending)])),
                       "dev-b hat freigegeben · dev-c hat Änderungen angefordert")
    }

    func testChecks() {
        XCTAssertEqual(DashboardText.checks(pr(checks: CheckSummary(total: 8, passed: 8, failed: 0))), "8 von 8 grün")
        XCTAssertEqual(DashboardText.checks(pr(checks: CheckSummary(total: 8, passed: 5, failed: 2))),
                       "2 rot · 5 grün · 1 offen")
        XCTAssertEqual(DashboardText.checks(pr(checks: CheckSummary(total: 0, passed: 0, failed: 0))), "keine Checks")
        XCTAssertEqual(DashboardText.checks(pr(failing: true)), "rot")
        XCTAssertEqual(DashboardText.checks(pr()), "keine Angaben")
    }

    func testSizeAndMerge() {
        XCTAssertEqual(DashboardText.size(pr(additions: 7, deletions: 7, files: 5)), "5 Dateien · +7 −7")
        XCTAssertEqual(DashboardText.size(pr(files: 1)), "1 Datei")
        XCTAssertEqual(DashboardText.size(pr()), "unbekannt")
        XCTAssertEqual(DashboardText.merge(pr(mergeable: .conflicting)), "Merge-Konflikt")
        XCTAssertEqual(DashboardText.merge(pr(mergeable: .mergeable)), "konfliktfrei")
        XCTAssertNil(DashboardText.merge(pr(mergeable: .unknown)))
        XCTAssertNil(DashboardText.merge(pr()))
    }

    func testCheckSummaryOtherNeverNegative() {
        XCTAssertEqual(CheckSummary(total: 3, passed: 2, failed: 1).other, 0)
        XCTAssertEqual(CheckSummary(total: 1, passed: 2, failed: 1).other, 0)
    }
}
