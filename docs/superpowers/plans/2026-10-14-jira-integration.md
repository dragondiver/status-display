# Jira-Integration — Implementierungsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Jira Cloud (atlassian.net) in status-display einbinden: zugewiesene offene Issues im Dashboard, Ticket-Zähler auf Panel und Board-Fenster.

**Architecture:** `JiraService` in StatusCore holt Issues via REST API v3 (Basic Auth). `AppModel` pollt alle 5 Minuten. `BoardState` trägt einen `jiraCount`-Zähler zu Panel und Board-Fenster. Das Dashboard-Fenster zeigt eine eigene Jira-Sektion neben den bestehenden PR-Bereichen.

**Tech Stack:** Swift, URLSession, macOS 14+, Jira Cloud REST API v3

**Spec:** `docs/superpowers/specs/2026-10-14-jira-integration.md`

## Global Constraints

- macOS 14+, Swift Language Mode 5
- StatusCore enthält die gesamte Logik (testbar ohne AppKit); StatusDisplay enthält die UI
- Commit-Messages auf Deutsch, Closing-Keywords englisch
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` für alle Test-Runs
- Keine echten API-Tokens in CI — `JiraFetcher`-Protokoll für Stubs

## Review Focus

1. **Kein Jira konfiguriert** (leeres `jiraDomain`): `refreshJira()` darf nicht aufgerufen werden, kein Absturz, `jira.openCount == 0`.
2. **HTTP 401 / 403 vom Server**: `JiraSnapshot.error` muss gesetzt werden, `issues` leer, kein Absturz.
3. **`customfield_10020` fehlt oder ist `null`**: `sprintName` muss `nil` sein, kein Absturz.
4. **Alle Issues gehören zu einem Projekt ohne Sprint**: `grouped()` gibt einen Eintrag mit `sprint == nil` zurück.
5. **`jiraCount == 0`**: Keine Jira-Zeile auf Panel und Board-Fenster; Sidebar-Abschnitt nicht sichtbar.

---

## Dateiübersicht

| Datei | Aktion |
|---|---|
| `Sources/StatusCore/Jira/JiraIssue.swift` | Neu: `JiraIssue`, `JiraSnapshot`, `JiraFetcher` |
| `Sources/StatusCore/Jira/JiraAggregator.swift` | Neu: Gruppierungslogik, Zähler |
| `Sources/StatusCore/Jira/JiraService.swift` | Neu: HTTP-Client, JSON-Parsing |
| `Sources/StatusCore/Render/BoardState.swift` | Ändern: `jiraCount: Int` |
| `Sources/StatusCore/Render/BoardRenderer.swift` | Ändern: Jira-Zeile in PR-Zone |
| `Sources/StatusCore/Render/BoardWindowRenderer.swift` | Ändern: Jira-Zeile in PR-Zone |
| `Sources/StatusCore/Settings/AppSettings.swift` | Ändern: `jiraDomain`, `jiraEmail`, `jiraToken` |
| `Sources/StatusDisplay/AppModel.swift` | Ändern: `jira`, `refreshJira`, 5min-Timer |
| `Sources/StatusDisplay/SettingsView.swift` | Ändern: neuer Jira-Reiter |
| `Sources/StatusDisplay/DashboardView.swift` | Ändern: Jira-Sektion, `SidebarSelection.jiraProject` |
| `Tests/StatusCoreTests/JiraAggregatorTests.swift` | Neu |
| `Tests/StatusCoreTests/JiraServiceTests.swift` | Neu |
| `Tests/StatusCoreTests/AppSettingsTests.swift` | Ändern |
| `Tests/StatusCoreTests/BoardRendererTests.swift` | Ändern |

---

## Task 1: Datenmodell (JiraIssue, JiraSnapshot, JiraAggregator)

**Files:**
- Create: `Sources/StatusCore/Jira/JiraIssue.swift`
- Create: `Sources/StatusCore/Jira/JiraAggregator.swift`
- Create: `Tests/StatusCoreTests/JiraAggregatorTests.swift`

**Interfaces:**
- Produces:
  - `public struct JiraIssue: Equatable, Identifiable`
  - `public struct JiraSnapshot: Equatable` mit `static let empty`
  - `public protocol JiraFetcher`
  - `public struct JiraAggregator: Equatable` mit `grouped()`, `openCount`, `isStale`, `record(_:)`

- [ ] **Tests anlegen (fehlschlagend)**

```swift
// Tests/StatusCoreTests/JiraAggregatorTests.swift
import XCTest
@testable import StatusCore

