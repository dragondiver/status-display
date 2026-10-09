import Foundation

public struct MeetingInfo: Equatable {
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var joinURL: URL?

    public init(title: String, startDate: Date, endDate: Date, joinURL: URL? = nil) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.joinURL = joinURL
    }
}

public protocol MeetingProvider {
    func nextMeeting(now: Date) -> MeetingInfo?
}
