# Nächstes Meeting anzeigen — Implementierungsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Das nächste heutige Meeting aus dem macOS-Kalender (Exchange) auf dem AKP02-Panel, im Board-Fenster und im Menü anzeigen.

**Architecture:** Ein neues `CalendarService`-Objekt in StatusCore liest EventKit, gibt `MeetingInfo?` zurück. `AppModel.refreshLocal()` ruft es im bestehenden 15s-Takt auf. `BoardState` trägt das Ergebnis zu allen drei Renderern.

**Tech Stack:** Swift, EventKit (macOS 14), CoreGraphics, AppKit/SwiftUI

**Spec:** `docs/superpowers/specs/2026-10-08-naechstes-meeting-anzeigen.md`

## Global Constraints

- macOS 14+ (`platforms: [.macOS(.v14)]` in Package.swift)
- Swift Language Mode 5 (Package.swift: `swiftLanguageModes: [.v5]`)
- Kein extra Timer — bestehender 15s-Takt in `AppModel.refreshLocal()`
- Neue Typen in `StatusCore`, UI-Anpassungen in `StatusDisplay`
- `swift test` muss nach jedem Commit grün bleiben
- Commit-Messages auf Deutsch, Closing-Keywords englisch

## Review Focus

- **EventKit-Zugriff verweigert:** `CalendarService.nextMeeting` muss `nil` zurückgeben, kein Absturz.
- **Meeting endet genau `now`:** `endDate > now` (nicht `>=`) — ein gerade endendes Meeting darf nicht mehr erscheinen.
- **Alle Events heute: alle `isAllDay`:** Kein Event darf erscheinen.
- **`startDate` > 60 Minuten in der Zukunft:** `meetingCountdown` gibt Uhrzeit statt Countdown zurück. — Test in Task 3.
- **Kein Meeting heute:** `BoardState.nextMeeting == nil` → keine Zeilen auf dem Panel, kein Menüpunkt.

---

## Dateiübersicht

| Datei | Aktion |
|---|---|
| `Sources/StatusCore/Calendar/MeetingInfo.swift` | Neu: `MeetingInfo`, `MeetingProvider` |
| `Sources/StatusCore/Calendar/CalendarService.swift` | Neu: EventKit-Implementierung |
| `Sources/StatusCore/Render/BoardState.swift` | Ändern: `nextMeeting: MeetingInfo?` |
| `Sources/StatusCore/Render/BoardText.swift` | Ändern: `meetingCountdown(_:now:timeZone:)` |
| `Sources/StatusCore/Render/BoardRenderer.swift` | Ändern: Meeting-Zeilen in `drawStatus` |
| `Sources/StatusCore/Render/BoardWindowLayout.swift` | Ändern: Meeting-Baselines in Statuszone |
| `Sources/StatusCore/Render/BoardWindowRenderer.swift` | Ändern: Meeting in `drawStatus` zeichnen |
| `Sources/StatusDisplay/AppModel.swift` | Ändern: `calendarService`, `nextMeeting` |
| `Sources/StatusDisplay/MenuContent.swift` | Ändern: Meeting-Menüpunkt |
| `Resources/Info.plist` | Ändern: `NSCalendarsUsageDescription` |
| `Tests/StatusCoreTests/CalendarServiceTests.swift` | Neu |
| `Tests/StatusCoreTests/BoardTextTests.swift` | Ändern: neue Tests |
| `Tests/StatusCoreTests/BoardRendererTests.swift` | Ändern: neue Tests |
| `Tests/StatusCoreTests/BoardWindowLayoutTests.swift` | Ändern: neue Tests |

---

## Task 1: MeetingInfo, MeetingProvider, BoardState

**Files:**
- Create: `Sources/StatusCore/Calendar/MeetingInfo.swift`
- Modify: `Sources/StatusCore/Render/BoardState.swift`
- Modify: `Tests/StatusCoreTests/BoardRendererTests.swift` (BoardState-Konstruktoraufrufe ergänzen)

**Interfaces:**
- Produces:
  - `public struct MeetingInfo: Equatable` mit `title: String`, `startDate: Date`, `endDate: Date`, `joinURL: URL?`
  - `public protocol MeetingProvider { func nextMeeting(now: Date) -> MeetingInfo? }`
  - `BoardState.nextMeeting: MeetingInfo?` (neues optionales Feld, Default `nil`)