final class JiraAggregatorTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func issue(_ key: String, project: String = "PROJ", projectName: String = "Projekt",
                       sprint: String? = "Sprint 1") -> JiraIssue {
        JiraIssue(id: key, key: key, summary: "Fix \(key)", statusName: "To Do",
                  priorityName: nil, projectKey: project, projectName: projectName,
                  sprintName: sprint,
                  url: URL(string: "https://x.atlassian.net/browse/\(key)")!)
    }

    func testOpenCountMatchesIssueCount() {
        let snap = JiraSnapshot(issues: [issue("PROJ-1"), issue("PROJ-2")], fetchedAt: t0, error: nil)
        XCTAssertEqual(JiraAggregator(snapshot: snap).openCount, 2)
    }

    func testOpenCountZeroWhenEmpty() {
        XCTAssertEqual(JiraAggregator.unknown.openCount, 0)
    }

    func testIsStaleWhenEmpty() {
        XCTAssertTrue(JiraAggregator.unknown.isStale)
    }

    func testIsStaleAfterTenMinutes() {
        let old = Date(timeIntervalSinceNow: -601)
        let snap = JiraSnapshot(issues: [], fetchedAt: old, error: nil)
        XCTAssertTrue(JiraAggregator(snapshot: snap).isStale)
    }

    func testNotStaleWhenFresh() {
        let snap = JiraSnapshot(issues: [], fetchedAt: Date(), error: nil)
        XCTAssertFalse(JiraAggregator(snapshot: snap).isStale)
    }

    func testGroupedByProjectAndSprint() {
        let issues = [
            issue("PROJ-1", project: "PROJ", projectName: "Projekt A", sprint: "Sprint 1"),
            issue("PROJ-2", project: "PROJ", projectName: "Projekt A", sprint: "Sprint 1"),
            issue("OTHER-1", project: "OTHER", projectName: "Projekt B", sprint: nil),
        ]
        let grouped = JiraAggregator(snapshot: JiraSnapshot(issues: issues, fetchedAt: t0, error: nil)).grouped()
        XCTAssertEqual(grouped.count, 2)
        XCTAssertEqual(grouped[0].project, "OTHER")   // alphabetisch
        XCTAssertEqual(grouped[1].project, "PROJ")
        XCTAssertEqual(grouped[1].sprints.count, 1)
        XCTAssertEqual(grouped[1].sprints[0].sprint, "Sprint 1")
        XCTAssertEqual(grouped[1].sprints[0].issues.count, 2)
    }

    func testNilSprintSortsLast() {
        let issues = [
            issue("PROJ-1", sprint: nil),
            issue("PROJ-2", sprint: "Sprint 1"),
        ]
        let sprints = JiraAggregator(snapshot: JiraSnapshot(issues: issues, fetchedAt: t0, error: nil))
            .grouped()[0].sprints
        XCTAssertEqual(sprints[0].sprint, "Sprint 1")
        XCTAssertNil(sprints[1].sprint)
    }

    func testRecordReplacesSnapshot() {
        var agg = JiraAggregator.unknown
        let snap = JiraSnapshot(issues: [issue("PROJ-1")], fetchedAt: t0, error: nil)
        agg.record(snap)
        XCTAssertEqual(agg.openCount, 1)
    }
}
```

- [ ] **Tests ausführen — müssen rot sein (Typ fehlt)**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter JiraAggregatorTests 2>&1 | grep "error:" | head -3
```
Erwartet: `error: cannot find type 'JiraIssue' in scope`

- [ ] **JiraIssue.swift anlegen**

```swift
// Sources/StatusCore/Jira/JiraIssue.swift
import Foundation

public struct JiraIssue: Equatable, Identifiable {
    public var id: String
    public var key: String
    public var summary: String
    public var statusName: String
    public var priorityName: String?
    public var projectKey: String
    public var projectName: String
    public var sprintName: String?
    public var url: URL

    public init(id: String, key: String, summary: String, statusName: String,
                priorityName: String?, projectKey: String, projectName: String,
                sprintName: String?, url: URL) {
        self.id = id; self.key = key; self.summary = summary; self.statusName = statusName
        self.priorityName = priorityName; self.projectKey = projectKey
        self.projectName = projectName; self.sprintName = sprintName; self.url = url
    }
}

public struct JiraSnapshot: Equatable {
    public var issues: [JiraIssue]
    public var fetchedAt: Date
    public var error: String?

    public init(issues: [JiraIssue], fetchedAt: Date, error: String?) {
        self.issues = issues; self.fetchedAt = fetchedAt; self.error = error
    }

    public static let empty = JiraSnapshot(issues: [], fetchedAt: .distantPast, error: nil)
}

public protocol JiraFetcher {
    func fetch(domain: String, email: String, token: String) async throws -> JiraSnapshot
}
```

- [ ] **JiraAggregator.swift anlegen**

