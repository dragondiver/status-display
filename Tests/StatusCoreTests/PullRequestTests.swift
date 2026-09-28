import XCTest
@testable import StatusCore

/// Testet `PullRequest.needsMyReview` isoliert von der GraphQL-Zuordnung (die hat eigene Tests in
/// `GitHubAPITests`) – die Zählregel für Review-Requests (Entscheidung Florian, 28.09.2026,
/// status-display#21, verfeinert im selben Issue).
final class PullRequestTests: XCTestCase {
    private func pr(codeOwner: Bool = false, extra: Bool = false, foreignDecision: Bool = false) -> PullRequest {
        PullRequest(number: 1, title: "t", repository: "a/b", url: URL(string: "https://x/1")!, ciFailing: false,
                   hasCodeOwnerRequestForMe: codeOwner, hasExtraRequestForMe: extra,
                   hasForeignApprovalOrChangesRequested: foreignDecision)
    }

    func testCodeOwnerRequestCountsWithNoReviews() {
        XCTAssertTrue(pr(codeOwner: true).needsMyReview)
    }

    func testCodeOwnerRequestDoesNotCountAfterForeignApprovalOrChangesRequested() {
        XCTAssertFalse(pr(codeOwner: true, foreignDecision: true).needsMyReview)
    }

    func testExtraRequestCountsDespiteForeignApproval() {
        XCTAssertTrue(pr(extra: true, foreignDecision: true).needsMyReview)
    }

    func testExtraRequestCountsWithoutForeignDecisionToo() {
        XCTAssertTrue(pr(extra: true).needsMyReview)
    }

    func testNeitherRequestKindDoesNotCount() {
        XCTAssertFalse(pr().needsMyReview)
    }

    func testBothCodeOwnerAndExtraStillCountAfterForeignDecision() {
        // Extra sticht: sobald irgendeine Extra-Anfrage vorliegt, zählt der PR unabhängig davon,
        // ob die Code-Owner-Anfrage schon erledigt ist.
        XCTAssertTrue(pr(codeOwner: true, extra: true, foreignDecision: true).needsMyReview)
    }
}