- [ ] **MeetingInfo.swift anlegen**

```swift
// Sources/StatusCore/Calendar/MeetingInfo.swift
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
```

- [ ] **BoardState um `nextMeeting` ergänzen**

In `Sources/StatusCore/Render/BoardState.swift` — `BoardState` bekommt:

```swift
public var nextMeeting: MeetingInfo?
```

`init` erhält einen neuen Parameter mit Default-Wert am Ende:

```swift
public init(statusName: String, statusColor: RGBColor, statusSince: Date,
            agents: [AgentActivity], prs: PRZone, now: Date,
            nextMeeting: MeetingInfo? = nil) {
    self.statusName = statusName; self.statusColor = statusColor; self.statusSince = statusSince
    self.agents = agents; self.prs = prs; self.now = now; self.nextMeeting = nextMeeting
}
```

- [ ] **Compiler-Check: `swift build` grün**

```bash
swift build 2>&1 | tail -5
```

Bestehende Tests müssen noch nicht laufen; der Compiler darf keine Fehler zeigen.

- [ ] **Commit**

```bash
git add Sources/StatusCore/Calendar/MeetingInfo.swift Sources/StatusCore/Render/BoardState.swift
git commit -m "$(cat <<'EOF'
Datenmodell: MeetingInfo, MeetingProvider, BoardState.nextMeeting

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: CalendarService + Info.plist

**Files:**
- Create: `Sources/StatusCore/Calendar/CalendarService.swift`
- Create: `Tests/StatusCoreTests/CalendarServiceTests.swift`
- Modify: `Resources/Info.plist`

**Interfaces:**
- Consumes: `MeetingInfo`, `MeetingProvider` aus Task 1
- Produces:
  - `public final class CalendarService: MeetingProvider`
  - `static func selectNext(from: [EventData], now: Date) -> MeetingInfo?` (intern, für Tests)
  - `static func extractTeamsURL(from: String?) -> URL?` (intern, für Tests)

- [ ] **CalendarService.swift anlegen**

```swift
// Sources/StatusCore/Calendar/CalendarService.swift
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

    // Interne Typen für testbare Hilfs-Funktionen

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
```

- [ ] **CalendarServiceTests.swift anlegen**

```swift
// Tests/StatusCoreTests/CalendarServiceTests.swift
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
        // endDate == now → schon vorbei (> now schlägt fehl)
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
        // Bereits gestartet, aber noch nicht beendet
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
```

- [ ] **Tests ausführen**

```bash
swift test --filter CalendarServiceTests 2>&1 | tail -10
```

Erwartet: alle Tests grün.

- [ ] **NSCalendarsUsageDescription in Info.plist eintragen**

In `Resources/Info.plist` nach `<key>LSUIElement</key><true/>` einfügen:

```xml
    <key>NSCalendarsUsageDescription</key>
    <string>StatusDisplay liest den heutigen Kalender, um das nächste Meeting anzuzeigen.</string>
```

- [ ] **Commit**

```bash
git add Sources/StatusCore/Calendar/CalendarService.swift \
        Tests/StatusCoreTests/CalendarServiceTests.swift \
        Resources/Info.plist
git commit -m "$(cat <<'EOF'
CalendarService: nächstes Event aus EventKit, testbare Hilfs-Funktionen

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: BoardText.meetingCountdown

**Files:**
- Modify: `Sources/StatusCore/Render/BoardText.swift`
- Modify: `Tests/StatusCoreTests/BoardTextTests.swift`

**Interfaces:**
- Consumes: `MeetingInfo` aus Task 1
- Produces: `public static func meetingCountdown(_ meeting: MeetingInfo, now: Date, timeZone: TimeZone = .current) -> String`

**Logik:**
- `startDate <= now` → `"Jetzt"`
- `startDate > now` und ≤ 60 Minuten → `"In N min"` (`N = ceil(Sekunden / 60)`)
- `startDate > now + 60 min` → `clock(startDate, timeZone:)` z. B. `"14:30"`

- [ ] **Fehlschlagende Tests schreiben**

An `BoardTextTests.swift` anhängen:

