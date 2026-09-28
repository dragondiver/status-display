import Foundation

public enum GitHubAPI {
    public static func graphqlURL(host: String) -> URL {
        host == "github.com"
            ? URL(string: "https://api.github.com/graphql")!
            : URL(string: "https://\(host)/api/graphql")!
    }

    public static let query = """
    query {
      review: search(query: "is:open is:pr archived:false review-requested:@me", type: ISSUE, first: 100) { nodes { ...pr } }
      mine: search(query: "is:open is:pr archived:false author:@me", type: ISSUE, first: 100) { nodes { ...pr } }
    }
    fragment pr on PullRequest {
      number title url repository { nameWithOwner } isDraft reviewDecision
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
        // Unbekannte/neue Enum-Werte decodiert Node.reviewDecision schon als nil (RawRepresentable-
        // Init schlägt fehl) – hier bleibt nur das Zusammenführen mit "Feld fehlt ganz".
        return PullRequest(number: number, title: title, repository: n.repository?.nameWithOwner ?? "",
                           url: url, ciFailing: state == "FAILURE" || state == "ERROR",
                           isDraft: n.isDraft ?? false, reviewDecision: n.reviewDecision?.value)
    }

    private struct Response: Decodable { let data: DataField?; let errors: [GQLError]? }
    private struct GQLError: Decodable { let message: String }
    private struct DataField: Decodable { let review: Search; let mine: Search }
    private struct Search: Decodable { let nodes: [Node?] }
    private struct Node: Decodable {
        let number: Int?; let title: String?; let url: String?
        let repository: Repo?; let commits: Commits?; let isDraft: Bool?
        let reviewDecision: LenientReviewDecision?
    }
    /// Decodiert `reviewDecision` verlustfrei-tolerant: ein unbekannter String (künftiger
    /// GraphQL-Enum-Wert) wird zu `value == nil` statt den ganzen PR-Knoten zu verwerfen.
    private struct LenientReviewDecision: Decodable {
        let value: ReviewDecision?
        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            value = ReviewDecision(rawValue: raw)
        }
    }
    private struct Repo: Decodable { let nameWithOwner: String }
    private struct Commits: Decodable { let nodes: [CommitNode?] }
    private struct CommitNode: Decodable { let commit: Commit }
    private struct Commit: Decodable { let statusCheckRollup: Rollup? }
    private struct Rollup: Decodable { let state: String }
}
