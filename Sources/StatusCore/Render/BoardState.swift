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
    public var id: String { repoKey }

    public init(repoKey: String, repository: String, toReview: Int, mine: Int, ciFailing: Bool) {
        self.repoKey = repoKey; self.repository = repository
        self.toReview = toReview; self.mine = mine; self.ciFailing = ciFailing
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

    public init(rows: [PRRow], ciFailingCount: Int, lastSuccess: Date?, isStale: Bool) {
        self.rows = rows; self.ciFailingCount = ciFailingCount
        self.lastSuccess = lastSuccess; self.isStale = isStale
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