```swift
// MARK: meetingCountdown

func testMeetingCountdownJetzt() {
    let m = MeetingInfo(title: "x", startDate: t0.addingTimeInterval(-300), endDate: t0.addingTimeInterval(3000))
    XCTAssertEqual(BoardText.meetingCountdown(m, now: t0), "Jetzt")
}

func testMeetingCountdownExactlyNow() {
    let m = MeetingInfo(title: "x", startDate: t0, endDate: t0.addingTimeInterval(3600))
    XCTAssertEqual(BoardText.meetingCountdown(m, now: t0), "Jetzt")
}

func testMeetingCountdownMinutes() {
    let m = MeetingInfo(title: "x", startDate: t0.addingTimeInterval(23 * 60 + 5),
                        endDate: t0.addingTimeInterval(83 * 60))
    // ceil(23*60+5 / 60) = ceil(23.08) = 24
    XCTAssertEqual(BoardText.meetingCountdown(m, now: t0), "In 24 min")
}

func testMeetingCountdownOneMinute() {
    let m = MeetingInfo(title: "x", startDate: t0.addingTimeInterval(30),
                        endDate: t0.addingTimeInterval(3630))
    XCTAssertEqual(BoardText.meetingCountdown(m, now: t0), "In 1 min")
}

func testMeetingCountdownSixtyMinutes() {
    let m = MeetingInfo(title: "x", startDate: t0.addingTimeInterval(60 * 60),
                        endDate: t0.addingTimeInterval(120 * 60))
    XCTAssertEqual(BoardText.meetingCountdown(m, now: t0), "In 60 min")
}

func testMeetingCountdownShowsClockWhenMoreThan60Min() {
    // t0 = 1790000000 s (UTC). startDate 90 min later.
    // In UTC: 1790000000 + 5400 s → format "HH:mm" in UTC.
    let start = t0.addingTimeInterval(90 * 60)
    let m = MeetingInfo(title: "x", startDate: start, endDate: start.addingTimeInterval(3600))
    let result = BoardText.meetingCountdown(m, now: t0, timeZone: TimeZone(identifier: "UTC")!)
    XCTAssertEqual(result, BoardText.clock(start, timeZone: TimeZone(identifier: "UTC")!))
    XCTAssertFalse(result.hasPrefix("In"))
    XCTAssertNotEqual(result, "Jetzt")
}
```

- [ ] **Tests ausführen — sollen rot sein**

```bash
swift test --filter BoardTextTests 2>&1 | grep -E "(FAIL|error:)" | head -5
```

Erwartet: Compiler-Fehler (`meetingCountdown` existiert noch nicht).

- [ ] **meetingCountdown implementieren**

In `Sources/StatusCore/Render/BoardText.swift` ergänzen:

```swift
public static func meetingCountdown(_ meeting: MeetingInfo, now: Date,
                                    timeZone: TimeZone = .current) -> String {
    let secs = meeting.startDate.timeIntervalSince(now)
    if secs <= 0 { return "Jetzt" }
    let minutes = Int(ceil(secs / 60))
    if minutes <= 60 { return "In \(minutes) min" }
    return clock(meeting.startDate, timeZone: timeZone)
}
```

- [ ] **Tests ausführen — sollen grün sein**

```bash
swift test --filter BoardTextTests 2>&1 | tail -5
```

- [ ] **Commit**

```bash
git add Sources/StatusCore/Render/BoardText.swift Tests/StatusCoreTests/BoardTextTests.swift
git commit -m "$(cat <<'EOF'
BoardText: meetingCountdown für Panel- und Fensterdarstellung

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Panel-Darstellung (BoardRenderer)

**Files:**
- Modify: `Sources/StatusCore/Render/BoardRenderer.swift`
- Modify: `Tests/StatusCoreTests/BoardRendererTests.swift`

**Interfaces:**
- Consumes: `BoardState.nextMeeting`, `BoardText.meetingCountdown`, `BoardText.truncate`

**Layout auf dem 1920×462-Panel (x=0..480, Statuszone):**
- Zeile 1 (Countdown): baseline 280, size 34, Farbe `muted`
- Zeile 2 (Titel): baseline 322, size 34, Farbe `white` mit 0.85-Alpha
- Kein Meeting: keine Zeilen, kein Leerraum

- [ ] **Fehlschlagende Tests schreiben**

An `BoardRendererTests.swift` anhängen (die Hilfsfunktionen `pixel` und `isWhitish` existieren bereits in der Datei):

```swift
// MARK: Meeting-Zeilen

