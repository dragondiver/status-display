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
    /// `pinned` und `hidden` sind Einträge der Form `host/owner/name` (siehe
    /// `AppSettings.pinnedRepos`/`hiddenRepos`). Angeheftete Repos erscheinen immer, auch mit
    /// 0/0; andere Repos nur, sobald dort ein Review-Request oder ein eigener offener PR liegt;
    /// ausgeblendete Repos nie. Sortierung: zuerst Zeilen mit `toReview > 0`, dann angeheftete,
    /// dann der Rest – innerhalb einer Gruppe alphabetisch nach `repoKey` für stabile Ausgabe.
    public func zone(now: Date, hosts: [String], pinned: [String] = [], hidden: [String] = []) -> PRZone {
        let all = Array(snapshots.values)
        guard let oldest = all.map(\.fetchedAt).min() else { return .unknown }
        let missingHost = hosts.contains { snapshots[$0] == nil }

        struct Acc { var repository: String; var toReview = 0; var mine = 0; var ciFailing = false }
        var acc: [String: Acc] = [:]
        var totalCIFailing = 0

        for snapshot in all {
            for pr in snapshot.toReview {
                let key = repoKey(host: snapshot.host, repository: pr.repository)
                acc[key, default: Acc(repository: pr.repository)].toReview += 1
            }
            for pr in snapshot.mine {
                let key = repoKey(host: snapshot.host, repository: pr.repository)
                acc[key, default: Acc(repository: pr.repository)].mine += 1
                if pr.ciFailing && !pr.isDraft {
                    acc[key, default: Acc(repository: pr.repository)].ciFailing = true
                    totalCIFailing += 1
                }
            }
        }

        let hiddenSet = Set(hidden)
        let pinnedSet = Set(pinned)
        for key in pinnedSet where acc[key] == nil {
            guard let repository = Self.repository(forKey: key) else { continue }
            acc[key] = Acc(repository: repository)
        }
        for key in hiddenSet { acc.removeValue(forKey: key) }

        let rows = acc.map { key, a in
            PRRow(repoKey: key, repository: Self.shortName(a.repository),
                  toReview: a.toReview, mine: a.mine, ciFailing: a.ciFailing)
        }
        let sorted = rows.sorted { lhs, rhs in
            let l = group(lhs, pinned: pinnedSet), r = group(rhs, pinned: pinnedSet)
            return l != r ? l < r : lhs.repoKey < rhs.repoKey
        }

        return PRZone(rows: sorted, ciFailingCount: totalCIFailing, lastSuccess: oldest,
                      isStale: missingHost || now.timeIntervalSince(oldest) > 3 * Self.refreshInterval)
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

    private static func shortName(_ nameWithOwner: String) -> String {
        nameWithOwner.split(separator: "/").last.map(String.init) ?? nameWithOwner
    }
}
