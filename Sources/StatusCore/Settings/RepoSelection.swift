import Foundation

/// Zustand eines Repos in der Auswahl-UI des Einstellungs-Reiters „Repos“ (#15).
public enum RepoState: Equatable, Hashable {
    case normal, pinned, hidden
}

/// Standard-Zustand für Repos ohne expliziten Eintrag in `pinnedRepos`/`hiddenRepos`/`shownRepos`,
/// pro Host (`AppSettings.hostDefaults`). Siehe `RepoSelection.hostDefault(for:hostDefaults:)` für
/// die feste Regel, welcher Standard gilt.
public enum RepoDefault: String, Codable, Equatable {
    case normal, hidden
}

/// Reine Auswahl-Logik für den Reiter „Repos“: Zustand ablesen/setzen, Suche/Filter, Anzeigegrenze.
/// Trägt keine Netzwerk- oder Dateizugriffe (die liegen in `RepoCatalogService`/`AppSupport`), damit
/// sie ohne beides testbar ist. Schlüssel sind durchgehend `host/owner/name`
/// (siehe `AppSettings.pinnedRepos`/`hiddenRepos`/`shownRepos`), Repo-Namen aus dem Katalog `owner/name`.
///
/// Drei explizite Zustände (normal/angeheftet/ausgeblendet), exklusiv über `pinnedRepos`/
/// `hiddenRepos`/`shownRepos`: ein Repo steht nie in mehr als einer dieser Listen. Ohne Eintrag in
/// irgendeiner der drei Listen gilt der Host-Standard aus `hostDefaults` (Entscheidung Florian,
/// 28.09.2026, status-display#19).
public enum RepoSelection {
    /// Ab dieser Trefferzahl wird die Liste in der UI gekürzt (Performance bei Hunderten Repos).
    public static let displayLimit = 200

    /// Der wirksame Standard für `host`, wenn `hostDefaults` (noch) keinen Eintrag für ihn hat:
    /// `github.com` ist normal, jeder andere Host ist ausgeblendet. Das ist dieselbe Regel, die
    /// beim Dekodieren alter Einstellungen (`AppSettings.init(from:)`) und beim Hinzufügen eines
    /// neuen Hosts (`AppSettings.addHost`) den Eintrag in `hostDefaults` setzt – hier noch einmal
    /// als Fallback, falls für einen konfigurierten Host aus irgendeinem Grund kein Eintrag existiert.
    public static func hostDefault(for host: String, hostDefaults: [String: RepoDefault]) -> RepoDefault {
        hostDefaults[host] ?? (host == "github.com" ? .normal : .hidden)
    }

    /// Löst den tatsächlichen Zustand für `repoKey` auf: explizite Listen zuerst
    /// (angeheftet, dann ausgeblendet, dann explizit normal), sonst der Host-Standard.
    public static func state(for repoKey: String, host: String, pinned: [String], hidden: [String],
                             shown: [String], hostDefaults: [String: RepoDefault]) -> RepoState {
        if pinned.contains(repoKey) { return .pinned }
        if hidden.contains(repoKey) { return .hidden }
        if shown.contains(repoKey) { return .normal }
        return hostDefault(for: host, hostDefaults: hostDefaults) == .hidden ? .hidden : .normal
    }

    /// Setzt den Zustand für `repoKey` und hält `pinnedRepos`/`hiddenRepos`/`shownRepos` dabei
    /// exklusiv: ein Repo steht nie in mehr als einer der drei Listen. Entspricht der neue Zustand
    /// bereits dem Host-Standard, landet `repoKey` in keiner Liste – so folgen später hinzugefügte
    /// bzw. dort neu erscheinende Repos automatisch dem Standard, statt an einem veralteten
    /// expliziten Eintrag festzuhängen.
    public static func setState(_ state: RepoState, for repoKey: String, host: String, pinned: [String],
                                hidden: [String], shown: [String], hostDefaults: [String: RepoDefault])
        -> (pinned: [String], hidden: [String], shown: [String]) {
        var p = pinned.filter { $0 != repoKey }
        var h = hidden.filter { $0 != repoKey }
        var s = shown.filter { $0 != repoKey }
        let def = hostDefault(for: host, hostDefaults: hostDefaults)
        switch state {
        case .normal: if def == .hidden { s.append(repoKey) }
        case .pinned: p.append(repoKey)
        case .hidden: if def != .hidden { h.append(repoKey) }
        }
        return (p, h, s)
    }

    /// Wendet `state` auf alle `names` (`owner/name`, aus dem Repo-Katalog für `host`) an – für die
    /// Sammelaktion im Reiter „Repos“: alle aktuellen Suchtreffer auf einmal, nicht nur die (auf
    /// `displayLimit` gekürzt) angezeigten.
    public static func setStateForAll(_ state: RepoState, names: [String], host: String, pinned: [String],
                                      hidden: [String], shown: [String], hostDefaults: [String: RepoDefault])
        -> (pinned: [String], hidden: [String], shown: [String]) {
        var p = pinned, h = hidden, s = shown
        for name in names {
            (p, h, s) = setState(state, for: "\(host)/\(name)", host: host, pinned: p, hidden: h, shown: s,
                                 hostDefaults: hostDefaults)
        }
        return (p, h, s)
    }

    /// Teilstring-Suche über `owner/name`, case-insensitive. Leere/nur-Leerzeichen-Suche liefert alles.
    public static func filter(_ repos: [String], query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return repos }
        return repos.filter { $0.lowercased().contains(q) }
    }

    /// `host/owner/name` -> `owner/name`, oder nil, wenn `key` nicht zu `host` gehört oder nach dem
    /// Host-Präfix nichts mehr übrig ist.
    public static func repository(forKey key: String, host: String) -> String? {
        let prefix = host + "/"
        guard key.hasPrefix(prefix) else { return nil }
        let rest = String(key.dropFirst(prefix.count))
        return rest.isEmpty ? nil : rest
    }
}
