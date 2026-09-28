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
             "reviews":{"nodes":[]}}
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
    }
}
