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
    /// Absoluter Pfad des Arbeitsverzeichnisses (Hook: `cwd`, MCP: `path`), nur fürs Dashboard.
    public var path: String?
    /// Letzter Prompt der Sitzung (Hook `UserPromptSubmit`), nur fürs Dashboard.
    public var prompt: String?

    public init(source: String, session: String, state: String, name: String? = nil,
                project: String? = nil, detail: String? = nil, url: String? = nil,
                path: String? = nil, prompt: String? = nil) {
        self.source = source; self.session = session; self.state = state
        self.name = name; self.project = project; self.detail = detail; self.url = url
        self.path = path; self.prompt = prompt
    }

    /// `ended` entfernt den Eintrag; alle anderen entsprechen `AgentState`.
    public static let states = ["running", "waiting", "done", "error", "ended"]

    public func validate() throws {
        if source.isEmpty { throw AgentEventError.missingField("source") }
        if session.isEmpty { throw AgentEventError.missingField("session") }
        guard Self.states.contains(state) else { throw AgentEventError.unknownState(state) }
        // Git und „Im Finder zeigen“ brauchen einen absoluten Pfad; ein relativer hinge vom
        // Arbeitsverzeichnis der App ab. Leer zählt als „nicht angegeben“.
        if let path, !path.isEmpty, !path.hasPrefix("/") { throw AgentEventError.relativePath(path) }
    }
}

public enum AgentEventError: Error, Equatable {
    case missingField(String)
    case unknownState(String)
    case relativePath(String)

    public var message: String {
        switch self {
        case .missingField(let f): return "Feld fehlt: \(f)"
        case .unknownState(let s): return "unbekannter Zustand: \(s) (erlaubt: \(AgentEvent.states.joined(separator: ", ")))"
        case .relativePath(let p): return "path muss ein absoluter Pfad sein (beginnt mit /): \(p)"
        }
    }
}
