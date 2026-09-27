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
    public var ciFailingCount: Int { mine.filter(\.ciFailing).count }

    public init(host: String, toReview: [PullRequest], mine: [PullRequest], fetchedAt: Date) {
        self.host = host; self.toReview = toReview; self.mine = mine; self.fetchedAt = fetchedAt
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
        case .http(let code): return code == 0 ? "keine Verbindung" : "HTTP \(code)"
        case .graphql(let m): return "GitHub: \(m)"
        case .decoding: return "unerwartete Antwort"
        case .ghTimeout: return "gh antwortet nicht (Zeitüberschreitung)"
        }
    }
}
