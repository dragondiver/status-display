import Foundation

/// Eine Zeile der PR-Tabelle: ein Repo mit den Zahlen, die für dieses Repo zählen.
public struct PRRow: Equatable, Identifiable {
    /// `host/owner/name`, eindeutig über alle Hosts hinweg; identisch mit den Einträgen
    /// in `AppSettings.pinnedRepos`/`hiddenRepos`.
    public let repoKey: String
    /// Kurzer Anzeigename (nur der Repo-Teil, ohne Owner/Host).
    public let repository: String
    public let toReview: Int
    public let mine: Int
    /// Roter Punkt: ein eigener Nicht-Draft-PR in diesem Repo hat rote CI.
    public let ciFailing: Bool
    /// Review-Requests in diesem Repo, für die `PullRequest.needsMyReview == false` ist – zählen
    /// nicht in `toReview` (Entscheidung Florian, 28.09.2026, status-display#21), bleiben aber im
    /// Menü in einem eigenen Abschnitt „schon freigegeben“ sichtbar. Nicht Teil von
    /// `Equatable`-relevanten Zähl-/Sortierlogik der Tabelle – nur fürs Menü gedacht.
    public let approvedReviews: [PullRequest]
    /// Mindestens einer der in `toReview` gezählten Review-Requests ist eine Extra-Anfrage
    /// (`PullRequest.hasExtraRequestForMe`), keine reine Code-Owner-Anfrage. Der Renderer färbt die
    /// Review-Zahl dieser Zeile dann orange statt weiß/grau (Entscheidung Florian, 28.09.2026,
    /// status-display#21).
    public let hasExtraReview: Bool
    public var id: String { repoKey }

    public init(repoKey: String, repository: String, toReview: Int, mine: Int, ciFailing: Bool,
               approvedReviews: [PullRequest] = [], hasExtraReview: Bool = false) {
        self.repoKey = repoKey; self.repository = repository
        self.toReview = toReview; self.mine = mine; self.ciFailing = ciFailing
        self.approvedReviews = approvedReviews
        self.hasExtraReview = hasExtraReview
    }
}

public struct PRZone: Equatable {
    public var rows: [PRRow]
    /// Gesamtzahl eigener Nicht-Draft-PRs mit roter CI, über alle Hosts – unabhängig davon,
    /// ob das jeweilige Repo angeheftet/ausgeblendet/automatisch sichtbar ist. Bestimmt den
    /// roten Rand der ganzen Zone.
    public var ciFailingCount: Int
    /// Ältester erfolgreicher Abruf über alle Hosts; nil = noch nie.
    public var lastSuccess: Date?
    public var isStale: Bool
    /// Review-Requests an Florian in ausgeblendeten Repos (explizit oder per Host-Standard) – eigene
    /// offene PRs zählen hier nicht (Entscheidung Florian, 28.09.2026, status-display#19). Bewusst
    /// kein Teil von `rows`: Board und Menü entscheiden je selbst, wie sie eine Sammelzeile daraus
    /// bilden, statt dass eine ausgeblendete Zeile unbemerkt durch die normale Zeilenkürzung fällt.
    public var hiddenReviews: [PullRequest]

    public init(rows: [PRRow], ciFailingCount: Int, lastSuccess: Date?, isStale: Bool,
               hiddenReviews: [PullRequest] = []) {
        self.rows = rows; self.ciFailingCount = ciFailingCount
        self.lastSuccess = lastSuccess; self.isStale = isStale
        self.hiddenReviews = hiddenReviews
    }

    public static let unknown = PRZone(rows: [], ciFailingCount: 0, lastSuccess: nil, isStale: true)
}

public struct BoardState: Equatable {
    public var statusName: String
    public var statusColor: RGBColor
    public var statusSince: Date
    public var agents: [AgentActivity]
    public var prs: PRZone
    public var now: Date

    public init(statusName: String, statusColor: RGBColor, statusSince: Date,
                agents: [AgentActivity], prs: PRZone, now: Date) {
        self.statusName = statusName; self.statusColor = statusColor; self.statusSince = statusSince
        self.agents = agents; self.prs = prs; self.now = now
    }
}
