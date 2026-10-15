import XCTest
@testable import StatusCore

final class JiraAggregatorTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func issue(_ key: String, project: String = "PROJ", projectName: String = "Projekt",
                       sprint: String? = "Sprint 1", server: String = "x.atlassian.net") -> JiraIssue {
        JiraIssue(id: key, key: key, summary: "Fix \(key)", statusName: "To Do",
                  priorityName: nil, projectKey: project, projectName: projectName,
                  sprintName: sprint, serverDomain: server,
                  url: URL(string: "https://\(server)/browse/\(key)")!)
    }

    private func snap(_ issues: [JiraIssue], error: String? = nil) -> JiraSnapshot {
        JiraSnapshot(issues: issues, fetchedAt: t0, error: error)
    }

    // MARK: openCount

    func testOpenCountSumsAcrossServers() {
        let agg = JiraAggregator(snapshots: [
            "a.atlassian.net": snap([issue("A-1"), issue("A-2")]),
            "b.atlassian.net": snap([issue("B-1")]),
        ])
        XCTAssertEqual(agg.openCount, 3)
    }

    func testOpenCountZeroWhenEmpty() {
        XCTAssertEqual(JiraAggregator.unknown.openCount, 0)
    }

    // MARK: isStale

    func testIsStaleWhenEmpty() {
        XCTAssertTrue(JiraAggregator.unknown.isStale)
    }

    func testIsStaleIfAnySnapshotIsStale() {
        let old = Date(timeIntervalSinceNow: -601)
        let agg = JiraAggregator(snapshots: [
            "a.atlassian.net": JiraSnapshot(issues: [], fetchedAt: Date(), error: nil),
            "b.atlassian.net": JiraSnapshot(issues: [], fetchedAt: old, error: nil),
        ])
        XCTAssertTrue(agg.isStale)
    }

    func testNotStaleWhenAllFresh() {
        let agg = JiraAggregator(snapshots: [
            "a.atlassian.net": JiraSnapshot(issues: [], fetchedAt: Date(), error: nil),
        ])
        XCTAssertFalse(agg.isStale)
    }

    // MARK: record

    func testRecordAddsSnapshot() {
        var agg = JiraAggregator.unknown
        agg.record(snap([issue("A-1")]), for: "a.atlassian.net")
        XCTAssertEqual(agg.openCount, 1)
    }

    func testRecordReplacesExistingSnapshot() {
        var agg = JiraAggregator(snapshots: ["a.atlassian.net": snap([issue("A-1"), issue("A-2")])])
        agg.record(snap([issue("A-3")]), for: "a.atlassian.net")
        XCTAssertEqual(agg.openCount, 1)
    }

    // MARK: grouped

    func testGroupedMergesAcrossServers() {
        let agg = JiraAggregator(snapshots: [
            "a.atlassian.net": snap([issue("A-1", project: "PROJ", projectName: "Projekt A")]),
            "b.atlassian.net": snap([issue("B-1", project: "OTHER", projectName: "Projekt B")]),
        ])
        let grouped = agg.grouped()
        XCTAssertEqual(grouped.count, 2)
        let projects = grouped.map(\.project).sorted()
        XCTAssertEqual(projects, ["OTHER", "PROJ"])
    }

    func testGroupedByProjectAndSprint() {
        let issues = [
            issue("PROJ-1", project: "PROJ", projectName: "Projekt A", sprint: "Sprint 1"),
            issue("PROJ-2", project: "PROJ", projectName: "Projekt A", sprint: "Sprint 1"),
            issue("OTHER-1", project: "OTHER", projectName: "Projekt B", sprint: nil),
        ]
        let grouped = JiraAggregator(snapshots: ["x.atlassian.net": snap(issues)]).grouped()
        XCTAssertEqual(grouped.count, 2)
        XCTAssertEqual(grouped[0].project, "OTHER")   // alphabetisch
        XCTAssertEqual(grouped[1].project, "PROJ")
        XCTAssertEqual(grouped[1].sprints[0].sprint, "Sprint 1")
        XCTAssertEqual(grouped[1].sprints[0].issues.count, 2)
    }

    func testNilSprintSortsLast() {
        let issues = [issue("PROJ-1", sprint: nil), issue("PROJ-2", sprint: "Sprint 1")]
        let sprints = JiraAggregator(snapshots: ["x.atlassian.net": snap(issues)]).grouped()[0].sprints
        XCTAssertEqual(sprints[0].sprint, "Sprint 1")
        XCTAssertNil(sprints[1].sprint)
    }

    // MARK: remove

    func testRecordErrorBehältIssuesBeiNetzausfall() {
        var agg = JiraAggregator(snapshots: ["a.atlassian.net": snap([issue("A-1")])])
        agg.recordError("Netzwerkfehler", for: "a.atlassian.net")
        // Issues bleiben erhalten
        XCTAssertEqual(agg.openCount, 1)
        // Fehler ist gesetzt
        XCTAssertEqual(agg.snapshots["a.atlassian.net"]?.error, "Netzwerkfehler")
    }

    func testRetainBehältNurKonfigurierteServer() {
        var agg = JiraAggregator(snapshots: [
            "a.atlassian.net": snap([issue("A-1")]),
            "b.atlassian.net": snap([issue("B-1")]),
        ])
        agg.retain(domains: ["b.atlassian.net"])
        XCTAssertEqual(agg.openCount, 1)
        XCTAssertNil(agg.snapshots["a.atlassian.net"])
    }

    func testRetainOhneServerLeertAlles() {
        var agg = JiraAggregator(snapshots: ["a.atlassian.net": snap([issue("A-1")])])
        agg.retain(domains: [])
        XCTAssertTrue(agg.snapshots.isEmpty)
    }

    // MARK: Fehlerzeilen

    func testErrorLinesNennenDomainUndSindEindeutig() {
        var agg = JiraAggregator(snapshots: ["c.atlassian.net": snap([issue("C-1")])])
        agg.recordError("HTTP 401", for: "b.atlassian.net")
        agg.recordError("HTTP 401", for: "a.atlassian.net")
        XCTAssertEqual(agg.errorLines, ["a.atlassian.net: HTTP 401", "b.atlassian.net: HTTP 401"])
    }

    // MARK: ID-Eindeutigkeit

    func testIssueIdEnthältServerDomain() {
        let i = JiraIssue(id: "10001", key: "P-1", summary: "x", statusName: "To Do",
                          priorityName: nil, projectKey: "P", projectName: "P",
                          sprintName: nil, serverDomain: "a.atlassian.net",
                          url: URL(string: "https://a.atlassian.net/browse/P-1")!)
        XCTAssertEqual(i.id, "a.atlassian.net/10001")
    }

    func testKeineIDKollisionZweiServern() {
        let snap1 = JiraSnapshot(
            issues: [JiraIssue(id: "10001", key: "P-1", summary: "A", statusName: "To Do",
                               priorityName: nil, projectKey: "P", projectName: "P",
                               sprintName: nil, serverDomain: "a.atlassian.net",
                               url: URL(string: "https://a.atlassian.net/browse/P-1")!)],
            fetchedAt: t0, error: nil)
        let snap2 = JiraSnapshot(
            issues: [JiraIssue(id: "10001", key: "P-1", summary: "B", statusName: "To Do",
                               priorityName: nil, projectKey: "P", projectName: "P",
                               sprintName: nil, serverDomain: "b.atlassian.net",
                               url: URL(string: "https://b.atlassian.net/browse/P-1")!)],
            fetchedAt: t0, error: nil)
        let agg = JiraAggregator(snapshots: ["a.atlassian.net": snap1, "b.atlassian.net": snap2])
        let ids = agg.allIssues.map(\.id)
        XCTAssertEqual(Set(ids).count, 2, "IDs müssen eindeutig sein")
    }

    // MARK: allIssues

    func testAllIssuesMergesServers() {
        let agg = JiraAggregator(snapshots: [
            "a.atlassian.net": snap([issue("A-1")]),
            "b.atlassian.net": snap([issue("B-1"), issue("B-2")]),
        ])
        XCTAssertEqual(agg.allIssues.count, 3)
    }
}
