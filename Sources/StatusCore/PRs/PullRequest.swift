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
    /// Fließt seit status-display#21 (Verfeinerung 28.09.2026) nicht mehr in `needsMyReview` ein –
    /// nur noch informativ.
    public let reviewDecision: ReviewDecision?
    /// Aus `reviewRequests` extrahiert: eine Code-Owner-Anfrage (`asCodeOwner == true`) an mich
    /// persönlich oder an ein Team, dem ich angehöre. GitHub verrät bei Team-Anfragen nicht, wer im
    /// Team gemeint ist – die Suche `review-requested:@me`, die diese PRs überhaupt erst liefert,
    /// stellt aber schon sicher, dass eine der Anfragen mich betrifft.
    public let hasCodeOwnerRequestForMe: Bool
    /// Eine ausdrückliche Zusatzanfrage an mich persönlich (`asCodeOwner == false`,
    /// `requestedReviewer` ein User mit meinem Login).
    public let hasExtraRequestForMe: Bool
    /// Näherung für „ein Code-Owner hat schon reviewt“: irgendjemand außer dem PR-Autor hat
    /// `APPROVED` oder `CHANGES_REQUESTED` abgegeben. GitHub liefert bei abgeschlossenen Reviews
    /// nicht mehr, ob der jeweilige Reviewer Code-Owner war – ein Review nur durch den Autor selbst
    /// zählt bewusst nicht als „Code-Owner hat reviewt“.
    public let hasForeignApprovalOrChangesRequested: Bool
    public var id: String { url.absoluteString }

    /// Zählt dieser Review-Request noch als „zu reviewen“?
    /// - Eine Extra-Anfrage an mich zählt **immer**, bis ich selbst reviewe (dann entfernt GitHub
    ///   die Anfrage, und sie taucht hier gar nicht mehr auf) – auch wenn der PR schon freigegeben ist.
    /// - Eine Code-Owner-Anfrage zählt nur, solange noch **kein** Code-Owner reviewt hat
    ///   (Näherung: `hasForeignApprovalOrChangesRequested`).
    ///
    /// Ersetzt die ursprüngliche „`reviewDecision == APPROVED` zählt nicht“-Regel (Entscheidung
    /// Florian, 28.09.2026, status-display#21, verfeinert im selben Issue: bei GHE ist
    /// Code-Owner-Review der Normalfall, `reviewDecision` allein unterscheidet das nicht).
    public var needsMyReview: Bool {
        hasExtraRequestForMe || (hasCodeOwnerRequestForMe && !hasForeignApprovalOrChangesRequested)
    }

    public init(number: Int, title: String, repository: String, url: URL, ciFailing: Bool, isDraft: Bool = false,
               reviewDecision: ReviewDecision? = nil, hasCodeOwnerRequestForMe: Bool = false,
               hasExtraRequestForMe: Bool = false, hasForeignApprovalOrChangesRequested: Bool = false) {
        self.number = number; self.title = title; self.repository = repository; self.url = url; self.ciFailing = ciFailing
        self.isDraft = isDraft
        self.reviewDecision = reviewDecision
        self.hasCodeOwnerRequestForMe = hasCodeOwnerRequestForMe
        self.hasExtraRequestForMe = hasExtraRequestForMe
        self.hasForeignApprovalOrChangesRequested = hasForeignApprovalOrChangesRequested
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
