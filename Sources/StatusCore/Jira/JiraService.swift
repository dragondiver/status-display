import Foundation

public final class JiraService: JiraFetcher {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public static func normalizedDomain(_ domain: String) -> String {
        var d = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if d.hasPrefix("https://") { d.removeFirst(8) }
        else if d.hasPrefix("http://")  { d.removeFirst(7) }
        while d.hasSuffix("/") { d.removeLast() }
        return d
    }

    public func fetch(domain: String, email: String, token: String) async throws -> JiraSnapshot {
        let domain = Self.normalizedDomain(domain)
        let jql = "assignee=currentUser() AND statusCategory!=Done"
        let fields = "summary,status,priority,project,customfield_10020"
        guard var components = URLComponents(string: "https://\(domain)/rest/api/3/search/jql") else {
            return JiraSnapshot(issues: [], fetchedAt: Date(),
                                error: "Ungültige Domain: \(domain)")
        }
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
            return JiraSnapshot(issues: [], fetchedAt: Date(),
                                error: "Netzwerkfehler: \(error.localizedDescription)")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            return JiraSnapshot(issues: [], fetchedAt: Date(), error: "HTTP \(status)")
        }
        do {
            let issues = try Self.parseIssues(from: data, domain: domain)
            return JiraSnapshot(issues: issues, fetchedAt: Date(), error: nil)
        } catch {
            return JiraSnapshot(issues: [], fetchedAt: Date(),
                                error: "Parse-Fehler: \(error.localizedDescription)")
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
                serverDomain: domain,
                url: url
            )
        }
    }

    private static func activeSprint(_ sprints: [SprintResponse]?) -> String? {
        guard let sprints, !sprints.isEmpty else { return nil }
        return (sprints.first { $0.state == "active" } ?? sprints.first)?.name
    }

    // MARK: Codable

    private struct SearchResponse: Decodable { var issues: [IssueResponse] }

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
