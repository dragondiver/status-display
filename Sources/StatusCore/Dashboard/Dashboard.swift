import Foundation

/// Die vier Bereiche der linken Spalte im Dashboard-Fenster (status-display#24, Entwurf B;
/// status-display#39: Agenten sind kein Sammel-Bereich mehr, sondern ein eigener Abschnitt mit
/// einer Zeile je Agent in der Seitenleiste – siehe `Dashboard.agents`).
/// `rawValue` ist zugleich die Ziffer des Tastaturkürzels (⌘1–⌘4).
public enum DashboardSection: Int, CaseIterable, Identifiable, Equatable {
    case waiting = 1
    case codeOwner = 2
    case mine = 3
    case approved = 4

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .waiting: return "Wartet auf dich"
        case .codeOwner: return "Code-Owner-Reviews"
        case .mine: return "Deine PRs"
        case .approved: return "Schon freigegeben"
        }
    }

    /// ⌘1–⌘4 → Bereich; andere Ziffern → nil.
    public init?(shortcutNumber: Int) { self.init(rawValue: shortcutNumber) }
}

/// Dringlichkeit eines Eintrags; kleiner = dringender. Die Reihenfolge folgt dem Produktsteckbrief
/// („wartet auf mich > rot > Rest“) und dem Prototyp (Extra-Anfrage vor wartendem Agenten vor
/// eigener roter CI).
public enum DashboardUrgency: Int, Comparable, Equatable {
    case extraRequest = 0
    case agentWaiting = 1
    /// Eigener PR mit roter CI (Nicht-Draft) oder angeforderten Änderungen.
    case ownActionNeeded = 2
    case agentError = 3
    case codeOwnerRequest = 4
    case ownPR = 5
    case agentRunning = 6
    case agentStale = 7
    case agentDone = 8
    /// Code-Owner-Anfrage, die schon ein anderer erledigt hat (`needsMyReview == false`).
    case alreadyReviewed = 9

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Kleine Text-Etiketten neben einem Eintrag. Farbe ist im Dashboard nie das einzige Signal –
/// jedes farbige Merkmal hat hier ein Etikett mit Text.
public enum DashboardTag: String, Equatable, CaseIterable {
    case extra, codeOwner, ciFailing, changesRequested, conflict, draft
    case agentWaiting, agentError, agentStale

    public var label: String {
        switch self {
        case .extra: return "Extra"
        case .codeOwner: return "Code-Owner"
        case .ciFailing: return "CI rot"
        case .changesRequested: return "Änderungen angefordert"
        case .conflict: return "Konflikt"
        case .draft: return "Draft"
        case .agentWaiting: return "wartet"
        case .agentError: return "Fehler"
        case .agentStale: return "unklar"
        }
    }
}

/// Farbklasse des Zustandspunkts vor einem Eintrag (Liste, Detail, Agenten-Zeilen der
/// Seitenleiste). Nie das einzige Signal – daneben steht immer ein Text-Etikett.
public enum DashboardMarkKind: Equatable {
    case waiting, error, neutral
}

public struct DashboardItem: Identifiable, Equatable {
    public enum Subject: Equatable {
        /// `repoKey` ist `host/owner/name`; `isMine` unterscheidet eigene PRs von Review-Anfragen.
        case pullRequest(PullRequest, repoKey: String, isMine: Bool)
        case agent(AgentActivity)
    }

    public let subject: Subject
    public let urgency: DashboardUrgency
    public let tags: [DashboardTag]

    public init(subject: Subject, urgency: DashboardUrgency, tags: [DashboardTag]) {
        self.subject = subject; self.urgency = urgency; self.tags = tags
    }

    public var id: String {
        switch subject {
        case .pullRequest(let pr, _, let isMine): return (isMine ? "mine:" : "review:") + pr.id
        case .agent(let a): return "agent:" + a.id
        }
    }

    /// Bezugszeitpunkt fürs Alter: Erstellung des PR bzw. Beginn des aktuellen Agenten-Zustands.
    public var date: Date? {
        switch subject {
        case .pullRequest(let pr, _, _): return pr.createdAt
        case .agent(let a): return a.since
        }
    }

    public var repoKey: String? {
        if case .pullRequest(_, let key, _) = subject { return key }
        return nil
    }

    public var url: URL? {
        switch subject {
        case .pullRequest(let pr, _, _): return pr.url
        case .agent(let a): return a.url
        }
    }

    /// Orange Markierung: Extra-Anfrage oder wartender Agent.
    public var isWaitingForMe: Bool { urgency == .extraRequest || urgency == .agentWaiting }

