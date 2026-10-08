import EventKit
import Foundation

public final class CalendarService: MeetingProvider {
    private let store = EKEventStore()

    public init() {
        guard EKEventStore.authorizationStatus(for: .event) == .notDetermined else { return }
        store.requestFullAccessToEvents { _, _ in }
    }

    public func nextMeeting(now: Date) -> MeetingInfo? {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return nil }
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return Self.selectNext(from: store.events(matching: predicate).map(EventData.init), now: now)
    }

    struct EventData {
        var title: String
        var startDate: Date
        var endDate: Date
        var url: URL?
        var notes: String?
        var isAllDay: Bool

        init(_ event: EKEvent) {
            title = event.title ?? "Meeting"
            startDate = event.startDate
            endDate = event.endDate
            url = event.url
            notes = event.notes
            isAllDay = event.isAllDay
        }

        init(title: String, startDate: Date, endDate: Date,
             url: URL? = nil, notes: String? = nil, isAllDay: Bool = false) {
            self.title = title; self.startDate = startDate; self.endDate = endDate
            self.url = url; self.notes = notes; self.isAllDay = isAllDay
        }
    }

    static func selectNext(from events: [EventData], now: Date) -> MeetingInfo? {
        events
            .filter { !$0.isAllDay && $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .first
            .map { e in
                let joinURL = e.url ?? extractTeamsURL(from: e.notes)
                return MeetingInfo(title: e.title, startDate: e.startDate,
                                   endDate: e.endDate, joinURL: joinURL)
            }
    }

    static func extractTeamsURL(from notes: String?) -> URL? {
        guard let notes else { return nil }
        let pattern = #"https://teams\.microsoft\.com/l/meetup-join/[^\s\"'>]+"#
        guard let range = notes.range(of: pattern, options: .regularExpression) else { return nil }
        return URL(string: String(notes[range]))
    }
}
