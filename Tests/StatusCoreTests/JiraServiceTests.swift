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
        XCTAssertEqual(snap.error, "Ungültige Domain", "Ungültige Domain muss Fehler-Snapshot liefern, nicht abstürzen")
        XCTAssertTrue(snap.issues.isEmpty)
    }

    func testNormalizedDomainStripsSchemaAndSlash() {
        XCTAssertEqual(JiraService.normalizedDomain("https://foo.atlassian.net/"), "foo.atlassian.net")
        XCTAssertEqual(JiraService.normalizedDomain("http://foo.atlassian.net"),   "foo.atlassian.net")
        XCTAssertEqual(JiraService.normalizedDomain("foo.atlassian.net"),           "foo.atlassian.net")
        XCTAssertEqual(JiraService.normalizedDomain("FOO.ATLASSIAN.NET/"),          "foo.atlassian.net")
    }

    // MARK: fetch gegen gestubbtes HTTP (StubProtocol aus PRServiceTests)

    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: config)
    }

    func testFetchSchicktJQLMitSortierungUndBasicAuth() async throws {
        var seen: URLRequest?
        StubProtocol.handler = { req in
            seen = req
            return (200, Data(#"{"issues":[]}"#.utf8))
        }
        let snap = try await JiraService(session: session())
            .fetch(domain: "https://x.atlassian.net/", email: "a@b.de", token: "tok")
        XCTAssertNil(snap.error)
        let url = try XCTUnwrap(seen?.url)
        XCTAssertEqual(url.host, "x.atlassian.net")
        XCTAssertEqual(url.path, "/rest/api/3/search/jql")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        // Sortierung gehört ins JQL; /search/jql kennt keinen orderBy-Parameter.
        XCTAssertEqual(items.first { $0.name == "jql" }?.value,
                       "assignee=currentUser() AND statusCategory!=Done ORDER BY updated DESC")
        XCTAssertNil(items.first { $0.name == "orderBy" })
        XCTAssertEqual(seen?.value(forHTTPHeaderField: "Authorization"),
                       "Basic " + Data("a@b.de:tok".utf8).base64EncodedString())
    }

    func testFetchHTTP401LiefertFehlerSnapshot() async throws {
        StubProtocol.handler = { _ in (401, Data()) }
        let snap = try await JiraService(session: session())
            .fetch(domain: "x.atlassian.net", email: "a@b.de", token: "falsch")
        XCTAssertEqual(snap.error, "HTTP 401")
        XCTAssertEqual(snap.issues, [])
    }
}