    /// Farbe des Zustandspunkts vor einem Eintrag – Liste, Detail und die Agenten-Zeilen der
    /// Seitenleiste (status-display#39) nutzen dieselbe Regel, statt sie je Ansicht zu wiederholen.
    public var markKind: DashboardMarkKind {
        if isWaitingForMe { return .waiting }
        if tags.contains(.ciFailing) || tags.contains(.agentError) { return .error }
        if urgency == .ownActionNeeded { return .waiting }
        return .neutral
    }

    /// Dringlichkeit, dann Alter (älteste zuerst – wer am längsten wartet, kommt zuerst dran),
    /// Einträge ohne Datum hinten, zuletzt die `id` für eine stabile Reihenfolge.
    static func precedes(_ l: DashboardItem, _ r: DashboardItem) -> Bool {
        if l.urgency != r.urgency { return l.urgency < r.urgency }
        switch (l.date, r.date) {
        case let (ld?, rd?) where ld != rd: return ld < rd
        case (.some, nil): return true
        case (nil, .some): return false
        default: return l.id < r.id
        }
    }
}

/// Ein Repo in der linken Spalte, mit Zähler.
public struct DashboardRepo: Identifiable, Equatable {
    public let repoKey: String
    public let name: String
    /// Offene PRs in diesem Repo, die das Dashboard unter „Wartet auf dich“, „Code-Owner-Reviews“
    /// oder „Deine PRs“ zeigt (ohne „Schon freigegeben“).
    public let count: Int
    /// Mindestens einer davon steht unter „Wartet auf dich“ – Zähler orange.
    public let hasWaiting: Bool
    public var id: String { repoKey }

    public init(repoKey: String, name: String, count: Int, hasWaiting: Bool) {
        self.repoKey = repoKey; self.name = name; self.count = count; self.hasWaiting = hasWaiting
    }
}

/// Reine Logik hinter dem Dashboard-Fenster (status-display#24): baut aus PR-Snapshots, der
/// Sichtbarkeitsregel des `PRAggregator` und den Agenten die Listen der vier PR-Bereiche, die
/// Agenten-Liste, die Repo-Liste und den Leerzustand. Keine UI, kein Netzwerk – vollständig
/// testbar.
///
/// Regeln (Entscheidung Florian, 28.09.2026, status-display#24 und status-display#39):
/// - **Wartet auf dich**: Extra-Anfragen an mich (`needsMyReview && hasExtraRequestForMe`),
///   Agenten im Zustand *wartet*, eigene PRs mit roter CI (nur Nicht-Draft, wie
///   `PRZone.ciFailingCount`) oder `reviewDecision == CHANGES_REQUESTED` (auch als Draft –
///   angeforderte Änderungen gelten unabhängig vom Draft-Status).
/// - **Code-Owner-Reviews**: `needsMyReview` ohne Extra-Anfrage (die stehen schon oben).
/// - **Deine PRs**: alle eigenen offenen PRs, auch die schon unter „Wartet auf dich“.
/// - **Agenten**: alle Agenten aus `AgentRegistry.snapshot()`, sortiert wie auf dem Display
///   (wartet → Fehler → läuft → unklar → fertig). Kein eigener `DashboardSection`-Fall mehr –
///   die Seitenleiste zeigt jeden Agenten einzeln (status-display#39), statt sie als Sammel-Eintrag
///   in die vier PR-Bereiche einzureihen.
/// - **Schon freigegeben**: Review-Anfragen mit `needsMyReview == false`.
/// - Ausgeblendete Repos (`PRAggregator.isHidden`) erscheinen in keinem Bereich und keiner
///   Repo-Zeile. Ihre offenen Review-Anfragen stehen – wie im Menü und auf dem Board – gesammelt
///   unter `hiddenReviews`, das die UI als eigenen, unauffälligen Eintrag „Ausgeblendet“ zeigt:
///   Für Kollegen ohne AKP02 ist das Fenster die einzige Ansicht; ohne den Eintrag würde eine
///   Anfrage in einem ausgeblendeten Repo dort unsichtbar. Sie zählen bewusst nicht unter „Wartet
///   auf dich“ – Ausblenden ist eine ausdrückliche Entscheidung des Nutzers.
/// - Jede Liste ist nach `DashboardItem.precedes` sortiert (Dringlichkeit, dann Alter).
public struct Dashboard: Equatable {
    public let waiting: [DashboardItem]
    public let codeOwner: [DashboardItem]
    public let mine: [DashboardItem]
    public let agents: [DashboardItem]
    public let approved: [DashboardItem]
    public let hiddenReviews: [DashboardItem]
    public let repos: [DashboardRepo]
    /// Mindestens ein Host hat schon einmal erfolgreich geantwortet.
    public let hasPRData: Bool
    public let isStale: Bool
    public let lastSuccess: Date?

