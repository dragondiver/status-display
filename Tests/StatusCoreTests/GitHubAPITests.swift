import XCTest
@testable import StatusCore

final class GitHubAPITests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    func testURLs() {
        XCTAssertEqual(GitHubAPI.graphqlURL(host: "github.com").absoluteString, "https://api.github.com/graphql")
        XCTAssertEqual(GitHubAPI.graphqlURL(host: "ghe.firma.de").absoluteString, "https://ghe.firma.de/api/graphql")
    }

    func testParse() throws {
        let json = #"""
        {"data":{
          "review":{"nodes":[
            {"number":12,"title":"Fix","url":"https://github.com/a/b/pull/12","repository":{"nameWithOwner":"a/b"},"commits":{"nodes":[]}},
            {}
          ]},
          "mine":{"nodes":[
            {"number":3,"title":"Rot","url":"https://github.com/a/c/pull/3","repository":{"nameWithOwner":"a/c"},"commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"FAILURE"}}}]}},
            {"number":4,"title":"Grün","url":"https://github.com/a/c/pull/4","repository":{"nameWithOwner":"a/c"},"commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"SUCCESS"}}}]}},
            {"number":5,"title":"Ohne CI","url":"https://github.com/a/c/pull/5","repository":{"nameWithOwner":"a/c"},"commits":{"nodes":[{"commit":{"statusCheckRollup":null}}]}}
          ]}
        }}
        """#
        let s = try GitHubAPI.parse(Data(json.utf8), host: "github.com", at: now)
        XCTAssertEqual(s.toReview.map(\.number), [12])
        XCTAssertEqual(s.mine.map(\.number), [3, 4, 5])
        XCTAssertEqual(s.ciFailingCount, 1)
        XCTAssertEqual(s.toReview[0].repository, "a/b")
        XCTAssertEqual(s.fetchedAt, now)
        XCTAssertFalse(s.mine[0].isDraft)
    }

    func testDraftIsReadFromResponseAndExcludedFromCiFailingCount() throws {
        let json = #"""
        {"data":{
          "review":{"nodes":[]},
          "mine":{"nodes":[
            {"number":1,"title":"Draft rot","url":"https://github.com/a/c/pull/1","repository":{"nameWithOwner":"a/c"},"isDraft":true,"commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"FAILURE"}}}]}},
            {"number":2,"title":"Nicht-Draft rot","url":"https://github.com/a/c/pull/2","repository":{"nameWithOwner":"a/c"},"isDraft":false,"commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"FAILURE"}}}]}}
          ]}
        }}
        """#
        let s = try GitHubAPI.parse(Data(json.utf8), host: "github.com", at: now)
        XCTAssertTrue(s.mine[0].isDraft)
        XCTAssertFalse(s.mine[1].isDraft)
        XCTAssertTrue(s.mine[0].ciFailing)
        XCTAssertTrue(s.mine[1].ciFailing)
        XCTAssertEqual(s.ciFailingCount, 1)
    }

    func testGraphQLErrorWithoutData() {
        let json = #"{"data":null,"errors":[{"message":"Bad credentials"}]}"#
        XCTAssertThrowsError(try GitHubAPI.parse(Data(json.utf8), host: "x", at: now)) {
            XCTAssertEqual($0 as? GitHubError, .graphql("Bad credentials"))
        }
        XCTAssertThrowsError(try GitHubAPI.parse(Data("<html>".utf8), host: "x", at: now)) {
            XCTAssertEqual($0 as? GitHubError, .decoding)
        }
    }

    func testDataWithErrorsKeepsPRsAndSetsWarning() throws {
        let json = #"""
        {"data":{
          "review":{"nodes":[{"number":7,"title":"T","url":"https://github.com/a/b/pull/7","repository":{"nameWithOwner":"a/b"},"commits":{"nodes":[]}}]},
          "mine":{"nodes":[null]}
        },"errors":[{"message":"Resource not accessible by integration"},{"message":"zweiter"}]}
        """#
        let s = try GitHubAPI.parse(Data(json.utf8), host: "github.com", at: now)
        XCTAssertEqual(s.toReview.map(\.number), [7])
        XCTAssertEqual(s.warning, "Resource not accessible by integration")
        let clean = try GitHubAPI.parse(Data(#"{"data":{"review":{"nodes":[]},"mine":{"nodes":[]}}}"#.utf8),
                                        host: "github.com", at: now)
        XCTAssertNil(clean.warning)
    }

    func testHTTP401Message() {
        XCTAssertEqual(GitHubError.http(401).message, "Token abgelehnt (HTTP 401) – gh auth refresh ausführen")
        XCTAssertEqual(GitHubError.http(502).message, "HTTP 502")
    }

    // MARK: reviewDecision (Issue #21)

    func testParsesAllThreeReviewDecisionValuesPlusNullAndUnknown() throws {
        let json = #"""
        {"data":{
          "review":{"nodes":[
            {"number":1,"title":"a","url":"https://github.com/a/b/pull/1","repository":{"nameWithOwner":"a/b"},"reviewDecision":"APPROVED","commits":{"nodes":[]}},
            {"number":2,"title":"b","url":"https://github.com/a/b/pull/2","repository":{"nameWithOwner":"a/b"},"reviewDecision":"CHANGES_REQUESTED","commits":{"nodes":[]}},
            {"number":3,"title":"c","url":"https://github.com/a/b/pull/3","repository":{"nameWithOwner":"a/b"},"reviewDecision":"REVIEW_REQUIRED","commits":{"nodes":[]}},
            {"number":4,"title":"d","url":"https://github.com/a/b/pull/4","repository":{"nameWithOwner":"a/b"},"reviewDecision":null,"commits":{"nodes":[]}},
            {"number":5,"title":"e","url":"https://github.com/a/b/pull/5","repository":{"nameWithOwner":"a/b"},"reviewDecision":"SOME_FUTURE_VALUE","commits":{"nodes":[]}},
            {"number":6,"title":"f","url":"https://github.com/a/b/pull/6","repository":{"nameWithOwner":"a/b"},"commits":{"nodes":[]}}
          ]},
          "mine":{"nodes":[]}
        }}
        """#
        let s = try GitHubAPI.parse(Data(json.utf8), host: "github.com", at: now)
        let byNumber = Dictionary(uniqueKeysWithValues: s.toReview.map { ($0.number, $0) })
        XCTAssertEqual(byNumber[1]?.reviewDecision, .approved)
        XCTAssertEqual(byNumber[2]?.reviewDecision, .changesRequested)
        XCTAssertEqual(byNumber[3]?.reviewDecision, .reviewRequired)
        XCTAssertNil(byNumber[4]?.reviewDecision, "explizites null")
        XCTAssertNil(byNumber[5]?.reviewDecision, "unbekannter Enum-Wert wird wie null behandelt")
        XCTAssertNil(byNumber[6]?.reviewDecision, "Feld fehlt ganz")
        // reviewDecision ist seit der Verfeinerung von Issue #21 (28.09.2026) nur noch informativ –
        // ob ein Review-Request zählt, entscheidet needsMyReview über reviewRequests/reviews
        // (siehe testParsesReviewRequestsAndComputesNeedsMyReview unten), nicht mehr dieses Feld.
    }

    // MARK: reviewRequests/reviews → needsMyReview (Issue #21, Verfeinerung 28.09.2026)

    func testParsesReviewRequestsAndComputesNeedsMyReview() throws {
        let json = #"""
        {"data":{
          "viewer": {"login": "florian"},
          "review":{"nodes":[
            {"number":1,"title":"Code-Owner offen","url":"https://github.com/a/b/pull/1","repository":{"nameWithOwner":"a/b"},
             "author":{"login":"author1"},"commits":{"nodes":[]},
             "reviewRequests":{"nodes":[{"asCodeOwner":true,"requestedReviewer":{"__typename":"User","login":"florian"}}]},
             "reviews":{"nodes":[]}},
            {"number":2,"title":"Code-Owner fremd entschieden","url":"https://github.com/a/b/pull/2","repository":{"nameWithOwner":"a/b"},
             "author":{"login":"author1"},"commits":{"nodes":[]},
             "reviewRequests":{"nodes":[{"asCodeOwner":true,"requestedReviewer":{"__typename":"User","login":"florian"}}]},
             "reviews":{"nodes":[{"author":{"login":"other"},"state":"APPROVED"}]}},
            {"number":3,"title":"Code-Owner nur Autor-Review","url":"https://github.com/a/b/pull/3","repository":{"nameWithOwner":"a/b"},
             "author":{"login":"author1"},"commits":{"nodes":[]},
             "reviewRequests":{"nodes":[{"asCodeOwner":true,"requestedReviewer":{"__typename":"User","login":"florian"}}]},
             "reviews":{"nodes":[{"author":{"login":"author1"},"state":"APPROVED"}]}},
            {"number":4,"title":"Extra trotz fremder Freigabe","url":"https://github.com/a/b/pull/4","repository":{"nameWithOwner":"a/b"},
             "author":{"login":"author1"},"commits":{"nodes":[]},
             "reviewRequests":{"nodes":[{"asCodeOwner":false,"requestedReviewer":{"__typename":"User","login":"florian"}}]},
             "reviews":{"nodes":[{"author":{"login":"other"},"state":"APPROVED"}]}},
            {"number":5,"title":"Team-Code-Owner","url":"https://github.com/a/b/pull/5","repository":{"nameWithOwner":"a/b"},
             "author":{"login":"author1"},"commits":{"nodes":[]},
             "reviewRequests":{"nodes":[{"asCodeOwner":true,"requestedReviewer":{"__typename":"Team","name":"platform"}}]},
             "reviews":{"nodes":[]}},
            {"number":6,"title":"Anfrage an andere","url":"https://github.com/a/b/pull/6","repository":{"nameWithOwner":"a/b"},
             "author":{"login":"author1"},"commits":{"nodes":[]},
             "reviewRequests":{"nodes":[{"asCodeOwner":true,"requestedReviewer":{"__typename":"User","login":"jemand-anders"}}]},
             "reviews":{"nodes":[]}},
            {"number":7,"title":"Non-Code-Owner-Team ignoriert","url":"https://github.com/a/b/pull/7","repository":{"nameWithOwner":"a/b"},
             "author":{"login":"author1"},"commits":{"nodes":[]},
             "reviewRequests":{"nodes":[{"asCodeOwner":false,"requestedReviewer":{"__typename":"Team","name":"platform"}}]},
             "reviews":{"nodes":[]}},
            {"number":8,"title":"Eigene frühere Freigabe, erneut angefragt","url":"https://github.com/a/b/pull/8","repository":{"nameWithOwner":"a/b"},
             "author":{"login":"author1"},"commits":{"nodes":[]},
             "reviewRequests":{"nodes":[{"asCodeOwner":true,"requestedReviewer":{"__typename":"User","login":"florian"}}]},
             "reviews":{"nodes":[{"author":{"login":"florian"},"state":"APPROVED"}]}},
            {"number":9,"title":"Eigene frühere Freigabe plus fremde Freigabe","url":"https://github.com/a/b/pull/9","repository":{"nameWithOwner":"a/b"},
             "author":{"login":"author1"},"commits":{"nodes":[]},
             "reviewRequests":{"nodes":[{"asCodeOwner":true,"requestedReviewer":{"__typename":"User","login":"florian"}}]},
             "reviews":{"nodes":[{"author":{"login":"florian"},"state":"APPROVED"},{"author":{"login":"other"},"state":"APPROVED"}]}}
          ]},
          "mine":{"nodes":[]}
        }}
        """#
        let s = try GitHubAPI.parse(Data(json.utf8), host: "github.com", at: now)
        let byNumber = Dictionary(uniqueKeysWithValues: s.toReview.map { ($0.number, $0) })

        XCTAssertTrue(byNumber[1]!.needsMyReview, "Code-Owner-Anfrage ohne Reviews zählt")
        XCTAssertTrue(byNumber[1]!.hasCodeOwnerRequestForMe)
        XCTAssertFalse(byNumber[1]!.hasExtraRequestForMe)

        XCTAssertFalse(byNumber[2]!.needsMyReview, "fremdes APPROVED erledigt die Code-Owner-Anfrage")

        XCTAssertTrue(byNumber[3]!.needsMyReview, "ein Review nur durch den Autor zählt nicht als Code-Owner-Review")

        XCTAssertTrue(byNumber[4]!.needsMyReview, "Extra-Anfrage zählt trotz fremder Freigabe")
        XCTAssertTrue(byNumber[4]!.hasExtraRequestForMe)

        XCTAssertTrue(byNumber[5]!.needsMyReview, "Team-Code-Owner-Anfrage zählt")
        XCTAssertTrue(byNumber[5]!.hasCodeOwnerRequestForMe)

        XCTAssertFalse(byNumber[6]!.needsMyReview, "Anfrage an jemand anderen zählt nicht")
        XCTAssertFalse(byNumber[6]!.hasCodeOwnerRequestForMe)

        XCTAssertFalse(byNumber[7]!.needsMyReview, "Non-Code-Owner-Team-Anfrage wird ignoriert")

        // Befund verifier, 28.09.2026: hasForeignApprovalOrChangesRequested schloss ursprünglich
        // nur den PR-Autor aus, nicht den Viewer selbst – eine eigene frühere Freigabe zählte
        // dadurch fälschlich als fremde Erledigung, sobald ich erneut als Code-Owner angefragt wurde.
        XCTAssertTrue(byNumber[8]!.needsMyReview,
                      "eine frühere eigene Freigabe erledigt eine erneute Code-Owner-Anfrage nicht")
        XCTAssertFalse(byNumber[8]!.hasForeignApprovalOrChangesRequested)

        XCTAssertFalse(byNumber[9]!.needsMyReview,
                       "zusätzlich zur eigenen alten Freigabe erledigt eine fremde Freigabe die Anfrage")
        XCTAssertTrue(byNumber[9]!.hasForeignApprovalOrChangesRequested)
    }

    // MARK: Detailfelder fürs Dashboard (status-display#24)

    func testQueryRequestsDetailFields() {
        for field in ["createdAt", "additions", "deletions", "changedFiles", "mergeable", "... on User { name }",
                      "contexts(first: 50)", "totalCount", "... on CheckRun { status conclusion }",
                      "... on StatusContext { state }"] {
            XCTAssertTrue(GitHubAPI.query.contains(field), field)
        }
    }

    func testParsesDetailFields() throws {
        let json = #"""
        {"data":{"viewer":{"login":"me"},
          "review":{"nodes":[]},
          "mine":{"nodes":[
            {"number":1,"title":"T","url":"https://github.com/a/b/pull/1","repository":{"nameWithOwner":"a/b"},
             "createdAt":"2026-09-26T10:00:00Z","additions":7,"deletions":3,"changedFiles":5,"mergeable":"CONFLICTING",
             "author":{"login":"me","name":"Dev Me"},
             "commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"FAILURE","contexts":{"totalCount":9,"nodes":[
               {"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"},
               {"__typename":"CheckRun","status":"COMPLETED","conclusion":"SKIPPED"},
               {"__typename":"CheckRun","status":"COMPLETED","conclusion":"NEUTRAL"},
               {"__typename":"CheckRun","status":"COMPLETED","conclusion":"FAILURE"},
               {"__typename":"CheckRun","status":"COMPLETED","conclusion":"TIMED_OUT"},
               {"__typename":"CheckRun","status":"IN_PROGRESS","conclusion":null},
               {"__typename":"StatusContext","state":"SUCCESS"},
               {"__typename":"StatusContext","state":"ERROR"},
               {"__typename":"StatusContext","state":"PENDING"}
             ]}}}}]},
             "reviews":{"nodes":[
               {"author":{"login":"dev-b"},"state":"COMMENTED"},
               {"author":{"login":"me"},"state":"COMMENTED"},
               {"author":{"login":"dev-c"},"state":"CHANGES_REQUESTED"},
               {"author":{"login":"dev-b"},"state":"APPROVED"},
               {"author":{"login":"dev-d"},"state":"SOMETHING_NEW"}
             ]}}
          ]}
        }}
        """#
        let p = try XCTUnwrap(GitHubAPI.parse(Data(json.utf8), host: "github.com", at: now).mine.first)
        XCTAssertEqual(p.createdAt, Date(timeIntervalSince1970: 1_790_416_800))
        XCTAssertEqual(p.additions, 7)
        XCTAssertEqual(p.deletions, 3)
        XCTAssertEqual(p.changedFiles, 5)
        XCTAssertEqual(p.mergeable, .conflicting)
        XCTAssertEqual(p.authorLogin, "me")
        XCTAssertEqual(p.authorName, "Dev Me")
        XCTAssertEqual(p.checks, CheckSummary(total: 9, passed: 4, failed: 3))
        XCTAssertEqual(p.checks?.other, 2)
        // Letzter Zustand je Reviewer, ohne Autor und ohne unbekannten Zustand.
        XCTAssertEqual(p.reviews, [ReviewSummary(login: "dev-b", state: .approved),
                                   ReviewSummary(login: "dev-c", state: .changesRequested)])
    }

    func testMissingOrMalformedDetailFieldsKeepTheNode() throws {
        let json = #"""
        {"data":{
          "review":{"nodes":[
            {"number":1,"title":"Ohne alles","url":"https://github.com/a/b/pull/1","repository":{"nameWithOwner":"a/b"}},
            {"number":2,"title":"Nulls","url":"https://github.com/a/b/pull/2","repository":{"nameWithOwner":"a/b"},
             "createdAt":null,"additions":null,"deletions":null,"changedFiles":null,"mergeable":null,
             "author":{"login":"dev-a","name":null},
             "commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"SUCCESS","contexts":null}}}]}},
            {"number":3,"title":"Falsche Typen","url":"https://github.com/a/b/pull/3","repository":{"nameWithOwner":"a/b"},
             "createdAt":"kein Datum","additions":"viele","deletions":{},"changedFiles":[],"mergeable":"MAYBE",
             "author":{"login":"dev-a","name":""},
             "commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"FAILURE","contexts":{"totalCount":"x","nodes":7}}}}]}},
            {"number":4,"title":"Unbekannte Check-Werte","url":"https://github.com/a/b/pull/4","repository":{"nameWithOwner":"a/b"},
             "commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"PENDING","contexts":{"nodes":[
               {"__typename":"CheckRun","status":"COMPLETED","conclusion":"STALE"},
               {"__typename":"KuenftigerTyp"},
               null
             ]}}}}]}}
          ]},
          "mine":{"nodes":[]}
        }}
        """#
        let prs = try GitHubAPI.parse(Data(json.utf8), host: "github.com", at: now).toReview
        XCTAssertEqual(prs.map(\.number), [1, 2, 3, 4])
        for p in prs.prefix(3) {
            XCTAssertNil(p.createdAt)
            XCTAssertNil(p.additions)
            XCTAssertNil(p.deletions)
            XCTAssertNil(p.changedFiles)
            XCTAssertNil(p.mergeable)
            XCTAssertNil(p.authorName)
            XCTAssertNil(p.checks)
            XCTAssertEqual(p.reviews, [])
        }
        XCTAssertNil(prs[0].authorLogin)
        XCTAssertEqual(prs[1].authorLogin, "dev-a")
        XCTAssertTrue(prs[2].ciFailing, "Gesamtzustand bleibt auch ohne lesbare Einzelzählung erhalten")
        // Ohne totalCount zählt die Zahl der gelesenen Einträge; Unbekanntes bleibt als „offen“ sichtbar.
        XCTAssertEqual(prs[3].checks, CheckSummary(total: 2, passed: 0, failed: 0))
    }

    func testParsesDatesWithFractionalSeconds() {
        XCTAssertEqual(GitHubAPI.parseDate("2026-09-26T10:00:00.500Z"), Date(timeIntervalSince1970: 1_790_416_800.5))
        XCTAssertEqual(GitHubAPI.parseDate("2026-09-26T10:00:00Z"), Date(timeIntervalSince1970: 1_790_416_800))
        XCTAssertNil(GitHubAPI.parseDate("gestern"))
    }
}
