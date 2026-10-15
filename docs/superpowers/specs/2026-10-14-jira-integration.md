# Jira-Integration

Datum: 2026-10-14

## Ziel

Jira Cloud (atlassian.net) in status-display einbinden: zugewiesene, offene Issues im Dashboard-Fenster anzeigen (gruppiert nach Projekt und Sprint), Gesamt-Zähler auf Panel und Board-Fenster.

## Abgrenzung

- **In scope:** Jira Cloud REST API v3, Basic Auth (email + API-Token), alle eigenen offenen Issues (`assignee = currentUser() AND statusCategory != Done`), Dashboard-Ansicht, Panel-Zähler, Board-Fenster-Zähler.
- **Out of scope:** Jira Server/Data Center, OAuth, Issues schreiben/kommentieren, andere JQL-Filter als der feste eigene, Benachrichtigungen, Jira auf dem AKP02 als eigene Zone.

## Authentifizierung

Basic Auth: `Authorization: Basic base64(email:token)`. API-Token wird unter `id.atlassian.com/manage-profile/security/api-tokens` erzeugt. Token liegt in `UserDefaults` (wie alle anderen Einstellungen); kein Keychain für dieses Privatprojekt.

## Datenmodell

```swift
// StatusCore/Jira/JiraIssue.swift
public struct JiraIssue: Equatable, Identifiable {
    public var id: String           // Jira-interne ID
    public var key: String          // "PROJ-42"
    public var summary: String
    public var statusName: String   // "In Progress", "To Do", …
    public var priorityName: String?
    public var projectKey: String
    public var projectName: String
    public var sprintName: String?  // nil wenn kein aktiver Sprint
    public var url: URL
}

// StatusCore/Jira/JiraSnapshot.swift
public struct JiraSnapshot: Equatable {
    public var issues: [JiraIssue]
    public var fetchedAt: Date
    public var error: String?       // Fehlermeldung bei HTTP/Parse-Fehler, sonst nil
    public static let empty = JiraSnapshot(issues: [], fetchedAt: .distantPast, error: nil)
}

// StatusCore/Jira/JiraAggregator.swift
public struct JiraAggregator: Equatable {
    public var snapshot: JiraSnapshot
    /// Alle offenen Tickets, nach Projekt und Sprint gruppiert.
    /// Schlüssel: projectKey, Wert: [(sprintName?, [JiraIssue])] – sortiert, kein Sprint zuletzt.
    public func grouped() -> [(project: String, projectName: String, sprints: [(sprint: String?, issues: [JiraIssue])])]
    /// Gesamt-Zähler für Panel/Board-Fenster.
    public var openCount: Int { snapshot.issues.count }
    /// true wenn `snapshot.fetchedAt` älter als 10 Minuten oder `snapshot == .empty`.
    public var isStale: Bool
    public static let unknown = JiraAggregator(snapshot: .empty)
}
```

## JiraService

```swift
// StatusCore/Jira/JiraFetcher.swift  (Protokoll)
public protocol JiraFetcher {
    func fetch(domain: String, email: String, token: String) async throws -> JiraSnapshot
}

// StatusCore/Jira/JiraService.swift  (Implementierung)
public final class JiraService: JiraFetcher { … }
```

**Endpunkt:**
```
GET https://<domain>/rest/api/3/search
  ?jql=assignee=currentUser() AND statusCategory!=Done
  &fields=summary,status,priority,project,issuetype,customfield_10020
  &maxResults=100
  &orderBy=updated DESC
```

`customfield_10020` ist das Standard-Sprint-Feld in Jira Cloud. Wenn das Feld fehlt oder leer ist → `sprintName = nil`.

**Fehlerbehandlung:** HTTP 4xx/5xx → `JiraSnapshot.error` setzen, `issues = []`. Netzwerkfehler → ebenfalls `error` setzen. Kein Absturz.