    public func items(in section: DashboardSection) -> [DashboardItem] {
        switch section {
        case .waiting: return waiting
        case .codeOwner: return codeOwner
        case .mine: return mine
        case .approved: return approved
        }
    }

    /// Der einzelne Agent für die Detailansicht eines Agenten-Eintrags der Seitenleiste
    /// (status-display#39). `nil`, wenn er inzwischen verschwunden ist (z. B. TTL abgelaufen).
    public func agentItem(id: String) -> DashboardItem? { agents.first { $0.id == id } }

    public func count(_ section: DashboardSection) -> Int { items(in: section).count }

    /// Die PRs eines Repos aus „Wartet auf dich“, „Code-Owner-Reviews“ und „Deine PRs“, ohne
    /// Doppelte, sortiert. Die Länge ist `DashboardRepo.count`.
    public func items(inRepo repoKey: String) -> [DashboardItem] {
        var seen = Set<String>()
        return (waiting + codeOwner + mine)
            .filter { $0.repoKey == repoKey && seen.insert($0.id).inserted }
            .sorted(by: DashboardItem.precedes)
    }

    /// Überschrift des Leerzustands von „Wartet auf dich“.
    public var emptyTitle: String { hasPRData ? "Nichts wartet auf dich." : "Noch keine Daten von GitHub." }

    /// Kurze Zusammenfassung unter dem Leerzustand, z. B. „3 Code-Owner-Reviews offen · 1 eigener
    /// PR offen · 2 Agenten laufen“.
    public var summary: String {
        var parts: [String] = []
        let running = agents.filter { $0.urgency == .agentRunning }.count
        if !codeOwner.isEmpty {
            parts.append(codeOwner.count == 1 ? "1 Code-Owner-Review offen" : "\(codeOwner.count) Code-Owner-Reviews offen")
        }
        if !mine.isEmpty { parts.append(mine.count == 1 ? "1 eigener PR offen" : "\(mine.count) eigene PRs offen") }
        if running > 0 { parts.append(running == 1 ? "1 Agent läuft" : "\(running) Agenten laufen") }
        if !approved.isEmpty {
            parts.append(approved.count == 1 ? "1 Review schon von anderen erledigt"
                                             : "\(approved.count) Reviews schon von anderen erledigt")
        }
        if !hiddenReviews.isEmpty { parts.append("\(hiddenReviews.count) in ausgeblendeten Repos") }
        return parts.isEmpty ? "Keine offenen PRs, keine laufenden Agenten." : parts.joined(separator: " · ")
    }

