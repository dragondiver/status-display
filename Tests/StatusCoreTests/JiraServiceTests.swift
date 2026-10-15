import XCTest
@testable import StatusCore

final class JiraServiceTests: XCTestCase {
    func testParseIssuesMinimalResponse() throws {
        let json = """
        {"issues":[{
            "id":"10001","key":"PROJ-42",
            "fields":{
                "summary":"Fix login",
                "status":{"name":"In Progress"},
                "project":{"key":"PROJ","name":"My Project"}
            }
        }]}
        """
        let issues = try JiraService.parseIssues(from: Data(json.utf8), domain: "x.atlassian.net")
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues[0].key, "PROJ-42")
        XCTAssertEqual(issues[0].summary, "Fix login")
        XCTAssertEqual(issues[0].statusName, "In Progress")
        XCTAssertEqual(issues[0].projectKey, "PROJ")
        XCTAssertEqual(issues[0].projectName, "My Project")
        XCTAssertNil(issues[0].sprintName)
        XCTAssertNil(issues[0].priorityName)
        XCTAssertEqual(issues[0].url.absoluteString, "https://x.atlassian.net/browse/PROJ-42")
    }

    func testParseIssuesWithActiveSprint() throws {
        let json = """
        {"issues":[{
            "id":"10002","key":"PROJ-43",
            "fields":{
                "summary":"Bug",
                "status":{"name":"To Do"},
                "project":{"key":"PROJ","name":"My Project"},
                "customfield_10020":[
                    {"name":"Sprint 1","state":"closed"},
                    {"name":"Sprint 2","state":"active"}
                ]
            }
        }]}
        """
        let issues = try JiraService.parseIssues(from: Data(json.utf8), domain: "x.atlassian.net")
        XCTAssertEqual(issues[0].sprintName, "Sprint 2")
    }

    func testParseIssuesWithNullSprint() throws {
        let json = """
        {"issues":[{
            "id":"10003","key":"PROJ-44",
            "fields":{
                "summary":"Task",
                "status":{"name":"To Do"},
                "project":{"key":"PROJ","name":"My Project"},
                "customfield_10020":null
            }
        }]}
        """
        let issues = try JiraService.parseIssues(from: Data(json.utf8), domain: "x.atlassian.net")
        XCTAssertNil(issues[0].sprintName)
    }

    func testParseIssuesWithPriority() throws {
        let json = """
        {"issues":[{
            "id":"10004","key":"PROJ-45",
            "fields":{
                "summary":"Prio",
                "status":{"name":"To Do"},
                "priority":{"name":"High"},
                "project":{"key":"PROJ","name":"My Project"}
            }
        }]}
        """
        let issues = try JiraService.parseIssues(from: Data(json.utf8), domain: "x.atlassian.net")
        XCTAssertEqual(issues[0].priorityName, "High")
    }

    func testParseIssuesEmptyArray() throws {
        let issues = try JiraService.parseIssues(from: Data(#"{"issues":[]}"#.utf8), domain: "x.atlassian.net")
        XCTAssertEqual(issues.count, 0)
    }

    func testFetchReturnsErrorSnapshotForInvalidDomain() async throws {
        // Leerzeichen in der Domain → URLComponents gibt nil → kein Absturz
        let snap = try await JiraService().fetch(domain: "my domain .net", email: "a@b.de", token: "t")
        XCTAssertNotNil(snap.error, "Ungültige Domain muss Fehler-Snapshot liefern, nicht abstürzen")
        XCTAssertTrue(snap.issues.isEmpty)
    }

    func testNormalizedDomainStripsSchemaAndSlash() {
        XCTAssertEqual(JiraService.normalizedDomain("https://foo.atlassian.net/"), "foo.atlassian.net")
        XCTAssertEqual(JiraService.normalizedDomain("http://foo.atlassian.net"),   "foo.atlassian.net")
        XCTAssertEqual(JiraService.normalizedDomain("foo.atlassian.net"),           "foo.atlassian.net")
        XCTAssertEqual(JiraService.normalizedDomain("FOO.ATLASSIAN.NET/"),          "foo.atlassian.net")
    }

    func testSnapshotErrorWhenHTTPFails() async throws {
        struct FailingFetcher: JiraFetcher {
            func fetch(domain: String, email: String, token: String) async throws -> JiraSnapshot {
                JiraSnapshot(issues: [], fetchedAt: Date(), error: "HTTP 401")
            }
        }
        let snap = try await FailingFetcher().fetch(domain: "x.atlassian.net", email: "a", token: "b")
        XCTAssertEqual(snap.issues, [])
        XCTAssertNotNil(snap.error)
    }
}