private func meetingState(startOffset: TimeInterval = 23 * 60) -> BoardState {
    let meeting = MeetingInfo(title: "Stand-up",
                              startDate: t0.addingTimeInterval(startOffset),
                              endDate:   t0.addingTimeInterval(startOffset + 3600))
    return BoardState(statusName: "Deep Focus", statusColor: RGBColor(hex: "#FF0000")!,
                      statusSince: t0, agents: [], prs: .unknown,
                      now: t0, nextMeeting: meeting)
}

func testMeetingZeilenSindSichtbarInStatuszone() {
    let img = BoardRenderer.render(meetingState())
    // Countdown-Zeile (baseline 280, size 34): weiß-graue Pixel bei y ~255..285, x ~40..200
    var sawPixels = false
    for y in 255...285 {
        for x in stride(from: 40, to: 200, by: 3) {
            if isWhitish(pixel(img, x, y)) { sawPixels = true }
        }
    }
    XCTAssertTrue(sawPixels, "Countdown-Zeile zeichnet Pixel in der Statuszone")
}

func testKeinMeetingKeineMeetingZeilen() {
    let state = BoardState(statusName: "Deep Focus", statusColor: RGBColor(hex: "#FF0000")!,
                           statusSince: t0, agents: [], prs: .unknown, now: t0,
                           nextMeeting: nil)
    // Im Meeting-Bereich (y 255..340) darf nur der farbige Hintergrund ohne Text-Pixel sein.
    // Da die Statuszone in Rot (#FF0000) ist, prüfen wir: keine hellen (whitish) Pixel dort.
    let img = BoardRenderer.render(state)
    var sawText = false
    for y in 260...340 {
        for x in stride(from: 40, to: 200, by: 3) {
            if isWhitish(pixel(img, x, y)) { sawText = true }
        }
    }
    XCTAssertFalse(sawText, "Ohne Meeting keine Text-Pixel im Meeting-Bereich")
}
```

- [ ] **Tests ausführen — sollen rot sein**

```bash
swift test --filter BoardRendererTests/testMeetingZeilen 2>&1 | grep -E "FAIL|PASS"
```

- [ ] **Meeting-Zeilen in drawStatus einbauen**

In `BoardRenderer.drawStatus`, nach der `for w in words`-Schleife und vor `text(ctx, BoardText.clock…)`:

```swift
if let m = s.nextMeeting {
    let countdown = BoardText.meetingCountdown(m, now: s.now)
    text(ctx, countdown,
         x: 40, baseline: 280, size: 34, color: muted)
    text(ctx, BoardText.truncate(m.title, max: 18),
         x: 40, baseline: 322, size: 34, color: white.withAlpha(0.85))
}
```

- [ ] **Tests ausführen — sollen grün sein**

```bash
swift test --filter BoardRendererTests 2>&1 | tail -5
```

- [ ] **Commit**

```bash
git add Sources/StatusCore/Render/BoardRenderer.swift Tests/StatusCoreTests/BoardRendererTests.swift
git commit -m "$(cat <<'EOF'
BoardRenderer: nächstes Meeting in der Statuszone des Panels

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Board-Fenster (BoardWindowLayout + BoardWindowRenderer)

**Files:**
- Modify: `Sources/StatusCore/Render/BoardWindowLayout.swift`
- Modify: `Sources/StatusCore/Render/BoardWindowRenderer.swift`
- Modify: `Tests/StatusCoreTests/BoardWindowLayoutTests.swift`

**Interfaces:**
- Consumes: `BoardState.nextMeeting`, `BoardText.meetingCountdown`, `BoardText.truncate`
- Produces: `BoardWindowLayout.meetingCountdownBaseline: CGFloat?`, `BoardWindowLayout.meetingTitleBaseline: CGFloat?`

**Layout-Logik:**
- `meetingTitleBaseline = clockBaseline - FontSize.since - 8 - FontSize.row`
- `meetingCountdownBaseline = meetingTitleBaseline - FontSize.row - 3`
- Nur nicht-nil wenn: `state.nextMeeting != nil` **und** `meetingCountdownBaseline > (statusBaselines.last ?? 0) + 8` (Platz-Check)

