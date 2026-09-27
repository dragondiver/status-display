import Foundation

public enum GitHubAPI {
    public static func graphqlURL(host: String) -> URL {
        host == "github.com"
            ? URL(string: "https://api.github.com/graphql")!
            : URL(string: "https://\(host)/api/graphql")!
    }

    public static let query = """
    query {
      review: search(query: "is:open is:pr archived:false review-requested:@me", type: ISSUE, first: 50) { nodes { ...pr } }
      mine: search(query: "is:open is:pr archived:false author:@me", type: ISSUE, first: 50) { nodes { ...pr } }
    }
    fragment pr on PullRequest {
      number title url repository { nameWithOwner }
      commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
    }
    """

    public static func requestBody() -> Data {
        try! JSONSerialization.data(withJSONObject: ["query": query])
    }

    public static func parse(_ data: Data, host: String, at date: Date) throws -> PRSnapshot {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { throw GitHubError.decoding }
        guard let d = response.data else {
            throw GitHubError.graphql(response.errors?.first?.message ?? "keine Daten")
        }
        return PRSnapshot(host: host, toReview: d.review.nodes.compactMap(pull), mine: d.mine.nodes.compactMap(pull),
                          fetchedAt: date, warning: response.errors?.first?.message)
    }

    private static func pull(_ node: Node?) -> PullRequest? {
        guard let n = node, let number = n.number, let title = n.title,
              let urlString = n.url, let url = URL(string: urlString) else { return nil }
        let state = n.commits?.nodes.last??.commit.statusCheckRollup?.state
        return PullRequest(number: number, title: title, repository: n.repository?.nameWithOwner ?? "",
                           url: url, ciFailing: state == "FAILURE" || state == "ERROR")
    }

    private struct Response: Decodable { let data: DataField?; let errors: [GQLError]? }
    private struct GQLError: Decodable { let message: String }
    private struct DataField: Decodable { let review: Search; let mine: Search }
    private struct Search: Decodable { let nodes: [Node?] }
    private struct Node: Decodable {
        let number: Int?; let title: String?; let url: String?
        let repository: Repo?; let commits: Commits?
    }
    private struct Repo: Decodable { let nameWithOwner: String }
    private struct Commits: Decodable { let nodes: [CommitNode?] }
    private struct CommitNode: Decodable { let commit: Commit }
    private struct Commit: Decodable { let statusCheckRollup: Rollup? }
    private struct Rollup: Decodable { let state: String }
}
