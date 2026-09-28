import Foundation

/// Baut die GraphQL-Abfrage für die Repo-Liste eines Hosts (Einstellungs-Reiter „Repos“, #15)
/// und parst eine einzelne Seite der Antwort. Archivierte Repos werden hier bereits weggelassen.
public enum RepoCatalogAPI {
    public static let pageSize = 100

    public static let query = """
    query($cursor: String) {
      viewer {
        repositories(first: \(pageSize), after: $cursor, affiliations: [OWNER, COLLABORATOR, ORGANIZATION_MEMBER], ownerAffiliations: [OWNER, COLLABORATOR, ORGANIZATION_MEMBER], orderBy: {field: NAME, direction: ASC}) {
          nodes { nameWithOwner isArchived }
          pageInfo { hasNextPage endCursor }
        }
      }
    }
    """

    public struct Page: Equatable {
        public let repos: [String]
        public let hasNextPage: Bool
        public let endCursor: String?
    }

    public static func requestBody(cursor: String?) -> Data {
        var variables: [String: Any] = [:]
        if let cursor { variables["cursor"] = cursor }
        return try! JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
    }

    public static func parse(_ data: Data) throws -> Page {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { throw GitHubError.decoding }
        guard let d = response.data else {
            throw GitHubError.graphql(response.errors?.first?.message ?? "keine Daten")
        }
        let repos = d.viewer.repositories.nodes.compactMap { node -> String? in
            guard let node, node.isArchived != true, let name = node.nameWithOwner else { return nil }
            return name
        }
        return Page(repos: repos, hasNextPage: d.viewer.repositories.pageInfo.hasNextPage,
                   endCursor: d.viewer.repositories.pageInfo.endCursor)
    }

    private struct Response: Decodable { let data: DataField?; let errors: [GQLError]? }
    private struct GQLError: Decodable { let message: String }
    private struct DataField: Decodable { let viewer: Viewer }
    private struct Viewer: Decodable { let repositories: Repositories }
    private struct Repositories: Decodable { let nodes: [Node?]; let pageInfo: PageInfo }
    private struct Node: Decodable { let nameWithOwner: String?; let isArchived: Bool? }
    private struct PageInfo: Decodable { let hasNextPage: Bool; let endCursor: String? }
}

/// Lädt die vollständige Repo-Liste eines Hosts, seitenweise. In Firmenaccounts sind es Hunderte
/// Repos, daher ist Paginierung Pflicht; `maxPages` ist eine Obergrenze (5000 Repos) als Schutz
/// gegen einen Account mit extrem vielen Repos oder eine kaputte Server-Antwort, die `hasNextPage`
/// nie auf `false` setzt.
public struct RepoCatalogService {
    public static let maxPages = 50

    private let tokens: TokenProviding
    private let session: URLSession

    public init(tokens: TokenProviding, session: URLSession = .shared) {
        self.tokens = tokens
        self.session = session
    }

    public func fetch(host: String) async throws -> [String] {
        // Wie PRService.fetch: GitHubAPI.graphqlURL erzwingt seine URL, also vorher prüfen.
        guard host == "github.com" || URL(string: "https://\(host)/api/graphql") != nil else {
            throw GitHubError.graphql("ungültiger Host")
        }
        let tokens = self.tokens
        let token = try await Task.detached {
            try tokens.token(for: host)
        }.value

        var all: [String] = []
        var cursor: String?
        var pageCount = 0
        repeat {
            pageCount += 1
            guard pageCount <= Self.maxPages else { break }
            var request = URLRequest(url: GitHubAPI.graphqlURL(host: host), timeoutInterval: 20)
            request.httpMethod = "POST"
            request.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = RepoCatalogAPI.requestBody(cursor: cursor)
            let data: Data, response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                throw GitHubError.http(0)
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { throw GitHubError.http(status) }
            let page = try RepoCatalogAPI.parse(data)
            all.append(contentsOf: page.repos)
            cursor = page.hasNextPage ? page.endCursor : nil
        } while cursor != nil
        return all
    }
}
