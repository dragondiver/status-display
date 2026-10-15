import Foundation

public struct JiraAggregator: Equatable {
    public private(set) var snapshots: [String: JiraSnapshot]

    public init(snapshots: [String: JiraSnapshot] = [:]) {
        self.snapshots = snapshots
    }

    public var openCount: Int { snapshots.values.reduce(0) { $0 + $1.issues.count } }

    public var allIssues: [JiraIssue] { snapshots.values.flatMap(\.issues) }

    /// true wenn keine Snapshots vorhanden oder mindestens einer älter als 10 Minuten.
    public var isStale: Bool {
        guard !snapshots.isEmpty else { return true }
        return snapshots.values.contains {
            $0.fetchedAt == .distantPast || Date().timeIntervalSince($0.fetchedAt) > 600
        }
    }

    public mutating func record(_ snapshot: JiraSnapshot, for domain: String) {
        snapshots[domain] = snapshot
    }

    /// Setzt einen Fehler auf dem vorhandenen Snapshot ohne die Issues zu löschen.
    /// Netzwerkfehler sollen geladene Tickets nicht verschwinden lassen.
    public mutating func recordError(_ error: String, for domain: String) {
        if var existing = snapshots[domain] {
            existing.error = error
            snapshots[domain] = existing
        } else {
            snapshots[domain] = JiraSnapshot(issues: [], fetchedAt: .distantPast, error: error)
        }
    }

    /// Behält nur die Snapshots der übergebenen (konfigurierten) Server. Auch ein Abruf, der beim
    /// Entfernen eines Servers noch lief, trägt dessen Tickets danach nicht dauerhaft wieder ein.
    public mutating func retain(domains: Set<String>) {
        snapshots = snapshots.filter { domains.contains($0.key) }
    }

    /// Fehler aller Server als „domain: Fehler“, nach Domain sortiert – eindeutig auch dann,
    /// wenn zwei Server denselben Fehler melden.
    public var errorLines: [String] {
        snapshots.compactMap { domain, snapshot in snapshot.error.map { "\(domain): \($0)" } }.sorted()
    }

    /// Issues aller Server nach Projekt (alphabetisch) und Sprint (benannte zuerst, nil zuletzt) gruppiert.
    public func grouped() -> [(project: String, projectName: String,
                                sprints: [(sprint: String?, issues: [JiraIssue])])] {
        var byProject: [String: (name: String, bySprintName: [String?: [JiraIssue]])] = [:]
        for issue in allIssues {
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

    public static let unknown = JiraAggregator(snapshots: [:])
}