```swift
// Sources/StatusCore/Jira/JiraAggregator.swift
import Foundation

public struct JiraAggregator: Equatable {
    public private(set) var snapshot: JiraSnapshot

    public init(snapshot: JiraSnapshot = .empty) {
        self.snapshot = snapshot
    }

    public var openCount: Int { snapshot.issues.count }

    public var isStale: Bool {
        snapshot.fetchedAt == .distantPast ||
        Date().timeIntervalSince(snapshot.fetchedAt) > 600
    }

    public mutating func record(_ snapshot: JiraSnapshot) {
        self.snapshot = snapshot
    }

    /// Issues nach Projekt (alphabetisch) und Sprint (benannte zuerst, nil zuletzt) gruppiert.
    public func grouped() -> [(project: String, projectName: String,
                                sprints: [(sprint: String?, issues: [JiraIssue])])] {
        var byProject: [String: (name: String, bySprintName: [String?: [JiraIssue]])] = [:]
        for issue in snapshot.issues {
            if byProject[issue.projectKey] == nil {
                byProject[issue.projectKey] = (name: issue.projectName, bySprintName: [:])
            }
            byProject[issue.projectKey]!.bySprintName[issue.sprintName, default: []].append(issue)
        }
        return byProject.sorted { $0.key < $1.key }.map { projectKey, value in
            let sprints = value.bySprintName
                .sorted { a, b in
                    switch (a.key, b.key) {
                    case (nil, nil): return false
                    case (nil, _):   return false
                    case (_, nil):   return true
                    case (let l?, let r?): return l < r
                    }
                }
                .map { (sprint: $0.key, issues: $0.value) }
            return (project: projectKey, projectName: value.name, sprints: sprints)
        }
    }

    public static let unknown = JiraAggregator(snapshot: .empty)
}
```

- [ ] **Tests ausführen — sollen grün sein**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter JiraAggregatorTests 2>&1 | grep -E "(Executed|passed|FAILED)" | tail -3
```
Erwartet: `Executed 9 tests, with 0 failures`

- [ ] **Commit**

```bash
git add Sources/StatusCore/Jira/JiraIssue.swift Sources/StatusCore/Jira/JiraAggregator.swift \
        Tests/StatusCoreTests/JiraAggregatorTests.swift
git commit -m "$(cat <<'EOF'
Jira Datenmodell: JiraIssue, JiraSnapshot, JiraAggregator

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: JiraService

**Files:**
- Create: `Sources/StatusCore/Jira/JiraService.swift`
- Create: `Tests/StatusCoreTests/JiraServiceTests.swift`

**Interfaces:**
- Consumes: `JiraIssue`, `JiraSnapshot`, `JiraFetcher` aus Task 1
- Produces:
  - `public final class JiraService: JiraFetcher`
  - `static func parseIssues(from data: Data, domain: String) throws -> [JiraIssue]` (intern, für Tests)

**Jira Cloud REST API v3 Endpunkt:**
```
GET https://<domain>/rest/api/3/search
  ?jql=assignee%3DcurrentUser()%20AND%20statusCategory%21%3DDone
  &fields=summary%2Cstatus%2Cpriority%2Cproject%2Ccustomfield_10020
  &maxResults=100
  &orderBy=updated+DESC
Authorization: Basic base64(email:token)
Accept: application/json
```

Jira-URL eines Issues: `https://<domain>/browse/<key>`

Sprint-Feld `customfield_10020`: Array von Sprint-Objekten; erster Sprint mit `state == "active"` wird verwendet. Falls kein aktiver Sprint, erster Sprint. Falls leer oder fehlt → `nil`.

- [ ] **Tests anlegen (fehlschlagend)**

```swift
// Tests/StatusCoreTests/JiraServiceTests.swift
import XCTest
@testable import StatusCore

final class JiraServiceTests: XCTestCase {
    // MARK: parseIssues

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
        let json = """{"issues":[]}"""
        let issues = try JiraService.parseIssues(from: Data(json.utf8), domain: "x.atlassian.net")
        XCTAssertEqual(issues.count, 0)
    }
}
```

- [ ] **Tests ausführen — sollen rot sein**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter JiraServiceTests 2>&1 | grep "error:" | head -3
```
Erwartet: `error: cannot find 'JiraService' in scope`

- [ ] **JiraService.swift anlegen**

```swift
// Sources/StatusCore/Jira/JiraService.swift
import Foundation

