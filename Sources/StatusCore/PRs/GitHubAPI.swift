import Foundation

public enum GitHubAPI {
    public static func graphqlURL(host: String) -> URL {
        host == "github.com"
            ? URL(string: "https://api.github.com/graphql")!
            : URL(string: "https://\(host)/api/graphql")!
    }

    public static let query = """
    query {
      viewer { login }
      review: search(query: "is:open is:pr archived:false review-requested:@me", type: ISSUE, first: 100) { nodes { ...pr } }
      mine: search(query: "is:open is:pr archived:false author:@me", type: ISSUE, first: 100) { nodes { ...pr } }
    }
    fragment pr on PullRequest {
      number title url repository { nameWithOwner } isDraft reviewDecision
      author { login }
      commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
      reviewRequests(first: 20) {
        nodes { asCodeOwner requestedReviewer { __typename ... on User { login } ... on Team { name } } }
      }
      reviews(last: 20) { nodes { author { login } state } }
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
        let viewerLogin = d.viewer?.login
        return PRSnapshot(host: host, toReview: d.review.nodes.compactMap { pull($0, viewerLogin: viewerLogin) },
                          mine: d.mine.nodes.compactMap { pull($0, viewerLogin: viewerLogin) },
                          fetchedAt: date, warning: response.errors?.first?.message)
    }

    private static func pull(_ node: Node?, viewerLogin: String?) -> PullRequest? {
        guard let n = node, let number = n.number, let title = n.title,
              let urlString = n.url, let url = URL(string: urlString) else { return nil }
        let state = n.commits?.nodes.last??.commit.statusCheckRollup?.state
        let (hasCodeOwner, hasExtra) = reviewRequestKinds(n.reviewRequests, viewerLogin: viewerLogin)
        let hasForeignDecision = hasForeignApprovalOrChangesRequested(n.reviews, authorLogin: n.author?.login)
        // Unbekannte/neue Enum-Werte decodiert Node.reviewDecision schon als nil (RawRepresentable-
        // Init schlägt fehl) – hier bleibt nur das Zusammenführen mit "Feld fehlt ganz".
        return PullRequest(number: number, title: title, repository: n.repository?.nameWithOwner ?? "",
                           url: url, ciFailing: state == "FAILURE" || state == "ERROR",
                           isDraft: n.isDraft ?? false, reviewDecision: n.reviewDecision?.value,
                           hasCodeOwnerRequestForMe: hasCodeOwner, hasExtraRequestForMe: hasExtra,
                           hasForeignApprovalOrChangesRequested: hasForeignDecision)
    }

    /// Wertet `reviewRequests` aus: eine Anfrage betrifft mich, wenn `requestedReviewer` ein User
    /// mit meinem Login ist, oder – bei `asCodeOwner == true` – ein Team (Anfragen an andere Teams
    /// nicht-Code-Owner-artig ignorieren wir, da GitHub uns dort keine Mitgliedschaft verrät;
    /// `review-requested:@me` hat den PR-Knoten aber ohnehin nur geliefert, wenn irgendeine Anfrage
    /// mich betrifft). Anfragen an andere User zählen nicht mit.
    private static func reviewRequestKinds(_ requests: ReviewRequests?, viewerLogin: String?)
        -> (codeOwner: Bool, extra: Bool) {
        var codeOwner = false
        var extra = false
        for request in requests?.nodes.compactMap({ $0 }) ?? [] {
            guard let reviewer = request.requestedReviewer else { continue }
            let isCodeOwner = request.asCodeOwner ?? false
            switch reviewer.typename {
            case "User":
                guard let login = reviewer.login, let viewerLogin, login == viewerLogin else { continue }
                if isCodeOwner { codeOwner = true } else { extra = true }
            case "Team":
                if isCodeOwner { codeOwner = true }
            default:
                continue
            }
        }
        return (codeOwner, extra)
    }

    /// Näherung „ein Code-Owner hat schon reviewt“: irgendjemand außer dem PR-Autor hat `APPROVED`
    /// oder `CHANGES_REQUESTED` abgegeben. Ein Review ganz ohne bekannten Autor (z. B. gelöschter
    /// Account) zählt vorsichtshalber als fremd.
    private static func hasForeignApprovalOrChangesRequested(_ reviews: Reviews?, authorLogin: String?) -> Bool {
        (reviews?.nodes.compactMap { $0 } ?? []).contains { review in
            guard review.state == "APPROVED" || review.state == "CHANGES_REQUESTED" else { return false }
            return review.author?.login != authorLogin
        }
    }

    private struct Response: Decodable { let data: DataField?; let errors: [GQLError]? }
    private struct GQLError: Decodable { let message: String }
    private struct DataField: Decodable { let viewer: UserRef?; let review: Search; let mine: Search }
    private struct Search: Decodable { let nodes: [Node?] }
    private struct Node: Decodable {
        let number: Int?; let title: String?; let url: String?
        let repository: Repo?; let commits: Commits?; let isDraft: Bool?
        let reviewDecision: LenientReviewDecision?
        let author: UserRef?
        let reviewRequests: ReviewRequests?
        let reviews: Reviews?
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
    private struct UserRef: Decodable { let login: String }
    private struct Repo: Decodable { let nameWithOwner: String }
    private struct Commits: Decodable { let nodes: [CommitNode?] }
    private struct CommitNode: Decodable { let commit: Commit }
    private struct Commit: Decodable { let statusCheckRollup: Rollup? }
    private struct Rollup: Decodable { let state: String }
    private struct ReviewRequests: Decodable { let nodes: [ReviewRequestNode?] }
    private struct ReviewRequestNode: Decodable { let asCodeOwner: Bool?; let requestedReviewer: RequestedReviewer? }
    /// `RequestedReviewer` ist ein GraphQL-Union (`User`/`Team`/`Mannequin`); `name` gilt nur für
    /// `Team` und bleibt hier ungenutzt (nur zur Unterscheidung von `login` nicht gebraucht, aber
    /// zum verlustfreien Decodieren mitgelesen).
    private struct RequestedReviewer: Decodable {
        let typename: String
        let login: String?
        enum CodingKeys: String, CodingKey { case typename = "__typename", login }
    }
    private struct Reviews: Decodable { let nodes: [ReviewNode?] }
    private struct ReviewNode: Decodable { let author: UserRef?; let state: String? }
}
