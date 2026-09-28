import CoreGraphics
import Foundation

public enum BoardText {
    public static func since(_ start: Date, now: Date) -> String {
        "seit " + duration(from: start, to: now)
    }

    /// „47 min“ bzw. ab einer Stunde „2:05 h“.
    static func duration(from start: Date, to now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(start) / 60))
        return minutes < 60 ? "\(minutes) min" : String(format: "%d:%02d h", minutes / 60, minutes % 60)
    }

    public static func agentLabel(_ a: AgentActivity, now: Date) -> String {
        if a.isStale { return "unklar seit " + duration(from: a.lastSeen, to: now) }
        switch a.state {
        case .running: return "läuft"
        case .waiting: return "wartet " + duration(from: a.since, to: now)
        case .error: return "Fehler"
        case .done: return "fertig"
        }
    }

    public static func truncate(_ s: String, max: Int) -> String {
        s.count <= max ? s : String(s.prefix(max - 1)) + "…"
    }

    /// Höchstens `maxRows` Zeilen; bei Überlauf eine Zeile weniger plus „+N weitere”.
    public static func visibleAgents(_ agents: [AgentActivity], maxRows: Int = 4) -> (rows: [AgentActivity], more: Int) {
        guard agents.count > maxRows else { return (agents, 0) }
        return (Array(agents.prefix(maxRows - 1)), agents.count - (maxRows - 1))
    }

    /// Höchstens `maxRows` Zeilen der PR-Tabelle; bei Überlauf eine Zeile weniger plus
    /// „+N weitere” (gleiches Prinzip wie `visibleAgents`).
    ///
    /// Ist `hiddenReviewCount > 0`, wird für die Hinweiszeile „Ausgeblendet · N zu reviewen“
    /// immer eine eigene, letzte Zeile reserviert (eine weniger für `rows`/„+N weitere“), statt
    /// sie selbst der Kürzung zu unterwerfen – sie soll nie abgeschnitten werden (Entscheidung
    /// Florian, 28.09.2026, status-display#19).
    public static func visiblePRRows(_ rows: [PRRow], hiddenReviewCount: Int = 0, maxRows: Int = 5)
        -> (rows: [PRRow], more: Int, hiddenHint: String?) {
        let hint = hiddenReviewCount > 0 ? "Ausgeblendet · \(hiddenReviewCount) zu reviewen" : nil
        let available = max(hint != nil ? maxRows - 1 : maxRows, 0)
        guard rows.count > available else { return (rows, 0, hint) }
        let shown = max(available - 1, 0)
        return (Array(rows.prefix(shown)), rows.count - shown, hint)
    }

    /// Grobe Breitenschätzung für fette Großbuchstaben (0,68 × Schriftgröße je Zeichen).
    public static func statusFontSize(for word: String, width: CGFloat, maxSize: CGFloat) -> CGFloat {
        let estimated = width / (0.68 * CGFloat(max(word.count, 1)))
        return min(maxSize, estimated.rounded(.down))
    }

    public static func clock(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.timeZone = timeZone
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
