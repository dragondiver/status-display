import Foundation

/// GitHubs Gesamt-Freigabestatus eines PR (`reviewDecision` im GraphQL-Schema). Unbekannte Werte
/// werden beim Parsen wie `null` behandelt (siehe `GitHubAPI`).
public enum ReviewDecision: String, Equatable {
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"
    case reviewRequired = "REVIEW_REQUIRED"
}

public struct PullRequest: Equatable, Identifiable {
    public let number: Int
    public let title: String
    public let repository: String
    public let url: URL
    public let ciFailing: Bool
    public let isDraft: Bool
    /// `nil`, solange GitHub (noch) keine Entscheidung kennt oder ein unbekannter Wert ankam.
    public let reviewDecision: ReviewDecision?
    public var id: String { url.absoluteString }

    /// Zählt dieser Review-Request noch als „zu reviewen“? Nur `APPROVED` zählt nicht mehr –
    /// `CHANGES_REQUESTED`, `REVIEW_REQUIRED` und `nil` (unbekannt/offen) zählen weiter
    /// (Entscheidung Florian, 28.09.2026, status-display#21: bei GitHub Enterprise bleibt eine
    /// persönliche Review-Anfrage stehen, auch wenn der PR durch andere schon freigegeben ist).
    public var needsMyReview: Bool { reviewDecision != .approved }

    public init(number: Int, title: String, repository: String, url: URL, ciFailing: Bool, isDraft: Bool = false,
               reviewDecision: ReviewDecision? = nil) {
        self.number = number; self.title = title; self.repository = repository; self.url = url; self.ciFailing = ciFailing
        self.isDraft = isDraft
        self.reviewDecision = reviewDecision
    }
}

public struct PRSnapshot: Equatable {
    public let host: String
    public let toReview: [PullRequest]
    public let mine: [PullRequest]
    public let fetchedAt: Date
    /// Teilantwort: GitHub lieferte Daten und zusätzlich Fehler (erste Meldung).
    public let warning: String?
    public var ciFailingCount: Int { mine.filter { $0.ciFailing && !$0.isDraft }.count }

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
