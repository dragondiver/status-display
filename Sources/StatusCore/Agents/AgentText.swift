import Foundation

/// Texte zu einem Agenten, die nur das Dashboard zeigt (status-display#52). Reine Funktionen.
public enum AgentText {
    /// Höchstlänge des gemerkten Prompts in Zeichen (Entscheidung Florian, 15.10.2026: „rund 300“).
    public static let promptLimit = 300

    /// Die ersten `limit` Zeichen eines Prompts, der Rest wird zu „…“. Zeilenumbrüche im Text
    /// bleiben, nur Leerraum am Anfang und Ende fällt weg. Leer oder fehlend → nil, damit ein
    /// späteres Ereignis ohne Prompt den alten nicht löscht.
    ///
    /// Mehrfach angewandt ändert sich nichts mehr: Der Hook kürzt schon vor dem Senden (ein
    /// eingefügtes Log darf das Ereignis nicht über die Größengrenze des Servers heben), die
    /// Registry kürzt noch einmal für Meldungen, die direkt an `/v1/events` gehen.
    public static func promptExcerpt(_ prompt: String?, limit: Int = promptLimit) -> String? {
        guard let text = prompt?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        guard text.count > limit else { return text }
        let head = String(text.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
        return head + "…"
    }

    /// Home-Verzeichnis als „~“: `/Users/name/Development/beispiel` → `~/Development/beispiel`.
    /// Nur ganze Pfadteile: `/Users/name2` bleibt bei Home `/Users/name` unverändert.
    public static func abbreviatingHome(_ path: String, home: String) -> String {
        var home = home
        while home.count > 1 && home.hasSuffix("/") { home.removeLast() }
        guard !home.isEmpty, home != "/" else { return path }
        if path == home { return "~" }
        guard path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