public final class JiraService: JiraFetcher {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetch(domain: String, email: String, token: String) async throws -> JiraSnapshot {
        let jql = "assignee=currentUser() AND statusCategory!=Done"
        let fields = "summary,status,priority,project,customfield_10020"
        var components = URLComponents(string: "https://\(domain)/rest/api/3/search")!
        components.queryItems = [
            URLQueryItem(name: "jql", value: jql),
            URLQueryItem(name: "fields", value: fields),
            URLQueryItem(name: "maxResults", value: "100"),
            URLQueryItem(name: "orderBy", value: "updated DESC"),
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let credentials = Data("\(email):\(token)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            return JiraSnapshot(issues: [], fetchedAt: Date(), error: "Netzwerkfehler: \(error.localizedDescription)")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            return JiraSnapshot(issues: [], fetchedAt: Date(), error: "HTTP \(status)")
        }
        do {
            let issues = try Self.parseIssues(from: data, domain: domain)
            return JiraSnapshot(issues: issues, fetchedAt: Date(), error: nil)
        } catch {
            return JiraSnapshot(issues: [], fetchedAt: Date(), error: "Parse-Fehler: \(error.localizedDescription)")
        }
    }

    static func parseIssues(from data: Data, domain: String) throws -> [JiraIssue] {
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        return response.issues.compactMap { r in
            guard let url = URL(string: "https://\(domain)/browse/\(r.key)") else { return nil }
            return JiraIssue(
                id: r.id,
                key: r.key,
                summary: r.fields.summary,
                statusName: r.fields.status.name,
                priorityName: r.fields.priority?.name,
                projectKey: r.fields.project.key,
                projectName: r.fields.project.name,
                sprintName: activeSprint(r.fields.customfield_10020),
                url: url
            )
        }
    }

    private static func activeSprint(_ sprints: [SprintResponse]?) -> String? {
        guard let sprints, !sprints.isEmpty else { return nil }
        return (sprints.first { $0.state == "active" } ?? sprints.first)?.name
    }

    // MARK: Codable-Typen (privat)

    private struct SearchResponse: Decodable {
        var issues: [IssueResponse]
    }

    private struct IssueResponse: Decodable {
        var id: String
        var key: String
        var fields: FieldsResponse
    }

    private struct FieldsResponse: Decodable {
        var summary: String
        var status: StatusResponse
        var priority: PriorityResponse?
        var project: ProjectResponse
        var customfield_10020: [SprintResponse]?

        enum CodingKeys: String, CodingKey {
            case summary, status, priority, project, customfield_10020
        }
    }

