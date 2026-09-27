import Foundation

/// Übersetzt die stdin-Nutzlast von Claude-Code- und Codex-Hooks (gleiches Format) in ein Ereignis.
public enum HookEventMapper {
    public static func event(source: String, payload: Data) throws -> AgentEvent? {
        guard let obj = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            throw AgentEventError.missingField("payload")
        }
        guard let hook = obj["hook_event_name"] as? String, let session = obj["session_id"] as? String else {
            return nil
        }
        let project = (obj["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
        let state: String
        var detail: String?
        switch hook {
        case "SessionStart", "UserPromptSubmit", "PostToolUse":
            state = "running"
        case "Notification":
            let message = obj["message"] as? String
            let idle = obj["notification_type"] as? String == "idle_prompt"
                || (message?.contains("waiting for your input") ?? false)
            if idle { return nil } // nach Stop gilt „fertig“
            state = "waiting"
            detail = message
        case "PermissionRequest":
            state = "waiting"
            detail = (obj["tool_name"] as? String).map { "wartet auf Freigabe: \($0)" }
        case "Stop":
            state = "done"
        case "SessionEnd":
            state = "ended"
        default:
            return nil
        }
        return AgentEvent(source: source, session: session, state: state, name: project,
                          project: project, detail: detail)
    }
}
