import XCTest
@testable import StatusCore

final class CalendarServiceTests: XCTestCase {
    private typealias ED = CalendarService.EventData
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    // MARK: selectNext

    func testSelectNextReturnsNilWhenEmpty() {
        XCTAssertNil(CalendarService.selectNext(from: [], now: t0))
    }

    func testSelectNextIgnoresAllDayEvents() {
        let allDay = ED(title: "Urlaub", startDate: t0, endDate: t0.addingTimeInterval(3600), isAllDay: true)
        XCTAssertNil(CalendarService.selectNext(from: [allDay], now: t0))
    }

    func testSelectNextIgnoresEndedEvents() {
        // endDate == now → schon vorbei (endDate > now schlägt fehl)
        let ended = ED(title: "Stand-up", startDate: t0.addingTimeInterval(-3600), endDate: t0)
        XCTAssertNil(CalendarService.selectNext(from: [ended], now: t0))
    }

    func testSelectNextPicksEarliestUpcoming() {
        let later  = ED(title: "Retro",    startDate: t0.addingTimeInterval(7200),  endDate: t0.addingTimeInterval(9000))
        let sooner = ED(title: "Stand-up", startDate: t0.addingTimeInterval(1800),  endDate: t0.addingTimeInterval(5400))
        let result = CalendarService.selectNext(from: [later, sooner], now: t0)
        XCTAssertEqual(result?.title, "Stand-up")
    }

    func testSelectNextIncludesRunningMeeting() {
        let running = ED(title: "1:1", startDate: t0.addingTimeInterval(-600), endDate: t0.addingTimeInterval(1800))
        let result = CalendarService.selectNext(from: [running], now: t0)
        XCTAssertEqual(result?.title, "1:1")
    }

    func testSelectNextPreferEventUrlOverNotes() {
        let url = URL(string: "https://example.com/meeting")!
        let e = ED(title: "x", startDate: t0.addingTimeInterval(60), endDate: t0.addingTimeInterval(3660),
                   url: url, notes: "https://teams.microsoft.com/l/meetup-join/abc123")
        XCTAssertEqual(CalendarService.selectNext(from: [e], now: t0)?.joinURL, url)
    }

    // MARK: extractTeamsURL

    func testExtractTeamsURLNil() {
        XCTAssertNil(CalendarService.extractTeamsURL(from: nil))
        XCTAssertNil(CalendarService.extractTeamsURL(from: "kein Link hier"))
    }

    func testExtractTeamsURLFound() {
        let notes = "Besprechung\nhttps://teams.microsoft.com/l/meetup-join/abc%2F123?context=foo\nEnde"
        let url = CalendarService.extractTeamsURL(from: notes)
        XCTAssertEqual(url?.absoluteString,
                       "https://teams.microsoft.com/l/meetup-join/abc%2F123?context=foo")
    }

    func testSelectNextJoinURLFromNotes() {
        let notes = "Join: https://teams.microsoft.com/l/meetup-join/xyz"
        let e = ED(title: "x", startDate: t0.addingTimeInterval(60), endDate: t0.addingTimeInterval(3660), notes: notes)
        XCTAssertNotNil(CalendarService.selectNext(from: [e], now: t0)?.joinURL)
    }
}
