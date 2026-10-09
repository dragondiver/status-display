import Foundation

/// Führt die Hosts zusammen, bildet die Zeilen der PR-Tabelle und entscheidet,
/// wann die PR-Zone veraltet ist.
public struct PRAggregator {
    public static let refreshInterval: TimeInterval = 120

    public private(set) var snapshots: [String: PRSnapshot] = [:]
    public private(set) var errors: [String: GitHubError] = [:]

    public init() {}

    public mutating func record(_ snapshot: PRSnapshot) {
        snapshots[snapshot.host] = snapshot
        errors[snapshot.host] = nil
    }

    public mutating func record(_ error: GitHubError, host: String) { errors[host] = error }

    public mutating func retain(hosts: [String]) {
        let keep = Set(hosts)
        snapshots = snapshots.filter { keep.contains($0.key) }
        errors = errors.filter { keep.contains($0.key) }
    }

    /// `hosts` sind die konfigurierten Hosts: Fehlt für einen davon noch jeder Erfolg,
    /// ist die Zone veraltet (grau), statt ihn stillschweigend wegzulassen.
    ///
    /// `pinned`, `hidden` und `shown` sind Einträge der Form `host/owner/name` (siehe
    /// `AppSettings.pinnedRepos`/`hiddenRepos`/`shownRepos`), `hostDefaults` der Host-Standard
    /// (`AppSettings.hostDefaults`). Angeheftete Repos erscheinen immer, auch mit 0/0; andere Repos
    /// nur, sobald dort ein Review-Request oder ein eigener offener PR liegt (auch ein Draft; der
    /// zählt aber nicht in `PRRow.mine`, status-display#44). Ausgeblendet ist ein
    /// Repo, wenn es explizit in `hidden` steht (das gilt auch, wenn es – inkonsistenterweise –
    /// zugleich angeheftet wäre), oder wenn keine der drei Listen einen Eintrag für es hat und der
    /// Host-Standard „ausgeblendet“ ist. Sortierung der sichtbaren Zeilen: zuerst `toReview > 0`,
    /// dann angeheftete, dann der Rest – innerhalb einer Gruppe alphabetisch nach `repoKey`.
    ///
    /// `PRZone.hiddenReviews` sammelt die Review-Requests aus ausgeblendeten Repos (Entscheidung
    /// Florian, 28.09.2026, status-display#19); eigene offene PRs aus ausgeblendeten Repos tauchen
    /// nirgends mehr auf.
    ///
    /// Review-Requests, für die `PullRequest.needsMyReview == false` ist, zählen nirgends mehr als
    /// „zu reviewen“ (weder in `rows[].toReview` noch in `hiddenReviews`) – Entscheidung Florian,
    /// 28.09.2026, status-display#21 (verfeinert im selben Issue: nicht mehr `reviewDecision ==
    /// APPROVED`, sondern Code-Owner- vs. Extra-Anfrage, siehe `PullRequest.needsMyReview`). Sie
    /// tauchen stattdessen als `PRRow.approvedReviews` pro (nicht ausgeblendetem) Repo auf, damit
    /// das Menü sie in einem eigenen Abschnitt „schon freigegeben“ zeigen kann; ein Repo ganz ohne
    /// offene eigene PRs, dessen einzige Review-Requests so schon erledigt sind, bekommt dadurch
    /// keine `Acc`-Zeile und verschwindet aus der Tabelle (außer es ist angeheftet). In
    /// ausgeblendeten Repos werden solche Review-Requests nicht gesondert aufbewahrt – wie eigene
    /// offene PRs verschwinden sie dort ganz.
    ///
    /// `PRRow.hasExtraReview` markiert eine Zeile, sobald mindestens einer der gezählten
    /// Review-Requests eine Extra-Anfrage (`hasExtraRequestForMe`) ist – der Renderer färbt die
    /// Review-Zahl dann orange, ebenso `hiddenReviews`-Konsumenten für die Hinweiszeile.
    public func zone(now: Date, hosts: [String], pinned: [String] = [], hidden: [String] = [],
                     shown: [String] = [], hostDefaults: [String: RepoDefault] = [:]) -> PRZone {
        let all = Array(snapshots.values)
        guard let oldest = all.map(\.fetchedAt).min() else { return .unknown }
        let missingHost = hosts.contains { snapshots[$0] == nil }

        struct Acc { var repository: String; var toReview = 0; var mine = 0; var ciFailing = false; var ciFailingCount = 0; var hasExtraReview = false }
        var acc: [String: Acc] = [:]
        var reviewsByKey: [String: [PullRequest]] = [:]
        var approvedByKey: [String: [PullRequest]] = [:]

        for snapshot in all {
            for pr in snapshot.toReview {
                let key = repoKey(host: snapshot.host, repository: pr.repository)
                if pr.needsMyReview {
                    acc[key, default: Acc(repository: pr.repository)].toReview += 1
                    if pr.hasExtraRequestForMe { acc[key, default: Acc(repository: pr.repository)].hasExtraReview = true }
                    reviewsByKey[key, default: []].append(pr)
                } else {
                    approvedByKey[key, default: []].append(pr)
                }
            }
            for pr in snapshot.mine {
                let key = repoKey(host: snapshot.host, repository: pr.repository)
                // Die Zeile entsteht für jeden eigenen PR, auch für einen Draft; nur die Zahl
                // „eigene offen“ zählt keine Drafts (Entscheidung Florian, 29.09.2026,
                // status-display#44). Ein Repo nur mit Drafts steht also mit `mine == 0` da.
                acc[key, default: Acc(repository: pr.repository)].mine += pr.isDraft ? 0 : 1
                if pr.ciFailing && !pr.isDraft {
                    acc[key, default: Acc(repository: pr.repository)].ciFailing = true
                    acc[key, default: Acc(repository: pr.repository)].ciFailingCount += 1
                }
            }
        }

        let pinnedSet = Set(pinned)
        for key in pinnedSet where acc[key] == nil {
            guard let repository = Self.repository(forKey: key) else { continue }
            acc[key] = Acc(repository: repository)
        }

        let hiddenSet = Set(hidden)
        let hostDefaultHidden = acc.keys.filter { key in
            Self.isHidden(repoKey: key, pinned: pinned, hidden: hidden, shown: shown, hostDefaults: hostDefaults)
        }
        let effectivelyHidden = hiddenSet.union(hostDefaultHidden)

        var hiddenReviews: [PullRequest] = []
        for key in effectivelyHidden {
            hiddenReviews += reviewsByKey[key] ?? []
            acc.removeValue(forKey: key)
            approvedByKey.removeValue(forKey: key)
        }
        hiddenReviews.sort { $0.repository != $1.repository ? $0.repository < $1.repository : $0.number < $1.number }

        // Erst nach dem Ausblenden zählen: Board und Dashboard zeigen dieselbe Zahl (status-display#31).
        let totalCIFailing = acc.values.reduce(0) { $0 + $1.ciFailingCount }

        let rows = acc.map { key, a in
            let approved = (approvedByKey[key] ?? []).sorted { $0.number < $1.number }
            return PRRow(repoKey: key, repository: Self.shortName(a.repository),
                        toReview: a.toReview, mine: a.mine, ciFailing: a.ciFailing, approvedReviews: approved,
                        hasExtraReview: a.hasExtraReview)
        }
        let sorted = rows.sorted { lhs, rhs in
            let l = group(lhs, pinned: pinnedSet), r = group(rhs, pinned: pinnedSet)
            return l != r ? l < r : lhs.repoKey < rhs.repoKey
        }

        return PRZone(rows: sorted, ciFailingCount: totalCIFailing, lastSuccess: oldest,
                      isStale: missingHost || now.timeIntervalSince(oldest) > 3 * Self.refreshInterval,
                      hiddenReviews: hiddenReviews)
    }

