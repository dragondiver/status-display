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
    public var lastSeen: Date
    /// Nur für `.running`: seit `AgentRegistry.staleAfter` keine Meldung.
    public var isStale: Bool = false

    public init(id: String, source: String, name: String, project: String? = nil, state: AgentState,
                since: Date, detail: String? = nil, url: URL? = nil, lastSeen: Date, isStale: Bool = false) {
        self.id = id; self.source = source; self.name = name; self.project = project; self.state = state
        self.since = since; self.detail = detail; self.url = url; self.lastSeen = lastSeen; self.isStale = isStale
    }
}