    public static func build(prs: PRAggregator, agents: [AgentActivity], now: Date, hosts: [String],
                             pinned: [String] = [], hidden: [String] = [], shown: [String] = [],
                             hostDefaults: [String: RepoDefault] = [:]) -> Dashboard {
        let zone = prs.zone(now: now, hosts: hosts, pinned: pinned, hidden: hidden, shown: shown,
                            hostDefaults: hostDefaults)
        func isHidden(_ key: String) -> Bool {
            PRAggregator.isHidden(repoKey: key, pinned: pinned, hidden: hidden, shown: shown,
                                  hostDefaults: hostDefaults)
        }

        var waiting: [DashboardItem] = []
        var codeOwner: [DashboardItem] = []
        var mine: [DashboardItem] = []
        var approved: [DashboardItem] = []
        var hiddenReviews: [DashboardItem] = []
        var seen = Set<String>()

        // Hosts sortiert durchlaufen, damit gleiche Eingaben unabhängig von der Dictionary-
        // Reihenfolge gleiche Ergebnisse liefern (die Sortierung am Ende entscheidet ohnehin).
        for host in prs.snapshots.keys.sorted() {
            guard let snapshot = prs.snapshots[host] else { continue }
            for pr in snapshot.toReview {
                let key = "\(host)/\(pr.repository)"
                let item = reviewItem(pr, repoKey: key)
                guard seen.insert(item.id).inserted else { continue }
                if isHidden(key) {
                    if pr.needsMyReview { hiddenReviews.append(item) }
                    continue
                }
                switch item.urgency {
                case .extraRequest: waiting.append(item)
                case .codeOwnerRequest: codeOwner.append(item)
                default: approved.append(item)
                }
            }
            for pr in snapshot.mine {
                let key = "\(host)/\(pr.repository)"
                let item = mineItem(pr, repoKey: key)
                guard !isHidden(key), seen.insert(item.id).inserted else { continue }
                mine.append(item)
                if item.urgency == .ownActionNeeded { waiting.append(item) }
            }
        }

        let agentItems = agents.map(agentItem)
        waiting += agentItems.filter { $0.urgency == .agentWaiting }

        waiting.sort(by: DashboardItem.precedes)
        codeOwner.sort(by: DashboardItem.precedes)
        mine.sort(by: DashboardItem.precedes)
        approved.sort(by: DashboardItem.precedes)
        hiddenReviews.sort(by: DashboardItem.precedes)
        let sortedAgents = agentItems.sorted(by: DashboardItem.precedes)

        let partial = Dashboard(waiting: waiting, codeOwner: codeOwner, mine: mine, agents: sortedAgents,
                                approved: approved, hiddenReviews: hiddenReviews, repos: [],
                                hasPRData: !prs.snapshots.isEmpty, isStale: zone.isStale,
                                lastSuccess: zone.lastSuccess)
        // Repo-Zeilen in der Reihenfolge und Auswahl der PR-Tabelle (Board/Menü), damit alle drei
        // Ansichten dieselben Repos zeigen.
        let waitingIDs = Set(waiting.map(\.id))
        let repos = zone.rows.map { row -> DashboardRepo in
            let items = partial.items(inRepo: row.repoKey)
            return DashboardRepo(repoKey: row.repoKey, name: row.repository, count: items.count,
                                 hasWaiting: items.contains { waitingIDs.contains($0.id) })
        }
        return Dashboard(waiting: waiting, codeOwner: codeOwner, mine: mine, agents: sortedAgents,
                         approved: approved, hiddenReviews: hiddenReviews, repos: repos,
                         hasPRData: partial.hasPRData, isStale: partial.isStale, lastSuccess: partial.lastSuccess)
    }

    // MARK: Einträge bilden

    static func reviewItem(_ pr: PullRequest, repoKey: String) -> DashboardItem {
        let urgency: DashboardUrgency
        var tags: [DashboardTag] = []
        if pr.needsMyReview && pr.hasExtraRequestForMe {
            urgency = .extraRequest
            tags.append(.extra)
        } else if pr.needsMyReview {
            urgency = .codeOwnerRequest
            tags.append(.codeOwner)
        } else {
            urgency = .alreadyReviewed
        }
        return DashboardItem(subject: .pullRequest(pr, repoKey: repoKey, isMine: false), urgency: urgency,
                             tags: tags + commonTags(pr))
    }

    static func mineItem(_ pr: PullRequest, repoKey: String) -> DashboardItem {
        let actionNeeded = (pr.ciFailing && !pr.isDraft) || pr.reviewDecision == .changesRequested
        return DashboardItem(subject: .pullRequest(pr, repoKey: repoKey, isMine: true),
                             urgency: actionNeeded ? .ownActionNeeded : .ownPR, tags: commonTags(pr))
    }

    private static func commonTags(_ pr: PullRequest) -> [DashboardTag] {
        var tags: [DashboardTag] = []
        if pr.ciFailing && !pr.isDraft { tags.append(.ciFailing) }
        if pr.reviewDecision == .changesRequested { tags.append(.changesRequested) }
        if pr.mergeable == .conflicting { tags.append(.conflict) }
        if pr.isDraft { tags.append(.draft) }
        return tags
    }

    static func agentItem(_ agent: AgentActivity) -> DashboardItem {
        let urgency: DashboardUrgency
        let tags: [DashboardTag]
        switch agent.state {
        case .waiting: urgency = .agentWaiting; tags = [.agentWaiting]
        case .error: urgency = .agentError; tags = [.agentError]
        case .running where agent.isStale: urgency = .agentStale; tags = [.agentStale]
        case .running: urgency = .agentRunning; tags = []
        case .done: urgency = .agentDone; tags = []
        }
        return DashboardItem(subject: .agent(agent), urgency: urgency, tags: tags)
    }
}

/// Entscheidet, ob die Menüleisten-App ein Dock-Symbol zeigt (status-display#24, Wunsch Florian
/// vom 28.09.2026): solange das Dashboard- oder das Board-Fenster offen ist, sonst nicht – dann
/// bleibt sie reine Menüleisten-App (`LSUIElement`).
public enum DockIconPolicy {
    public static func showsDockIcon(dashboardOpen: Bool, boardWindowOpen: Bool) -> Bool {
        dashboardOpen || boardWindowOpen
    }
}
