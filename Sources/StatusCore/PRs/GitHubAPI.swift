import Foundation

public enum GitHubAPI {
    public static func graphqlURL(host: String) -> URL {
        host == "github.com"
            ? URL(string: "https://api.github.com/graphql")!
            : URL(string: "https://\(host)/api/graphql")!
    }

    /// Wie viele Check-Einträge pro PR für die CI-Zusammenfassung gelesen werden. `totalCount`
    /// kommt trotzdem vollständig; was darüber hinausgeht, zählt als `CheckSummary.other`.
    /// Gemessen am 28.09.2026 auf github.com: Abfragekosten 6 → 8 Punkte pro Abruf.
    public static let checkContextLimit = 50

    public static let query = """
    query {
      viewer { login }
      review: search(query: "is:open is:pr archived:false review-requested:@me", type: ISSUE, first: 100) { nodes { ...pr } }
      mine: search(query: "is:open is:pr archived:false author:@me", type: ISSUE, first: 100) { nodes { ...pr } }
    }
    fragment pr on PullRequest {
      number title url repository { nameWithOwner } isDraft reviewDecision
      createdAt additions deletions changedFiles mergeable
      author { login ... on User { name } }
      commits(last: 1) { nodes { commit { statusCheckRollup {
        state
        contexts(first: \(checkContextLimit)) {
          totalCount
          nodes { __typename ... on CheckRun { status conclusion } ... on StatusContext { state } }
        }
      } } } }
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
        let hasForeignDecision = hasForeignApprovalOrChangesRequested(n.reviews, authorLogin: n.author?.login,
                                                                      viewerLogin: viewerLogin)
        // Unbekannte/neue Enum-Werte decodiert Node.reviewDecision schon als nil (RawRepresentable-
        // Init schlägt fehl) – hier bleibt nur das Zusammenführen mit "Feld fehlt ganz".
        let rollup = n.commits?.nodes.last??.commit.statusCheckRollup
        return PullRequest(number: number, title: title, repository: n.repository?.nameWithOwner ?? "",
                           url: url, ciFailing: state == "FAILURE" || state == "ERROR",
                           isDraft: n.isDraft ?? false, reviewDecision: n.reviewDecision?.value,
                           hasCodeOwnerRequestForMe: hasCodeOwner, hasExtraRequestForMe: hasExtra,
                           hasForeignApprovalOrChangesRequested: hasForeignDecision,
                           createdAt: n.createdAt?.value.flatMap(parseDate),
                           additions: n.additions?.value, deletions: n.deletions?.value,
                           changedFiles: n.changedFiles?.value,
                           mergeable: n.mergeable?.value.flatMap(Mergeable.init(rawValue:)),
                           authorLogin: n.author?.login, authorName: n.author?.name?.value.flatMap(nonEmpty),
                           checks: rollup?.contexts?.value.map(checkSummary),
                           reviews: reviewSummaries(n.reviews, authorLogin: n.author?.login))
    }

    private static func nonEmpty(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }

    /// GitHub liefert `DateTime` als ISO 8601, mit oder (üblich) ohne Sekundenbruchteile.
    static func parseDate(_ string: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let d = plain.date(from: string) { return d }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string)
    }

    /// Zählt grüne und rote Checks. `CheckRun`: erst ab `status == COMPLETED` zählt `conclusion`
    /// (SUCCESS/NEUTRAL/SKIPPED grün; FAILURE/TIMED_OUT/CANCELLED/ACTION_REQUIRED/STARTUP_FAILURE
    /// rot). `StatusContext`: SUCCESS grün, FAILURE/ERROR rot. Alles andere – laufend, wartend,
    /// STALE, unbekannte künftige Werte – bleibt als `other` sichtbar, statt verworfen zu werden.
    private static func checkSummary(_ contexts: Contexts) -> CheckSummary {
        var passed = 0, failed = 0
        let nodes = contexts.nodes?.compactMap { $0 } ?? []
        for node in nodes {
            switch classify(node) {
            case .passed: passed += 1
            case .failed: failed += 1
            case .other: break
            }
        }
        let total = max(contexts.totalCount ?? nodes.count, passed + failed)
        return CheckSummary(total: total, passed: passed, failed: failed)
    }

    private enum CheckOutcome { case passed, failed, other }

    private static func classify(_ node: ContextNode) -> CheckOutcome {
        switch node.typename {
        case "CheckRun":
            guard node.status == "COMPLETED" else { return .other }
            switch node.conclusion {
            case "SUCCESS", "NEUTRAL", "SKIPPED": return .passed
            case "FAILURE", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE": return .failed
            default: return .other
            }
        case "StatusContext":
            switch node.state {
            case "SUCCESS": return .passed
            case "FAILURE", "ERROR": return .failed
            default: return .other
            }
        default:
            return .other
        }
    }

    /// Letzter Zustand je Reviewer, ohne den PR-Autor (Selbst-Kommentare sind kein Review) und
    /// ohne Reviews unbekannter Autoren oder mit unbekanntem Zustand.
    private static func reviewSummaries(_ reviews: Reviews?, authorLogin: String?) -> [ReviewSummary] {
        var order: [String] = []
        var latest: [String: ReviewSummary.State] = [:]
        for review in reviews?.nodes.compactMap({ $0 }) ?? [] {
            guard let login = review.author?.login, login != authorLogin,
                  let raw = review.state, let state = ReviewSummary.State(rawValue: raw) else { continue }
            if latest[login] == nil { order.append(login) }
            latest[login] = state
        }
        return order.compactMap { login in latest[login].map { ReviewSummary(login: login, state: $0) } }
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

    /// Näherung „ein Code-Owner hat schon reviewt“: irgendjemand außer dem PR-Autor **und außer mir
    /// selbst** hat `APPROVED` oder `CHANGES_REQUESTED` abgegeben. Ohne den Ausschluss meines
    /// eigenen Logins würde eine frühere eigene Freigabe fälschlich als fremde Erledigung zählen,
    /// falls ich (z. B. nach einem neuen Commit) erneut als Code-Owner angefragt werde – die alte
    /// Freigabe soll die neue Anfrage nicht stillschweigend abräumen (Befund verifier, 28.09.2026,
    /// status-display#21). Ein Review ganz ohne bekannten Autor (z. B. gelöschter Account) zählt
    /// vorsichtshalber als fremd.
    private static func hasForeignApprovalOrChangesRequested(_ reviews: Reviews?, authorLogin: String?,
                                                              viewerLogin: String?) -> Bool {
        (reviews?.nodes.compactMap { $0 } ?? []).contains { review in
            guard review.state == "APPROVED" || review.state == "CHANGES_REQUESTED" else { return false }
            let reviewerLogin = review.author?.login
            return reviewerLogin != authorLogin && reviewerLogin != viewerLogin
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
        // Detailfelder (status-display#24): tolerant decodiert, ein unerwarteter Typ wird zu nil
        // statt den ganzen Knoten (oder gar die ganze Antwort) zu verwerfen.
        let createdAt: Lenient<String>?
        let additions: Lenient<Int>?
        let deletions: Lenient<Int>?
        let changedFiles: Lenient<Int>?
        let mergeable: Lenient<String>?
    }
    /// Decodiert `T` oder – bei falschem Typ – nil, ohne zu werfen.
    private struct Lenient<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? decoder.singleValueContainer().decode(T.self) }
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
    private struct UserRef: Decodable { let login: String; let name: Lenient<String>? }
    private struct Repo: Decodable { let nameWithOwner: String }
    private struct Commits: Decodable { let nodes: [CommitNode?] }
    private struct CommitNode: Decodable { let commit: Commit }
    private struct Commit: Decodable { let statusCheckRollup: Rollup? }
    private struct Rollup: Decodable { let state: String; let contexts: Lenient<Contexts>? }
    private struct Contexts: Decodable { let totalCount: Int?; let nodes: [ContextNode?]? }
    /// `StatusCheckRollupContext` ist ein Union aus `CheckRun` (`status`/`conclusion`) und
    /// `StatusContext` (`state`); alle Felder optional und als String, damit neue Enum-Werte
    /// nichts kaputt machen.
    private struct ContextNode: Decodable {
        let typename: String?
        let status: String?
        let conclusion: String?
        let state: String?
        enum CodingKeys: String, CodingKey { case typename = "__typename", status, conclusion, state }
    }
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
