import Foundation

public struct PullRequest: Equatable, Identifiable {
    public let number: Int
    public let title: String
    public let repository: String
    public let url: URL
    public let ciFailing: Bool
    public var id: String { url.absoluteString }

    public init(number: Int, title: String, repository: String, url: URL, ciFailing: Bool) {
        self.number = number; self.title = title; self.repository = repository; self.url = url; self.ciFailing = ciFailing
    }
}

public struct PRSnapshot: Equatable {
    public let host: String
    public let toReview: [PullRequest]
    public let mine: [PullRequest]
    public let fetchedAt: Date
    /// Teilantwort: GitHub lieferte Daten und zusätzlich Fehler (erste Meldung).
    public let warning: String?
    public var ciFailingCount: Int { mine.filter(\.ciFailing).count }

    public init(host: String, toReview: [PullRequest], mine: [PullRequest], fetchedAt: Date, warning: String? = nil) {
        self.host = host; self.toReview = toReview; self.mine = mine; self.fetchedAt = fetchedAt
        self.warning = warning
    }
}

public enum GitHubError: Error, Equatable {
    case ghNotFound
    case notLoggedIn(String)
    case http(Int)
    case graphql(String)
    case decoding
    case ghTimeout

    public var message: String {
        switch self {
        case .ghNotFound: return "gh nicht gefunden – Pfad in den Einstellungen setzen"
        case .notLoggedIn(let host): return "gh nicht angemeldet: gh auth login --hostname \(host)"
        case .http(0): return "keine Verbindung"
        case .http(401): return "Token abgelehnt (HTTP 401) – gh auth refresh ausführen"
        case .http(let code): return "HTTP \(code)"
        case .graphql(let m): return "GitHub: \(m)"
        case .decoding: return "unerwartete Antwort"
        case .ghTimeout: return "gh antwortet nicht (Zeitüberschreitung)"
        }
    }
}
