import CoreGraphics
import Foundation

public enum BoardText {
    public static func since(_ start: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(start) / 60))
        return minutes < 60 ? "seit \(minutes) min" : String(format: "seit %d:%02d h", minutes / 60, minutes % 60)
    }

    public static func agentLabel(_ a: AgentActivity, now: Date) -> String {
        if a.isStale { return "unklar" }
        switch a.state {
        case .running: return "läuft"
        case .waiting: return "wartet \(max(0, Int(now.timeIntervalSince(a.since) / 60))) min"
        case .error: return "Fehler"
        case .done: return "fertig"
        }
    }

    public static func truncate(_ s: String, max: Int) -> String {
        s.count <= max ? s : String(s.prefix(max - 1)) + "…"
    }

    /// Höchstens `maxRows` Zeilen; bei Überlauf eine Zeile weniger plus „+N weitere“.
    public static func visibleAgents(_ agents: [AgentActivity], maxRows: Int = 4) -> (rows: [AgentActivity], more: Int) {
        guard agents.count > maxRows else { return (agents, 0) }
        return (Array(agents.prefix(maxRows - 1)), agents.count - (maxRows - 1))
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
