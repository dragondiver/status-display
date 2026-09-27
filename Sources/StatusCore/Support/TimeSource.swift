import Foundation

/// Uhr-Abstraktion, damit Zeitregeln ohne Warten testbar sind.
public protocol TimeSource: AnyObject {
    var now: Date { get }
}

public final class SystemTime: TimeSource {
    public init() {}
    public var now: Date { Date() }
}

public final class ManualTime: TimeSource {
    public var now: Date
    public init(_ start: Date = Date(timeIntervalSince1970: 1_790_000_000)) { now = start }
    public func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}
