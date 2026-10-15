import Foundation

public struct JiraIssue: Equatable, Identifiable {
    public let jiraId: String       // interne Jira-ID, z. B. "10001"
    public var key: String          // "PROJ-42"
    public var summary: String
    public var statusName: String
    public var priorityName: String?
    public var projectKey: String
    public var projectName: String
    public var sprintName: String?
    public var serverDomain: String  // normalisierte Domain, z. B. "myco.atlassian.net"
    public var url: URL

    /// Eindeutig über alle Server hinweg: `"domain/jiraId"`.
    public var id: String { "\(serverDomain)/\(jiraId)" }

    public init(id jiraId: String, key: String, summary: String, statusName: String,
                priorityName: String?, projectKey: String, projectName: String,
                sprintName: String?, serverDomain: String, url: URL) {
        self.jiraId = jiraId; self.key = key; self.summary = summary
        self.statusName = statusName; self.priorityName = priorityName
        self.projectKey = projectKey; self.projectName = projectName
        self.sprintName = sprintName; self.serverDomain = serverDomain; self.url = url
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