**Keine Konfiguration** (leeres `jiraDomain`/`jiraEmail`/`jiraToken`) → `JiraService.fetch` wird nicht aufgerufen.

## AppSettings

Drei neue Felder (alle mit Default-Wert, damit alte gespeicherte Einstellungen weiter funktionieren):

```swift
public var jiraDomain: String = ""   // "mycompany.atlassian.net"
public var jiraEmail:  String = ""
public var jiraToken:  String = ""   // Atlassian API-Token
```

`CodingKeys` entsprechend erweitern. `init(from:)` mit `decodeIfPresent` für alle drei.

`var jiraConfigured: Bool { !jiraDomain.isEmpty && !jiraEmail.isEmpty && !jiraToken.isEmpty }`

## AppModel

```swift
@Published private(set) var jira = JiraAggregator.unknown
@Published private(set) var jiraRefreshRunning = false
```

- Eigener 5-Minuten-Timer (Jira-Issues ändern sich langsamer als PRs).
- `func refreshJira() async` — Single-flight wie `refreshPRs()`.
- Aufruf auch nach `NSWorkspace.didWakeNotification`.
- Wenn `!settings.jiraConfigured` → No-op.
- Nach Einstellungsänderung (`apply(_:old:)`): wenn Jira-Felder geändert → `Task { await refreshJira() }`.

## Einstellungs-UI

Neuer Reiter „Jira" im bestehenden `SettingsView`:

- `TextField("domain.atlassian.net", text: $settings.jiraDomain)`
- `TextField("vorname.nachname@firma.com", text: $settings.jiraEmail)`
- `SecureField("API-Token", text: $settings.jiraToken)` + Link zu `id.atlassian.com/manage-profile/security/api-tokens`
- Kein „Verbindung testen"-Button — Fehler erscheint beim nächsten Refresh im Dashboard.

## Dashboard

`DashboardView.SidebarSelection` (in StatusDisplay) bekommt einen neuen Case:
```swift
case jiraProject(String)   // projectKey
```

**Seitenleiste** — neuer Abschnitt „Jira" unterhalb der Agenten-Einträge, nur sichtbar wenn `settings.jiraConfigured`:
- Ein Eintrag pro Projekt: `"PROJ  3"` (Projektname + Zähler rechts)
- Auswahl → Mittelspalte zeigt Issues des Projekts, nach Sprint gruppiert

**Mittelspalte** bei Jira-Auswahl:
- Sprint-Header als `Section`-Label
- Jede Issue-Zeile: `[KEY] Zusammenfassung` + Status-Badge
- Fehler → `Text(snapshot.error)` statt Liste

**Detailspalte** bei ausgewählter Issue:
- Key, Titel, Status, Priorität (falls vorhanden), Sprint, Projekt
- `Button("In Jira öffnen")` → `NSWorkspace.shared.open(issue.url)`

**Toolbar**: `Button("Jira aktualisieren")` neben dem PR-Button, nur wenn `jiraConfigured && !jiraRefreshRunning`.

## Panel (BoardRenderer) & Board-Fenster (BoardWindowRenderer)

`BoardState` bekommt ein neues Feld:

```swift
public var jiraCount: Int = 0   // 0 wenn nicht konfiguriert oder keine Issues
```

**Panel:** Neue Zeile in der PR-Zone (rechts ab x≈1270):
- Nur wenn `jiraCount > 0`: `"Jira  \(jiraCount)"` als einzelne Zeile in `muted`/white-Farbe, unterhalb der PR-Tabelle.

**Board-Fenster:** Gleiche Zeile in der PR-Zone des Fenster-Renderers, unterhalb des bestehenden PR-Inhalts.

## CI ohne Secrets

`JiraFetcher`-Protokoll erlaubt Test-Stubs ohne echte API. Tests mocken HTTP-Antworten; kein echter Jira-Token in CI.

## Offene Fragen

Keine.
