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
}
