import Foundation

/// Eine Meldung eines Agenten, egal ob per Hook, HTTP oder MCP.
public struct AgentEvent: Codable, Equatable {
    public var source: String
    public var session: String
    public var state: String
    public var name: String?
    public var project: String?
    public var detail: String?
    public var url: String?

    public init(source: String, session: String, state: String, name: String? = nil,
                project: String? = nil, detail: String? = nil, url: String? = nil) {
        self.source = source; self.session = session; self.state = state
        self.name = name; self.project = project; self.detail = detail; self.url = url
    }

    /// `ended` entfernt den Eintrag; alle anderen entsprechen `AgentState`.
    public static let states = ["running", "waiting", "done", "error", "ended"]

    public func validate() throws {
        if source.isEmpty { throw AgentEventError.missingField("source") }
        if session.isEmpty { throw AgentEventError.missingField("session") }
        guard Self.states.contains(state) else { throw AgentEventError.unknownState(state) }
    }
}

public enum AgentEventError: Error, Equatable {
    case missingField(String)
    case unknownState(String)

    public var message: String {
        switch self {
        case .missingField(let f): return "Feld fehlt: \(f)"
        case .unknownState(let s): return "unbekannter Zustand: \(s) (erlaubt: \(AgentEvent.states.joined(separator: ", ")))"
        }
    }
}
