import Foundation

/// GitHubs Gesamt-Freigabestatus eines PR (`reviewDecision` im GraphQL-Schema). Unbekannte Werte
/// werden beim Parsen wie `null` behandelt (siehe `GitHubAPI`).
public enum ReviewDecision: String, Equatable {
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"
    case reviewRequired = "REVIEW_REQUIRED"
}

/// Ob GitHub den PR konfliktfrei mergen könnte (`mergeable` im GraphQL-Schema). `UNKNOWN` heißt,
/// GitHub rechnet noch – das Dashboard zeigt dann nichts statt einer Vermutung.
public enum Mergeable: String, Equatable {
    case mergeable = "MERGEABLE"
    case conflicting = "CONFLICTING"
    case unknown = "UNKNOWN"
}

/// Zusammenfassung der Checks am letzten Commit (`statusCheckRollup.contexts`), fürs Dashboard
/// (status-display#24). `total` kommt aus `totalCount`; gelesen werden nur die ersten
/// `GitHubAPI.checkContextLimit` Einträge, alles darüber hinaus steckt in `other`.
public struct CheckSummary: Equatable {
    public let total: Int
    public let passed: Int
    public let failed: Int
    /// Laufend, wartend, unbekannter Zustand oder jenseits der gelesenen Einträge.
    public var other: Int { max(0, total - passed - failed) }

    public init(total: Int, passed: Int, failed: Int) {
        self.total = total; self.passed = passed; self.failed = failed
    }
}

/// Letzter Review-Zustand eines Reviewers (ohne den PR-Autor), fürs Dashboard.
public struct ReviewSummary: Equatable {
    public enum State: String, Equatable {
        case approved = "APPROVED"
        case changesRequested = "CHANGES_REQUESTED"
        case commented = "COMMENTED"
        case dismissed = "DISMISSED"
        case pending = "PENDING"
    }
    public let login: String
    public let state: State

    public init(login: String, state: State) { self.login = login; self.state = state }
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

    // Details fürs Dashboard (status-display#24). Alle optional: fehlt ein Feld in der Antwort
    // (ältere GHE-Version, Teilantwort), bleibt der PR trotzdem erhalten.
    public let createdAt: Date?
    public let additions: Int?
    public let deletions: Int?
    public let changedFiles: Int?
    public let mergeable: Mergeable?
    public let authorLogin: String?
    /// Anzeigename des Autors, falls GitHub einen liefert (nur bei `User`, nicht bei Bots).
    public let authorName: String?
    public let checks: CheckSummary?
    /// Letzter Zustand je Reviewer (ohne den Autor), in der Reihenfolge des ersten Auftretens.
    public let reviews: [ReviewSummary]
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
               hasExtraRequestForMe: Bool = false, hasForeignApprovalOrChangesRequested: Bool = false,
               createdAt: Date? = nil, additions: Int? = nil, deletions: Int? = nil, changedFiles: Int? = nil,
               mergeable: Mergeable? = nil, authorLogin: String? = nil, authorName: String? = nil,
               checks: CheckSummary? = nil, reviews: [ReviewSummary] = []) {
        self.number = number; self.title = title; self.repository = repository; self.url = url; self.ciFailing = ciFailing
        self.isDraft = isDraft
        self.reviewDecision = reviewDecision
        self.hasCodeOwnerRequestForMe = hasCodeOwnerRequestForMe
        self.hasExtraRequestForMe = hasExtraRequestForMe
        self.hasForeignApprovalOrChangesRequested = hasForeignApprovalOrChangesRequested
        self.createdAt = createdAt; self.additions = additions; self.deletions = deletions
        self.changedFiles = changedFiles; self.mergeable = mergeable
        self.authorLogin = authorLogin; self.authorName = authorName
        self.checks = checks; self.reviews = reviews
    }
}

public struct PRSnapshot: Equatable {
    public let host: String
    public let toReview: [PullRequest]
    public let mine: [PullRequest]
    public let fetchedAt: Date
    /// Teilantwort: GitHub lieferte Daten und zusätzlich Fehler (erste Meldung).
    public let warning: String?

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
