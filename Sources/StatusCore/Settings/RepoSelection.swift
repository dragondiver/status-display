import Foundation

/// Zustand eines Repos in der Auswahl-UI des Einstellungs-Reiters „Repos“ (#15).
public enum RepoState: Equatable, Hashable {
    case normal, pinned, hidden
}

/// Reine Auswahl-Logik für den Reiter „Repos“: Zustand ablesen/setzen, Suche/Filter, Anzeigegrenze.
/// Trägt keine Netzwerk- oder Dateizugriffe (die liegen in `RepoCatalogService`/`AppSupport`), damit
/// sie ohne beides testbar ist. Schlüssel sind durchgehend `host/owner/name`
/// (siehe `AppSettings.pinnedRepos`/`hiddenRepos`), Repo-Namen aus dem Katalog `owner/name`.
public enum RepoSelection {
    /// Ab dieser Trefferzahl wird die Liste in der UI gekürzt (Performance bei Hunderten Repos).
    public static let displayLimit = 200

    public static func state(for repoKey: String, pinned: [String], hidden: [String]) -> RepoState {
        if pinned.contains(repoKey) { return .pinned }
        if hidden.contains(repoKey) { return .hidden }
        return .normal
    }

    /// Setzt den Zustand für `repoKey` und hält `pinnedRepos`/`hiddenRepos` dabei exklusiv:
    /// ein Repo steht nie in beiden Listen gleichzeitig.
    public static func setState(_ state: RepoState, for repoKey: String,
                                pinned: [String], hidden: [String]) -> (pinned: [String], hidden: [String]) {
        var p = pinned.filter { $0 != repoKey }
        var h = hidden.filter { $0 != repoKey }
        switch state {
        case .normal: break
        case .pinned: p.append(repoKey)
        case .hidden: h.append(repoKey)
        }
        return (p, h)
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