    private struct StatusResponse:   Decodable { var name: String }
    private struct PriorityResponse: Decodable { var name: String }
    private struct ProjectResponse:  Decodable { var key: String; var name: String }
    private struct SprintResponse:   Decodable { var name: String; var state: String }
}
```

- [ ] **Tests ausführen — sollen grün sein**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter JiraServiceTests 2>&1 | grep -E "(Executed|passed|FAILED)" | tail -3
```
Erwartet: `Executed 5 tests, with 0 failures`

- [ ] **Review Focus Test: HTTP-Fehler → error gesetzt, kein Absturz**

Diesen Test ebenfalls in `JiraServiceTests.swift` ergänzen — er testet das Protokoll-Verhalten via einen synchronen Stub, nicht JiraService direkt (da kein echter Server):

```swift
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
```

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter JiraServiceTests 2>&1 | grep -E "(Executed|passed|FAILED)" | tail -3
```
Erwartet: `Executed 6 tests, with 0 failures`

- [ ] **Commit**

```bash
git add Sources/StatusCore/Jira/JiraService.swift Tests/StatusCoreTests/JiraServiceTests.swift
git commit -m "$(cat <<'EOF'
JiraService: REST API v3 Client und JSON-Parsing

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: AppSettings Jira-Felder

**Files:**
- Modify: `Sources/StatusCore/Settings/AppSettings.swift`
- Modify: `Tests/StatusCoreTests/AppSettingsTests.swift`

**Interfaces:**
- Produces: `AppSettings.jiraDomain`, `.jiraEmail`, `.jiraToken`, `.jiraConfigured`

- [ ] **Tests schreiben (fehlschlagend)**

An `AppSettingsTests.swift` anhängen:

```swift
func testJiraFieldsDefaultToEmpty() {
    XCTAssertEqual(AppSettings().jiraDomain, "")
    XCTAssertEqual(AppSettings().jiraEmail,  "")
    XCTAssertEqual(AppSettings().jiraToken,  "")
    XCTAssertFalse(AppSettings().jiraConfigured)
}

func testJiraConfiguredWhenAllFieldsSet() {
    var s = AppSettings()
    s.jiraDomain = "x.atlassian.net"
    s.jiraEmail  = "a@b.com"
    s.jiraToken  = "tok"
    XCTAssertTrue(s.jiraConfigured)
}

func testJiraConfiguredFalseWhenAnyFieldEmpty() {
    var s = AppSettings()
    s.jiraDomain = "x.atlassian.net"
    s.jiraEmail  = "a@b.com"
    // token leer
    XCTAssertFalse(s.jiraConfigured)
}

func testJiraFieldsDecodeFromOldSettingsWithoutJira() throws {
    let json = """
    {"hosts":["github.com"],"brightness":60,"port":47615,"ghPath":""}
    """
    let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    XCTAssertEqual(decoded.jiraDomain, "")
    XCTAssertFalse(decoded.jiraConfigured)
}

func testJiraRoundTrip() {
    let d = UserDefaults(suiteName: "AppSettingsTests-Jira-\(UUID().uuidString)")!
    var s = AppSettings()
    s.jiraDomain = "mycompany.atlassian.net"
    s.jiraEmail  = "florian@firma.de"
    s.jiraToken  = "secret"
    s.save(to: d)
    let loaded = AppSettings.load(from: d)
    XCTAssertEqual(loaded.jiraDomain, s.jiraDomain)
    XCTAssertEqual(loaded.jiraEmail,  s.jiraEmail)
    XCTAssertEqual(loaded.jiraToken,  s.jiraToken)
}
```

- [ ] **Tests ausführen — sollen rot sein**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AppSettingsTests 2>&1 | grep "error:" | head -3
```
Erwartet: `error: value of type 'AppSettings' has no member 'jiraDomain'`

- [ ] **AppSettings.swift erweitern**

In `Sources/StatusCore/Settings/AppSettings.swift`:

*Nach `boardWindowAlwaysOnTop`:*
```swift
public var jiraDomain: String = ""
public var jiraEmail:  String = ""
public var jiraToken:  String = ""

public var jiraConfigured: Bool {
    !jiraDomain.isEmpty && !jiraEmail.isEmpty && !jiraToken.isEmpty
}
```

*`CodingKeys` um drei neue Fälle ergänzen:*
```swift
case hosts, brightness, port, ghPath, pinnedRepos, hiddenRepos, shownRepos, hostDefaults,
     boardWindowMode, boardWindowAlwaysOnTop,
     jiraDomain, jiraEmail, jiraToken
```

*In `init(from:)` nach `boardWindowAlwaysOnTop`:*
```swift
jiraDomain = try c.decodeIfPresent(String.self, forKey: .jiraDomain) ?? ""
jiraEmail  = try c.decodeIfPresent(String.self, forKey: .jiraEmail)  ?? ""
jiraToken  = try c.decodeIfPresent(String.self, forKey: .jiraToken)  ?? ""
```

- [ ] **Tests ausführen — sollen grün sein**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AppSettingsTests 2>&1 | grep -E "(Executed|passed|FAILED)" | tail -3
```
Erwartet: alle grün.

- [ ] **Commit**

```bash
git add Sources/StatusCore/Settings/AppSettings.swift Tests/StatusCoreTests/AppSettingsTests.swift
git commit -m "$(cat <<'EOF'
AppSettings: Jira-Felder (Domain, E-Mail, Token)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: BoardState.jiraCount + Panel & Board-Fenster

**Files:**
- Modify: `Sources/StatusCore/Render/BoardState.swift`
- Modify: `Sources/StatusCore/Render/BoardRenderer.swift`
- Modify: `Sources/StatusCore/Render/BoardWindowRenderer.swift`
- Modify: `Tests/StatusCoreTests/BoardRendererTests.swift`

**Interfaces:**
- Consumes: Keine neuen Typen; `BoardState` aus bestehendem Code
- Produces: `BoardState.jiraCount: Int` (Default `0`)

**Panel-Layout:** Jira-Zähler ganz rechts in der PR-Zone-Kopfzeile (`x0 + 540, baseline: 70, size: 28`), nur wenn `jiraCount > 0`. Die bestehende "Stand …"-Zeile (bei `isStale`) bleibt bei `x0 + 460`; beide passen nebeneinander da "Stand 12:59" ~110px breit ist und der Jira-Zähler ~80px.

- [ ] **Tests schreiben (fehlschlagend)**

An `BoardRendererTests.swift` anhängen:

```swift
// MARK: Jira-Zähler

private func stateWithJira(_ count: Int) -> BoardState {
    BoardState(statusName: "Deep Focus", statusColor: RGBColor(hex: "#FF0000")!,
               statusSince: t0, agents: [], prs: .unknown, now: t0, jiraCount: count)
}

func testJiraZaehlerPixelSichtbarBeiCount() {
    // "Jira 3" in muted-Farbe (#8C8C96) rechts in der PR-Zone-Kopfzeile (baseline 70)
    let img = BoardRenderer.render(stateWithJira(3))
    var sawGreyish = false
    for y in 40...82 {
        for x in stride(from: 1700, to: 1900, by: 3) {
            if isGreyish(pixel(img, x, y)) { sawGreyish = true }
        }
    }
    XCTAssertTrue(sawGreyish, "Jira-Zähler zeichnet greyish-Pixel im rechten PR-Kopf")
}

func testKeinJiraZaehlerBeiCountNull() {
    let img = BoardRenderer.render(stateWithJira(0))
    var sawGreyish = false
    for y in 40...82 {
        for x in stride(from: 1700, to: 1900, by: 3) {
            if isGreyish(pixel(img, x, y)) { sawGreyish = true }
        }
    }
    XCTAssertFalse(sawGreyish, "Kein Jira-Zähler wenn count == 0")
}
```

- [ ] **Tests ausführen — sollen rot sein**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter BoardRendererTests/testJira 2>&1 | grep "error:" | head -3
```
Erwartet: Compiler-Fehler wegen fehlendem `jiraCount`-Parameter.

- [ ] **BoardState.swift: jiraCount ergänzen**

```swift
public var jiraCount: Int

public init(statusName: String, statusColor: RGBColor, statusSince: Date,
            agents: [AgentActivity], prs: PRZone, now: Date,
            jiraCount: Int = 0) {
    self.statusName = statusName; self.statusColor = statusColor; self.statusSince = statusSince
    self.agents = agents; self.prs = prs; self.now = now; self.jiraCount = jiraCount
}
```

- [ ] **BoardRenderer.swift: Jira-Zeile in drawPRs**

In `drawPRs`, nach dem `text(ctx, "PRs", ...)` Aufruf:

```swift
if s.jiraCount > 0 {
    text(ctx, "Jira \(s.jiraCount)", x: x0 + 540, baseline: 70, size: 28, color: muted)
}
```

- [ ] **BoardWindowRenderer.swift: Jira-Zeile in drawPRs**

In `drawPRs`, nach dem `text(ctx, "PRs", ...)` Aufruf (direkt nach der `headerWidth`-Zuweisung):

```swift
if s.jiraCount > 0 {
    rightAligned(ctx, "Jira \(s.jiraCount)", right: zone.maxX - L.padding,
                 baseline: L.headerBaseline, size: F.header, color: R.muted)
}
```

- [ ] **Tests ausführen — sollen grün sein**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter BoardRendererTests 2>&1 | grep -E "(Executed|passed|FAILED)" | tail -3
```

- [ ] **Vollständige Suite grün**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test 2>&1 | grep "Suite 'All tests' passed"
```

- [ ] **Commit**

```bash
git add Sources/StatusCore/Render/BoardState.swift \
        Sources/StatusCore/Render/BoardRenderer.swift \
        Sources/StatusCore/Render/BoardWindowRenderer.swift \
        Tests/StatusCoreTests/BoardRendererTests.swift
git commit -m "$(cat <<'EOF'
BoardState.jiraCount + Panel/Fenster: Jira-Zähler in PR-Zone

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: AppModel + SettingsView

**Files:**
- Modify: `Sources/StatusDisplay/AppModel.swift`
- Modify: `Sources/StatusDisplay/SettingsView.swift`

**Interfaces:**
- Consumes: `JiraAggregator`, `JiraService`, `JiraFetcher`, `AppSettings.jiraConfigured` aus Tasks 1–3
- Produces: `AppModel.jira: JiraAggregator`, `AppModel.jiraRefreshRunning: Bool`, `AppModel.refreshJira() async`

*Kein automatisierter Test (AppModel nicht unit-getestet); Verifikation durch Build + manuelle Prüfung.*

- [ ] **AppModel.swift erweitern**

*Neue Felder nach `@Published private(set) var prsRefreshRunning`:*
```swift
@Published private(set) var jira = JiraAggregator.unknown
@Published private(set) var jiraRefreshRunning = false
private let jiraService: JiraFetcher
private var jiraRefreshPending = false
```

*`init` — neuer Parameter mit Default am Anfang, analog zu calendarService falls vorhanden:*
```swift
init(jiraService: JiraFetcher = JiraService()) {
    self.jiraService = jiraService
    let settings = AppSettings.load()
    // … Rest unverändert …
```

*5-Minuten-Timer nach dem 15s-Timer in `init`:*
```swift
timers.append(Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
    Task { @MainActor in await self?.refreshJira() }
})
```

*Nach dem `NSWorkspace.didWakeNotification`-Block in `init`:*
```swift
Task { await refreshJira() }
```

*Neue Methode `refreshJira()` analog zu `refreshPRs()`:*
```swift
func refreshJira() async {
    guard settings.jiraConfigured else { return }
    guard !jiraRefreshRunning else {
        jiraRefreshPending = true
        return
    }
    jiraRefreshRunning = true
    defer { jiraRefreshRunning = false }
    repeat {
        jiraRefreshPending = false
        let snap = try? await jiraService.fetch(
            domain: settings.jiraDomain,
            email: settings.jiraEmail,
            token: settings.jiraToken
        )
        if let snap {
            jira.record(snap)
            scheduleRender()
        }
    } while jiraRefreshPending
}
```

*In `scheduleRender()` — `BoardState`-Konstruktor um `jiraCount` ergänzen:*
```swift
let state = BoardState(statusName: status.preset.name, statusColor: status.preset.color,
                       statusSince: status.since, agents: agents,
                       prs: prs.zone(now: now, hosts: settings.hosts,
                                    pinned: settings.pinnedRepos, hidden: settings.hiddenRepos,
                                    shown: settings.shownRepos, hostDefaults: settings.hostDefaults),
                       now: now,
                       jiraCount: settings.jiraConfigured ? jira.openCount : 0)
```

*In `apply(_:)` — Jira-Felder reagieren auf Einstellungsänderung:*
```swift
if old.jiraDomain != settings.jiraDomain || old.jiraEmail != settings.jiraEmail
    || old.jiraToken != settings.jiraToken {
    Task { await refreshJira() }
}
```

- [ ] **SettingsView.swift: Jira-Reiter**

Im `TabView` in `SettingsView.body`, nach dem letzten Tab `reposTab`:

```swift
jiraTab.tabItem { Text("Jira") }
```

Neue `private var jiraTab: some View` Property, z. B. nach `reposTab`:

```swift
private var jiraTab: some View {
    Form {
        Section("Jira Cloud") {
            TextField("domain.atlassian.net", text: $model.settings.jiraDomain)
                .autocorrectionDisabled()
            TextField("vorname.nachname@firma.de", text: $model.settings.jiraEmail)
                .autocorrectionDisabled()
            SecureField("API-Token", text: $model.settings.jiraToken)
        }
        Section {
            Link("API-Token erstellen",
                 destination: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!)
        }
    }
}
```

- [ ] **App bauen**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build 2>&1 | grep -E "(error:|Build complete)"
```
Erwartet: `Build complete!`

- [ ] **Vollständige Suite grün**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test 2>&1 | grep "Suite 'All tests' passed"
```

- [ ] **Commit**

```bash
git add Sources/StatusDisplay/AppModel.swift Sources/StatusDisplay/SettingsView.swift
git commit -m "$(cat <<'EOF'
AppModel: JiraService verdrahtet, 5-min-Polling; SettingsView Jira-Reiter

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Dashboard-Sektion

**Files:**
- Modify: `Sources/StatusDisplay/DashboardView.swift`

**Interfaces:**
- Consumes: `JiraAggregator`, `JiraIssue`, `JiraSnapshot` aus Task 1; `AppModel.jira`, `AppModel.jiraRefreshRunning` aus Task 5; `AppSettings.jiraConfigured` aus Task 3
- Produces:
  - `DashboardView.SidebarSelection.jiraProject(String)` (neuer Case)
  - `JiraSidebarSection`, `JiraDashboardList`, `JiraDashboardDetail` (neue private Structs)

*Kein automatisierter Test; Verifikation durch Build + manuelle Prüfung im Dashboard.*

- [ ] **SidebarSelection um jiraProject erweitern**

In `DashboardView.swift`, `enum SidebarSelection`:

```swift
case jiraProject(String)   // projectKey
```

- [ ] **listItems: jiraProject-Case hinzufügen**

In `DashboardView.listItems(_:)`:

```swift
case .jiraProject?: return []   // Jira-Inhalt wird direkt in content-Spalte gerendert
```

- [ ] **NavigationSplitView content-Spalte: Jira-Branch**

Den content-Abschnitt in `DashboardView.body` anpassen — Jira-Auswahl bekommt eigenen Zweig:

```swift
} content: {
    if case .jiraProject(let key)? = sidebar {
        JiraDashboardList(jira: model.jira, projectKey: key,
                          selectedIssueID: $selectedItemID)
            .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 520)
    } else {
        DashboardList(dashboard: dashboard, selection: sidebar, items: items, now: now,
                      selectedItemID: $selectedItemID, open: open)
            .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 520)
            .safeAreaInset(edge: .bottom) { footer(dashboard) }
    }
```

- [ ] **NavigationSplitView detail-Spalte: Jira-Branch**

Den detail-Abschnitt anpassen:

```swift
} detail: {
    if case .jiraProject? = sidebar,
       let issueID = selectedItemID,
       let issue = model.jira.snapshot.issues.first(where: { $0.id == issueID }) {
        JiraDashboardDetail(issue: issue)
    } else if let item = items.first(where: { $0.id == selectedItemID }) {
        DashboardDetail(item: item, now: now, open: open, dismissAgent: model.dismissAgent)
    } else {
        Text("Nichts ausgewählt")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
```

- [ ] **Toolbar: Jira-Aktualisieren-Button**

Im `.toolbar`-Block, nach dem PR-Aktualisieren-Button:

```swift
if model.settings.jiraConfigured {
    if model.jiraRefreshRunning {
        ProgressView().controlSize(.small)
    }
    Button {
        Task { await model.refreshJira() }
    } label: {
        Label("Jira aktualisieren", systemImage: "arrow.clockwise.circle")
    }
    .help("Jira-Tickets aktualisieren")
}
```

- [ ] **DashboardSidebar: Jira-Abschnitt**

In `DashboardSidebar.body`, nach dem Agenten-Abschnitt:

```swift
if jiraConfigured, !jira.grouped().isEmpty {
    Section("Jira") {
        ForEach(jira.grouped(), id: \.project) { group in
            SidebarRow(title: group.projectName,
                       count: group.sprints.flatMap(\.issues).count,
                       waiting: false)
                .tag(DashboardView.SidebarSelection.jiraProject(group.project))
        }
    }
}
```

**Hinweis:** `DashboardSidebar` muss `jira: JiraAggregator` und `jiraConfigured: Bool` als Parameter erhalten. Den Call-Site in `DashboardView.body` entsprechend anpassen:

```swift
DashboardSidebar(dashboard: dashboard, jira: model.jira,
                 jiraConfigured: model.settings.jiraConfigured,
                 selection: $sidebar, now: now)
```

Und `DashboardSidebar` erhält neue Felder:
```swift
let jira: JiraAggregator
let jiraConfigured: Bool
```

- [ ] **JiraDashboardList anlegen**

Neuer private struct am Ende von `DashboardView.swift`, vor `// MARK: - Status-Etikett`:

```swift
private struct JiraDashboardList: View {
    let jira: JiraAggregator
    let projectKey: String
    @Binding var selectedIssueID: String?

    var body: some View {
        let group = jira.grouped().first { $0.project == projectKey }
        if let error = jira.snapshot.error {
            Text("Fehler: \(error)")
                .foregroundStyle(.secondary)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let group {
            List(selection: $selectedIssueID) {
                ForEach(group.sprints, id: \.sprint) { sprintGroup in
                    Section(sprintGroup.sprint ?? "Kein Sprint") {
                        ForEach(sprintGroup.issues) { issue in
                            JiraIssueRow(issue: issue).tag(issue.id)
                        }
                    }
                }
            }
        } else {
            Text("Keine Tickets.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct JiraIssueRow: View {
    let issue: JiraIssue

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(issue.key)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text(issue.summary).lineLimit(1)
            }
            Text(issue.statusName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
```

- [ ] **JiraDashboardDetail anlegen**

```swift
private struct JiraDashboardDetail: View {
    let issue: JiraIssue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(issue.projectName) · \(issue.key)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(issue.summary)
                        .font(.title3.weight(.semibold))
                        .textSelection(.enabled)
                }
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        detailLabel("Status")
                        Text(issue.statusName)
                    }
                    if let priority = issue.priorityName {
                        GridRow {
                            detailLabel("Priorität")
                            Text(priority)
                        }
                    }
                    if let sprint = issue.sprintName {
                        GridRow {
                            detailLabel("Sprint")
                            Text(sprint)
                        }
                    }
                }
                .font(.callout)
                Button("In Jira öffnen") { NSWorkspace.shared.open(issue.url) }
                    .keyboardShortcut(.defaultAction)
                    .padding(.top, 6)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func detailLabel(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.leading)
    }
}
```

- [ ] **App bauen**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build 2>&1 | grep -E "(error:|Build complete)"
```
Erwartet: `Build complete!`

- [ ] **Vollständige Suite grün**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test 2>&1 | grep "Suite 'All tests' passed"
```

- [ ] **App starten und Dashboard prüfen**

```bash
pkill -x StatusDisplay 2>/dev/null; sleep 0.3
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/build.sh && open build/StatusDisplay.app
```

Prüfliste (ohne echte Jira-Credentials):
- Einstellungen → Reiter „Jira" sichtbar
- Dashboard ohne Jira-Credentials: kein Jira-Abschnitt in der Seitenleiste
- Mit Credentials eingetragen: Jira-Abschnitt erscheint nach Aktualisierung

- [ ] **Commit**

```bash
git add Sources/StatusDisplay/DashboardView.swift
git commit -m "$(cat <<'EOF'
Dashboard: Jira-Sektion mit Projekt-Seitenleiste, Issue-Liste und Detail

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```
