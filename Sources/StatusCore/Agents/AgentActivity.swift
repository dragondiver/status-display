import Foundation

public enum AgentState: String, Codable {
    case running, waiting, done, error
}

public struct AgentActivity: Equatable, Identifiable {
    public let id: String
    public let source: String
    public var name: String
    public var project: String?
    public var state: AgentState
    public var since: Date
    public var detail: String?
    public var url: URL?
    /// Arbeitsverzeichnis, voller Pfad. Nur das Dashboard zeigt ihn (status-display#52).
    public var path: String?
    /// Letzter Prompt, schon gekürzt (`AgentText.promptExcerpt`). Nur das Dashboard zeigt ihn.
    public var prompt: String?
    public var lastSeen: Date
    /// Nur für `.running`: seit `AgentRegistry.staleAfter` keine Meldung.
    public var isStale: Bool = false

    public init(id: String, source: String, name: String, project: String? = nil, state: AgentState,
                since: Date, detail: String? = nil, url: URL? = nil, path: String? = nil, prompt: String? = nil,
                lastSeen: Date, isStale: Bool = false) {
        self.id = id; self.source = source; self.name = name; self.project = project; self.state = state
        self.since = since; self.detail = detail; self.url = url; self.path = path; self.prompt = prompt
        self.lastSeen = lastSeen; self.isStale = isStale
    }
}