- [ ] **Fehlschlagende Tests schreiben**

An `BoardWindowLayoutTests.swift` anhängen — zuerst die existierenden Hilfsfunktionen der Datei ansehen (`head -30 Tests/StatusCoreTests/BoardWindowLayoutTests.swift`) und denselben State-Helfer nutzen:

```swift
// MARK: Meeting-Baselines

private func meetingState(size: CGSize) -> BoardWindowLayout {
    let m = MeetingInfo(title: "Stand-up",
                        startDate: Date().addingTimeInterval(23 * 60),
                        endDate:   Date().addingTimeInterval(83 * 60))
    let s = BoardState(statusName: "Deep Focus",
                       statusColor: RGBColor(hex: "#FF0000")!,
                       statusSince: Date(), agents: [], prs: .unknown,
                       now: Date(), nextMeeting: m)
    return BoardWindowLayout(state: s, size: size)
}

private func noMeetingLayout(size: CGSize) -> BoardWindowLayout {
    let s = BoardState(statusName: "Deep Focus",
                       statusColor: RGBColor(hex: "#FF0000")!,
                       statusSince: Date(), agents: [], prs: .unknown,
                       now: Date(), nextMeeting: nil)
    return BoardWindowLayout(state: s, size: size)
}

func testMeetingBaselinesNichtNilBeiAusreichendHohemFenster() {
    let l = meetingState(size: CGSize(width: 600, height: 110))
    XCTAssertNotNil(l.meetingCountdownBaseline)
    XCTAssertNotNil(l.meetingTitleBaseline)
}

func testMeetingBaselinesNilOhneMeeting() {
    let l = noMeetingLayout(size: CGSize(width: 600, height: 110))
    XCTAssertNil(l.meetingCountdownBaseline)
    XCTAssertNil(l.meetingTitleBaseline)
}

func testMeetingBaselinesNilBeiZuKleinerHoehe() {
    // Bei minimaler Höhe ist kein Platz für Meeting-Zeilen.
    let l = meetingState(size: CGSize(width: 600, height: 40))
    XCTAssertNil(l.meetingCountdownBaseline)
}

func testMeetingCountdownBaselineUnterStatusWorten() {
    let l = meetingState(size: CGSize(width: 600, height: 110))
    if let countdown = l.meetingCountdownBaseline, let lastWord = l.statusBaselines.last {
        XCTAssertGreaterThan(countdown, lastWord + 7)
    }
}

func testMeetingTitleBaselineOberhalsClock() {
    let l = meetingState(size: CGSize(width: 600, height: 110))
    if let title = l.meetingTitleBaseline {
        XCTAssertLessThan(title, l.clockBaseline)
    }
}
```

- [ ] **Tests ausführen — sollen rot sein**

```bash
swift test --filter BoardWindowLayoutTests 2>&1 | grep -E "FAIL|error:" | head -5
```

- [ ] **BoardWindowLayout: neue Felder und Berechnung**

In `Sources/StatusCore/Render/BoardWindowLayout.swift`:

*Neue Felder nach `sinceBaseline`:*
```swift
public let meetingCountdownBaseline: CGFloat?
public let meetingTitleBaseline: CGFloat?
```

*In `init`, nach der Berechnung von `sinceBaseline`/`clockBaseline`:*
```swift
if state.nextMeeting != nil {
    let titleBase = clockBaseline - FontSize.since - 8 - FontSize.row
    let countdownBase = titleBase - FontSize.row - 3
    let minBase = (statusBaselines.last ?? 0) + 8
    if countdownBase > minBase {
        meetingTitleBaseline = titleBase
        meetingCountdownBaseline = countdownBase
    } else {
        meetingTitleBaseline = nil
        meetingCountdownBaseline = nil
    }
} else {
    meetingTitleBaseline = nil
    meetingCountdownBaseline = nil
}
```

- [ ] **BoardWindowRenderer: Meeting zeichnen**

In `Sources/StatusCore/Render/BoardWindowRenderer.swift`, in `drawStatus`, nach dem `text(ctx, BoardText.since…)`-Aufruf:

