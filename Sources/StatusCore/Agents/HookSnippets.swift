import Foundation

/// Konfigurationsblöcke, die die Einstellungen zum Kopieren anzeigen. Die App schreibt keine fremden Dateien.
public enum HookSnippets {
    /// Für ~/.claude/settings.json
    public static let claudeEvents = ["SessionStart", "UserPromptSubmit", "PostToolUse", "Notification", "Stop", "SessionEnd"]
    /// Für ~/.codex/hooks.json
    public static let codexEvents = ["SessionStart", "UserPromptSubmit", "PostToolUse", "PermissionRequest", "Stop", "SessionEnd"]

    /// Für ~/.codex/config.toml: Hooks sind in Codex standardmäßig aktiv, dieser Block ist nur
    /// zur Sicherheit gedacht, falls eine andere Konfiguration sie zuvor abgeschaltet hat
    /// (`[features] hooks = false`). Laut https://developers.openai.com/codex/hooks (Stand 27.09.2026)
    /// gibt es keinen Schalter zum expliziten Einschalten, nur einen zum Abschalten.
    public static let codexFeatureFlag = "[features]\nhooks = true"

    public static func hooksJSON(executable: String, source: String, events: [String]) -> String {
        let command = "'\(executable)' hook \(source)"
        var hooks: [String: Any] = [:]
        for event in events {
            hooks[event] = [["hooks": [["type": "command", "command": command, "timeout": 2]]]]
        }
        return pretty(["hooks": hooks])
    }

    /// Eintrag für MCP-Konfigurationen (VS Code/Copilot u. a.); das Format der Hülle variiert je Client.
    public static func mcpJSON(port: UInt16, token: String) -> String {
        pretty(["status-display": [
            "type": "http",
            "url": "http://127.0.0.1:\(port)/mcp",
            "headers": ["Authorization": "Bearer \(token)"],
        ] as [String: Any]])
    }

    private static func pretty(_ object: Any) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object,
                                               options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }
}
