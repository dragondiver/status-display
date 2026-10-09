# Nächstes Meeting anzeigen

Datum: 2026-10-08

## Ziel

Das nächste heutige Meeting aus dem macOS-Kalender (Exchange-Sync) auf dem AKP02-Panel, im Board-Fenster und im Menü anzeigen — rein lesend, kein Statuswechsel, kein Schreiben in Teams.

## Abgrenzung

- **In scope:** Nächstes Event, das heute noch läuft oder beginnt. Alle Kalender (nicht nur Teams-spezifische). Join-URL wenn vorhanden.
- **Out of scope:** Automatischer Statuswechsel beim Meeting-Start. Morgenplanung / mehrtägige Ansicht. Benachrichtigungen.

## Datenmodell

```swift
// StatusCore/Calendar/MeetingInfo.swift
public struct MeetingInfo: Equatable {
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var joinURL: URL?      // Teams-Join-Link aus Event-URL oder -Notizen
}
```

`BoardState` bekommt ein neues Feld:

```swift
public var nextMeeting: MeetingInfo?
```

## CalendarService

```swift
// StatusCore/Calendar/MeetingProvider.swift  (Protokoll)
public protocol MeetingProvider {
    func nextMeeting(now: Date) -> MeetingInfo?
}

// StatusCore/Calendar/CalendarService.swift  (Implementierung)
public final class CalendarService: MeetingProvider { … }
```

**Logik in `nextMeeting(now:)`:**

1. EventKit-Zugriff prüfen; wenn verweigert oder noch nicht erteilt → `nil` (kein Absturz, kein Dialog im Hintergrund).
2. Alle Events des heutigen Tages laden (`EKEventStore.events(matching:)`).
3. Das erste Event zurückgeben, dessen `endDate > now` — also läuft noch oder beginnt noch heute.
4. Join-URL: erst `EKEvent.url`, dann regulärer Ausdruck auf `EKEvent.notes` für `https://teams.microsoft.com/l/meetup-join/…`.

**Zugriffsanfrage:** `CalendarService` ruft `EKEventStore.requestAccess(to: .event)` lazy beim ersten `nextMeeting(now:)` auf — kein extra Einstieg in `AppModel`. Solange die Antwort aussteht → `nil`. Nach Ablehnung: `nil` für die gesamte Laufzeit (keine Wiederholung).

## AppModel

Neue Felder:

```swift
private let calendarService: MeetingProvider   // CalendarService() in Produktion
@Published private(set) var nextMeeting: MeetingInfo?
```

In `refreshLocal()`:

```swift
nextMeeting = calendarService.nextMeeting(now: Date())
```

In `scheduleRender()` — `BoardState`-Konstruktion um `nextMeeting` ergänzen.

Kein separater Timer: der bestehende 15s-Takt reicht; EventKit-Zugriff auf lokale Daten ist schnell.

## Oberflächen

### Panel (BoardRenderer / 1920×462)

Zwei neue Zeilen unterhalb des Status-Balkens, nur wenn `nextMeeting != nil`:

- Zeile 1: Countdown oder Uhrzeit — `„In 23 min"` / `„Jetzt"` / `„14:30"`
- Zeile 2: Titel (gekürzt auf Zeilenbreite)

Kein Meeting → keine Zeilen, kein Leerraum.

### Board-Fenster (BoardWindowStatusZone)

Gleiche zwei Zeilen, eingepasst zwischen Status-Zone und PR-Bereich. Schrift und Abstand konsistent mit bestehenden Zonen.

### Menü (StatusMenuItems)

Ein Menüpunkt direkt unterhalb des Status-Eintrags:

- `„14:30 · Stand-up"` — klickbar wenn `joinURL != nil` (öffnet Teams), sonst deaktiviert.
- Kein Meeting → Punkt fehlt.

## Berechtigungen

`Info.plist` bekommt `NSCalendarsUsageDescription` mit einem deutschen Erklärungstext. Die Zugriffsanfrage erscheint beim ersten Start nach dem Update; Ablehnung ist silent-tolerant.

## Tests

`MeetingProvider`-Protokoll erlaubt Stubs ohne echten Kalender:

- `CalendarServiceTests`: Stub mit vorbereiteten Events — prüft die Auswahllogik (laufendes Event, beginnendes Event, abgelaufenes Event, kein Event heute, Event nach Mitternacht).
- Join-URL-Extraktion aus `notes`: eigene Funktion, isoliert testbar.
- `AppModel`-Tests: bestehende Struktur, `MeetingProvider`-Stub injiziert.

## Offene Fragen

Keine.