```swift
if let m = s.nextMeeting,
   let countdownBaseline = l.meetingCountdownBaseline,
   let titleBaseline = l.meetingTitleBaseline {
    let maxWidth = l.statusRect.width - 2 * L.padding
    text(ctx, BoardText.meetingCountdown(m, now: s.now),
         x: x, baseline: countdownBaseline, size: F.row, color: R.muted, maxWidth: maxWidth)
    text(ctx, BoardText.truncate(m.title, max: 22),
         x: x, baseline: titleBaseline, size: F.row, color: R.white.withAlpha(0.85), maxWidth: maxWidth)
}
```

- [ ] **Tests ausführen — sollen grün sein**

```bash
swift test --filter BoardWindowLayoutTests 2>&1 | tail -5
```

- [ ] **Vollständige Test-Suite grün**

```bash
swift test 2>&1 | tail -5
```

- [ ] **Commit**

```bash
git add Sources/StatusCore/Render/BoardWindowLayout.swift \
        Sources/StatusCore/Render/BoardWindowRenderer.swift \
        Tests/StatusCoreTests/BoardWindowLayoutTests.swift
git commit -m "$(cat <<'EOF'
BoardWindowLayout/Renderer: nächstes Meeting in der Statuszone

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: AppModel + MenuContent

**Files:**
- Modify: `Sources/StatusDisplay/AppModel.swift`
- Modify: `Sources/StatusDisplay/MenuContent.swift`

**Interfaces:**
- Consumes: `CalendarService`, `MeetingProvider`, `MeetingInfo`, `BoardText.meetingCountdown` aus vorigen Tasks

Kein automatisierter Test (AppModel ist in der Codebase nicht Unit-getestet); Verifikation durch Bauen + manuelle Prüfung.

- [ ] **AppModel: calendarService + nextMeeting**

*Neue Felder in `AppModel` (nach `private let knownPresets`):*
```swift
private let calendarService: MeetingProvider
@Published private(set) var nextMeeting: MeetingInfo?
```

*`init` erhält einen neuen Parameter mit Default-Wert als erstes (vor `let settings`):*
```swift
init(calendarService: MeetingProvider = CalendarService()) {
    self.calendarService = calendarService
    let settings = AppSettings.load()
    // … Rest unverändert …
```

*In `refreshLocal()`, vor `scheduleRender()`:*
```swift
nextMeeting = calendarService.nextMeeting(now: Date())
```

*In `scheduleRender()`, im `BoardState`-Konstruktor, `nextMeeting` ergänzen:*
```swift
let state = BoardState(statusName: status.preset.name, statusColor: status.preset.color,
                       statusSince: status.since, agents: agents,
                       prs: prs.zone(now: now, hosts: settings.hosts,
                                    pinned: settings.pinnedRepos, hidden: settings.hiddenRepos,
                                    shown: settings.shownRepos, hostDefaults: settings.hostDefaults),
                       now: now,
                       nextMeeting: nextMeeting)
```

- [ ] **MenuContent: Meeting-Menüpunkt**

In `Sources/StatusDisplay/MenuContent.swift`, in `body`, direkt nach dem ersten `Text(…)` (Status-Zeile), vor `StatusMenuItems`:

```swift
if let m = model.nextMeeting {
    let label = "\(BoardText.meetingCountdown(m, now: Date())) · \(m.title)"
    if let url = m.joinURL {
        Button(label) { NSWorkspace.shared.open(url) }
    } else {
        Text(label).foregroundStyle(.secondary)
    }
}
```

- [ ] **App bauen**

```bash
swift build 2>&1 | tail -5
```

Erwartet: keine Fehler.

- [ ] **Vollständige Test-Suite grün**

```bash
swift test 2>&1 | tail -5
```

- [ ] **App starten und Meeting-Anzeige prüfen**

```bash
scripts/build.sh && open build/StatusDisplay.app
```

Prüfliste:
- Menü öffnen: Meeting erscheint (oder fehlt wenn kein heutiges Event)
- Board-Fenster öffnen (Menü → „Board-Fenster anzeigen"): Meeting sichtbar in Statuszone
- Panel (falls AKP02 verbunden): Meeting-Zeilen in der farbigen Statuszone

- [ ] **Commit**

```bash
git add Sources/StatusDisplay/AppModel.swift Sources/StatusDisplay/MenuContent.swift
git commit -m "$(cat <<'EOF'
AppModel + Menü: nächstes Meeting aus CalendarService verdrahtet

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```
