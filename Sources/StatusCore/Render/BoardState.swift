import Foundation

public struct PRZone: Equatable {
    public var toReview: Int
    public var mine: Int
    public var ciFailing: Int
    /// Ältester erfolgreicher Abruf über alle Hosts; nil = noch nie.
    public var lastSuccess: Date?
    public var isStale: Bool

    public init(toReview: Int, mine: Int, ciFailing: Int, lastSuccess: Date?, isStale: Bool) {
        self.toReview = toReview; self.mine = mine; self.ciFailing = ciFailing
        self.lastSuccess = lastSuccess; self.isStale = isStale
    }

    public static let unknown = PRZone(toReview: 0, mine: 0, ciFailing: 0, lastSuccess: nil, isStale: true)
}

public struct BoardState: Equatable {
    public var statusName: String
    public var statusColor: RGBColor
    public var statusSince: Date
    public var agents: [AgentActivity]
    public var prs: PRZone
    public var now: Date

    public init(statusName: String, statusColor: RGBColor, statusSince: Date,
                agents: [AgentActivity], prs: PRZone, now: Date) {
        self.statusName = statusName; self.statusColor = statusColor; self.statusSince = statusSince
        self.agents = agents; self.prs = prs; self.now = now
    }
}