    /// Ist `repoKey` (`host/owner/name`) ausgeblendet? Explizit in `hidden` (gewinnt auch gegen
    /// ein inkonsistentes gleichzeitiges Anheften), oder ohne jeden expliziten Eintrag (weder
    /// angeheftet noch ausgeblendet noch ausdrücklich normal) über den Host-Standard. Dieselbe
    /// Regel, die `zone` anwendet – öffentlich, damit das Dashboard (status-display#24) sie nicht
    /// nachbauen muss.
    public static func isHidden(repoKey key: String, pinned: [String], hidden: [String], shown: [String],
                                hostDefaults: [String: RepoDefault]) -> Bool {
        if hidden.contains(key) { return true }
        guard !pinned.contains(key), !shown.contains(key), let host = host(ofKey: key) else { return false }
        return RepoSelection.hostDefault(for: host, hostDefaults: hostDefaults) == .hidden
    }

    private func group(_ row: PRRow, pinned: Set<String>) -> Int {
        if row.toReview > 0 { return 0 }
        if pinned.contains(row.repoKey) { return 1 }
        return 2
    }

    private func repoKey(host: String, repository: String) -> String { "\(host)/\(repository)" }

    /// Löst `host/owner/name` in `owner/name` auf (für angeheftete Repos ohne eigene PRs,
    /// bei denen es noch keinen Snapshot-Eintrag gibt).
    private static func repository(forKey key: String) -> String? {
        guard let slash = key.firstIndex(of: "/") else { return nil }
        let repository = String(key[key.index(after: slash)...])
        return repository.isEmpty ? nil : repository
    }

    /// Löst `host/owner/name` in `host` auf.
    private static func host(ofKey key: String) -> String? {
        guard let slash = key.firstIndex(of: "/") else { return nil }
        return String(key[..<slash])
    }

    private static func shortName(_ nameWithOwner: String) -> String {
        nameWithOwner.split(separator: "/").last.map(String.init) ?? nameWithOwner
    }
}
