import Foundation

/// Hält den Zustand aller Agenten. Die Zeitregeln stehen hier, nicht beim Agenten.
/// Nur vom Main-Thread benutzen.
public final class AgentRegistry {
    public static let doneTTL: TimeInterval = 600
    public static let staleAfter: TimeInterval = 1800
    public static let removeAfter: TimeInterval = 14_400

    private let time: TimeSource
    private var items: [String: AgentActivity] = [:]

    public init(time: TimeSource) { self.time = time }

    public func apply(_ event: AgentEvent) throws {
        try event.validate()
        let id = "\(event.source):\(event.session)"
        guard let state = AgentState(rawValue: event.state) else {
            items[id] = nil // "ended"
            return
        }
        let now = time.now
        var item = items[id] ?? AgentActivity(id: id, source: event.source, name: event.source,
                                              state: state, since: now, lastSeen: now)
        if item.state != state { item.since = now }
        item.state = state
        item.lastSeen = now
        item.project = event.project ?? item.project
        item.name = event.name ?? event.project ?? item.project ?? item.name
        item.detail = event.detail
        if let u = event.url { item.url = URL(string: u) }
        items[id] = item
    }

    public func dismiss(id: String) { items[id] = nil }

    public func snapshot() -> [AgentActivity] {
        let now = time.now
        items = items.filter { _, a in
            switch a.state {
            case .done: return now.timeIntervalSince(a.since) <= Self.doneTTL
            case .running: return now.timeIntervalSince(a.lastSeen) <= Self.removeAfter
            case .waiting, .error: return true
            }
        }
        return items.values
            .map { a -> AgentActivity in
                var a = a
                a.isStale = a.state == .running && now.timeIntervalSince(a.lastSeen) > Self.staleAfter
                return a
            }
            .sorted { l, r in
                let (lr, rr) = (rank(l), rank(r))
                return lr != rr ? lr < rr : l.since < r.since
            }
    }

    private func rank(_ a: AgentActivity) -> Int {
        switch a.state {
        case .waiting: return 0
        case .error: return 1
        case .running: return a.isStale ? 3 : 2
        case .done: return 4
        }
    }
}
