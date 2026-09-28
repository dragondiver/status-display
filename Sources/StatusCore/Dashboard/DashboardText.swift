import Foundation

/// Texte für Liste und Detailspalte des Dashboard-Fensters (status-display#24). Reine Funktionen,
/// damit Formulierungen und Grenzfälle (fehlende Felder) ohne UI testbar sind.
public enum DashboardText {
    /// Leerzustand des Agenten-Abschnitts der Seitenleiste, grau statt Sammel-Eintrag mit 0
    /// (Entscheidung Florian, 28.09.2026, status-display#39).
    public static let noActiveAgents = "Keine aktiven Agenten"

    /// Kurzes Alter für die Liste: „12 min“, „3 h“, „2 T“.
    public static func shortAge(from start: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(start) / 60))
        if minutes < 60 { return "\(minutes) min" }
        if minutes < 24 * 60 { return "\(minutes / 60) h" }
        return "\(minutes / (24 * 60)) T"
    }

    /// Ausgeschriebenes Alter für die Details: „gerade eben“, „vor 5 Minuten“, „vor 1 Stunde“,
    /// „vor 2 Tagen“.
    public static func longAge(from start: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(start) / 60))
        if minutes < 1 { return "gerade eben" }
        if minutes < 60 { return minutes == 1 ? "vor 1 Minute" : "vor \(minutes) Minuten" }
        let hours = minutes / 60
        if hours < 24 { return hours == 1 ? "vor 1 Stunde" : "vor \(hours) Stunden" }
        let days = hours / 24
        return days == 1 ? "vor 1 Tag" : "vor \(days) Tagen"
    }

    /// „Warum bei dir“.
    public static func reason(_ pr: PullRequest, isMine: Bool) -> String {
        if isMine { return "dein PR" }
        if pr.needsMyReview && pr.hasExtraRequestForMe { return "ausdrücklich als Reviewer angefragt" }
        if pr.needsMyReview { return "als Code-Owner angefragt, noch niemand hat reviewt" }
        return "als Code-Owner angefragt, schon von anderen reviewt"
    }

    /// „Autor“: Anzeigename, sonst Login, sonst „unbekannt“, dazu das Alter, falls bekannt.
    public static func author(_ pr: PullRequest, now: Date) -> String {
        let who = pr.authorName ?? pr.authorLogin ?? "unbekannt"
        guard let created = pr.createdAt else { return who }
        return "\(who) · \(longAge(from: created, now: now))"
    }

    /// „Reviews“: je Reviewer der letzte Zustand, z. B. „alice hat freigegeben · bob hat Änderungen
    /// angefordert“.
    public static func reviews(_ pr: PullRequest) -> String {
        let relevant = pr.reviews.filter { $0.state != .pending }
        guard !relevant.isEmpty else { return "noch keine Reviews" }
        return relevant.map { review in
            switch review.state {
            case .approved: return "\(review.login) hat freigegeben"
            case .changesRequested: return "\(review.login) hat Änderungen angefordert"
            case .commented: return "\(review.login) hat kommentiert"
            case .dismissed: return "\(review.login) (Review verworfen)"
            case .pending: return "\(review.login) (Entwurf)"
            }
        }.joined(separator: " · ")
    }

    /// „CI“: „8 von 8 grün“, „2 rot · 5 grün · 1 offen“, „keine Checks“, oder nur der Gesamtzustand,
    /// wenn die Einzelzählung fehlt.
    public static func checks(_ pr: PullRequest) -> String {
        guard let c = pr.checks else { return pr.ciFailing ? "rot" : "keine Angaben" }
        if c.total == 0 { return "keine Checks" }
        if c.failed == 0 && c.other == 0 { return "\(c.passed) von \(c.total) grün" }
        var parts: [String] = []
        if c.failed > 0 { parts.append("\(c.failed) rot") }
        if c.passed > 0 { parts.append("\(c.passed) grün") }
        if c.other > 0 { parts.append("\(c.other) offen") }
        return parts.joined(separator: " · ")
    }

    /// „Änderungen“: „5 Dateien · +7 −7“ – fehlende Teile entfallen, ganz ohne Angaben „unbekannt“.
    public static func size(_ pr: PullRequest) -> String {
        var parts: [String] = []
        if let files = pr.changedFiles { parts.append(files == 1 ? "1 Datei" : "\(files) Dateien") }
        if let add = pr.additions, let del = pr.deletions { parts.append("+\(add) −\(del)") }
        return parts.isEmpty ? "unbekannt" : parts.joined(separator: " · ")
    }

    /// „Merge“: nur bei bekanntem Zustand ein Text, sonst nil (GitHub rechnet noch).
    public static func merge(_ pr: PullRequest) -> String? {
        switch pr.mergeable {
        case .conflicting: return "Merge-Konflikt"
        case .mergeable: return "konfliktfrei"
        case .unknown, nil: return nil
        }
    }
}
