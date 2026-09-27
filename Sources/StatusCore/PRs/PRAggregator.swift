import Foundation

/// Führt die Hosts zusammen und entscheidet, wann die PR-Zone veraltet ist.
public struct PRAggregator {
    public static let refreshInterval: TimeInterval = 120

    public private(set) var snapshots: [String: PRSnapshot] = [:]
    public private(set) var errors: [String: GitHubError] = [:]

    public init() {}

    public mutating func record(_ snapshot: PRSnapshot) {
        snapshots[snapshot.host] = snapshot
        errors[snapshot.host] = nil
    }

    public mutating func record(_ error: GitHubError, host: String) { errors[host] = error }

    public mutating func retain(hosts: [String]) {
        let keep = Set(hosts)
        snapshots = snapshots.filter { keep.contains($0.key) }
        errors = errors.filter { keep.contains($0.key) }
    }

    /// `hosts` sind die konfigurierten Hosts: Fehlt für einen davon noch jeder Erfolg,
    /// ist die Zone veraltet (grau), statt ihn stillschweigend wegzulassen.
    public func zone(now: Date, hosts: [String]) -> PRZone {
        let all = Array(snapshots.values)
        guard let oldest = all.map(\.fetchedAt).min() else { return .unknown }
        let missingHost = hosts.contains { snapshots[$0] == nil }
        return PRZone(toReview: all.map(\.toReview.count).reduce(0, +),
                      mine: all.map(\.mine.count).reduce(0, +),
                      ciFailing: all.map(\.ciFailingCount).reduce(0, +),
                      lastSuccess: oldest,
                      isStale: missingHost || now.timeIntervalSince(oldest) > 3 * Self.refreshInterval)
    }
}
