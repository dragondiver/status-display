# status-display: Mac-App für das AJAZZ AKP02 — Design

Stand: 27.09.2026 · Status: Entwurf zur Freigabe

## Ziel

Eine kleine native Mac-App in der Menüleiste, die auf dem AJAZZ AKP02
(9,2″, 1920×462, USB-HID) ein Developer-Status-Board zeigt: den selbst
gesetzten Arbeitsstatus, laufende Agenten und PRs. Sie läuft auf Florians
privatem Mac **und** auf dem Arbeitgeber-Mac, jeweils mit eigener
Konfiguration.

Erfolg heißt: Ein Blick auf das Display sagt, (1) ob gestört werden darf,
(2) welcher Agent gerade auf Florian wartet, (3) ob Reviews anstehen oder ein
eigener PR rot ist. Ruhig, solange nichts zu tun ist.

## Rahmenbedingungen

| Punkt | Festlegung | Quelle |
|---|---|---|
| Plattform | macOS 14+, native Swift/SwiftUI, eine `.app` ohne Laufzeit | Entscheidung 27.09. (Weg A) |
| Zwei Macs | privat (github.com) und Arbeitgeber (GHE); keine Synchronisation, keine privaten Daten auf dem Firmen-Mac | Florian |
| Installation | Eigenbau, unsigniert bzw. ad-hoc signiert; einmal Rechtsklick → Öffnen | Florian: „Ich installiere dort den Eigenbau" |
| Agenten | Claude Code, Codex, GitHub Copilot, Devin u. a. | Florian |
| Display optional | Ohne angestecktes AKP02 läuft die App nur in der Menüleiste | Annahme, bestätigt |

## Spike-Ergebnis (27.09.2026)

Mit der Python-Library [deonspengler/akp02](https://github.com/deonspengler/akp02)
(v2.0.0, MPL-2.0) auf diesem Mac geprüft:

- macOS sieht das Gerät ohne Treiber: `0300:3017`, „HOTSPOTEKUSB HID DEMO",
  Usage Page `0xFFA0`, zwei Usages.
- Öffnen 0,02 s, Vollbild 0,10 s, Teilbild 0,013 s. Vollständiges Neuzeichnen
  bei jeder Änderung ist also unproblematisch.
- Das Panel schläft ohne Heartbeat ein und zeigt dann das AJAZZ-Logo
  (Library: alle 5 s). Nach Reconnect setzt es die Helligkeit auf 80 zurück.
- Teilbilder müssen auf der kurzen Achse an bestimmten Positionen beginnen,
  sonst stimmen die Farben nicht (`SHORT_AXIS_ALIGN_*` in der Library).
- Helvetica hat kein `◐`; Symbole werden gezeichnet, nicht als Glyphen gesetzt.

## Anzeige (Version 1, Layout seit Issue #14 27.09.2026)

```
┌──────────────┬───────────────────────┬────────────────────────────────────┐
│  DEEP        │  AGENTEN              │  PRs                               │
│  FOCUS       │  ● telefon-ai  läuft  │        Repo          Review  Offen │
│              │  ◐ rundfunk    wartet │  ●     telefon-ai       2      1   │
│              │    auf dich (4 min)   │        rundfunk         1      0   │
│  23:34       │  ✓ heim-agent  fertig │        heim-agent       0      0   │
│  seit 47 min │                       │        +3 weitere                  │
└──────────────┴───────────────────────┴────────────────────────────────────┘
   480 px            ~760 px                        ~680 px
```

- **Status**: Name rückt nach oben, Farbe je Status. Unten links in derselben
  Zone die Uhr (72 pt fett) mit „seit …" darunter. Die einzige Zone, die für
  Kolleg:innen gedacht ist.
- **Agenten**: höchstens 4 Zeilen, sortiert *wartet* → *Fehler* → *läuft* →
  *fertig*. „Wartet auf dich" ist das stärkste Signal der ganzen Anzeige
  (Akzentfarbe, Dauer). Mehr als 4: letzte Zeile „+2 weitere".
- **PRs**: eine Tabelle statt Summen, eine Zeile pro Repo (Repo · zu reviewen ·
  eigene offen). Roter Punkt vor dem Repo, wenn dort ein eigener Nicht-Draft-PR
  rote CI hat; roter Rand der ganzen Zone bei mindestens einem eigenen
  Nicht-Draft-PR mit roter CI, unabhängig von Anheften/Ausblenden. Jedes Repo
  hat einen von drei expliziten Zuständen – normal / angeheftet / ausgeblendet
  (`pinnedRepos`/`hiddenRepos`/`shownRepos`, Reiter „Repos", #15/#19) – oder,
  ohne Eintrag, den Standard seines Hosts (`hostDefaults`): `github.com` ist
  normal, jeder andere Host ist ausgeblendet. Angeheftete Repos erscheinen
  immer, auch mit 0/0; andere Repos nur bei Review-Request oder eigenem
  offenem PR; ausgeblendete nie. Sortierung: zuerst „zu reviewen" > 0, dann
  angeheftet, dann der Rest. Höchstens 5 Zeilen, danach „+N weitere". Gibt es
  Review-Requests an Florian in ausgeblendeten Repos, reserviert die Tabelle
  dafür immer eine eigene, nie abgeschnittene letzte Zeile „Ausgeblendet · N
  zu reviewen" (grau; eigene offene PRs zählen hier nicht) – im Menü
  aufklappbar mit den einzelnen PRs (#19).
- **Veraltete Daten** werden nie still weiter angezeigt: Ist eine Quelle länger
  als 3 Abfrageintervalle ohne Erfolg, wird ihre Zone grau und zeigt das Alter
  („PRs · Stand 14:05").

Die Menüleiste zeigt dieselben Informationen ausführlich und klickbar.

## Architektur

Ein Prozess, klar getrennte Einheiten. Alles außer `AKP02Driver` und der UI
ist ohne Gerät und ohne Netz testbar.

```
                ┌────────────── Eingänge ──────────────┐
 Claude-Hooks ─▶│ IngressServer  (127.0.0.1)            │
 Codex notify ─▶│   POST /v1/events   ─┐                │
 MCP-Agenten  ─▶│   /mcp (Streamable) ─┴▶ AgentRegistry │──┐
                └──────────────────────────────────────┘  │
 gh-Token ─▶ PRProvider (github.com, GHE) ─────────────────┤
 Menüleiste ─▶ StatusStore ────────────────────────────────┤
                                                            ▼
                                                     BoardState
                                                            │
                                  ┌─────────────────────────┴──────┐
                                  ▼                                ▼
                          Renderer (CGImage)               MenuBar-UI
                                  │
                                  ▼
                          AKP02Driver (IOKit HID)
```

### 1. `AKP02Driver`

- Findet das Gerät über `IOHIDManager` (VID `0x0300`, PID `0x3017`), reagiert
  auf An- und Abstecken sowie auf Aufwachen aus dem Ruhezustand.
- API: `screenOn()`, `setBrightness(_:)`, `show(jpeg:at:)`, `heartbeat()`.
- Heartbeat alle 5 s aus einem Timer. Bildübertragungen und Heartbeat laufen
  seriell über eine Queue, damit kein Heartbeat mitten in ein Bild fällt.
- Nach jedem (Re-)Connect: `screenOn`, Helligkeit aus der Konfiguration,
  vollständiges Bild.
- Protokoll portiert aus `akp02` (Befehle, Bild-Header, Aufteilung in
  1024-Byte-Reports). Die App sendet **nur Vollbilder** (0,10 s pro Bild
  reichen), daher entfallen Teilbilder, Ausrichtungsregel und Wartezeit
  zwischen Teilbildern.
  Die portierte Datei bleibt unter MPL-2.0 mit Quellenangabe; der Rest des
  Projekts ist davon nicht betroffen (MPL ist dateibezogen).
- Aufgeteilt in `AKP02Protocol` (reine Byte-Erzeugung, testbar) und
  `AKP02Transport` (IOKit).

### 2. `Renderer`

Reine Funktion `BoardState → CGImage (1920×462)`, danach JPEG-Kodierung.
Zeichnet mit Core Graphics/Core Text, Symbole als Formen. Die Zoneneinteilung
ist Code, nicht Konfiguration (YAGNI). Bei jeder Änderung von `BoardState`
wird neu gezeichnet, höchstens 2× pro Sekunde; die Uhr stößt einmal pro Minute
ein Neuzeichnen an.

### 3. `StatusStore`

- Vorgaben (konfigurierbar, Reihenfolge = Menü): *Deep Focus* (rot),
  *In Meeting* (violett), *Easy Coding* (grün), *Verfügbar* (grau),
  *Pause* (blau). Name und Farbe je Eintrag.
- Setzen per Menüleiste; optional mit Ablauf (30 min, 1 h, 2 h, bis
  Tagesende), danach zurück auf *Verfügbar*.
- Merkt sich Status und Startzeit über Neustarts hinweg (`UserDefaults`).
- Neben dem manuellen Status gibt es einen automatischen Status mit Quelle,
  der Vorrang hat, solange er gesetzt ist. In Version 1 ungenutzt; er ist die
  Andockstelle für Teams (siehe Version 2).
- Der Status ist auch über den Ingress setzbar (`POST /v1/status`), damit ein
  Kurzbefehl oder ein Skript ihn schalten kann. Agenten ändern ihn nicht.

### 4. `AgentRegistry`

Gemeinsames Modell für alle Eingänge:

```swift
struct AgentActivity {
    let id: String          // Quelle + Session-ID
    let source: String      // "claude-code", "codex", "mcp:<client>" …
    var name: String        // Anzeigename, z. B. Projekt oder Agent
    var project: String?
    var state: State        // .running, .waiting, .done, .error
    var since: Date         // Beginn des aktuellen Zustands
    var detail: String?     // eine Zeile, z. B. "wartet auf Freigabe: Bash"
    var url: URL?           // Link für die Menüleiste
    var lastSeen: Date
}
```

Regeln (Code, nicht Agent-Ermessen):

- *fertig* verschwindet nach 10 min.
- *läuft* ohne Meldung seit 30 min wird zu *unklar* (grau, „keine Meldung seit
  …"). Nach 4 h ohne Meldung wird der Eintrag entfernt.
- *wartet* und *Fehler* bleiben stehen, bis eine neue Meldung kommt oder
  Florian sie in der Menüleiste wegklickt.
- Nur im Speicher. Nach einem App-Neustart ist die Liste leer und füllt sich
  mit den nächsten Meldungen.

### 5. `IngressServer`

Lokaler HTTP-Server, gebunden **nur an `127.0.0.1`**, Port konfigurierbar
(Standard 47615).

- `POST /v1/events` — ein Ereignis:
  `{"source","session","state","name","project","detail","url"}`.
- `POST /v1/status` — manuellen Status setzen.
- `GET /v1/health` — für Skripte und Tests.
- `/mcp` — MCP-Server (Streamable HTTP, nur JSON-Antworten, kein SSE; von
  Hand implementiert: `initialize`, `ping`, `tools/list`, `tools/call`) mit einem Tool
  `report_status(state, name, project?, detail?, url?)` und dem Hinweistext,
  dass Agenten es bei Beginn, beim Warten auf den Menschen und am Ende
  aufrufen sollen. Session-ID aus der MCP-Session.
- **Schutz**: Jede Anfrage braucht den Header `Authorization: Bearer <token>`.
  Das Token erzeugt die App beim ersten Start und legt es in
  `~/Library/Application Support/status-display/token` ab (Rechte 0600).
  Das verhindert, dass eine beliebige Webseite im Browser per `fetch` an
  `localhost` Ereignisse einschleust.

### 6. Agent-Anbindung (Version 1)

**Claude Code** über Hooks in `~/.claude/settings.json`. Die App schreibt die
Datei nicht selbst; sie zeigt im Einstellungsfenster den fertigen Block zum
Kopieren und nutzt als Befehl die App-Binärdatei mit `hook claude-code`, die das
stdin-JSON der Hooks in ein Ereignis übersetzt:

| Hook | Zustand |
|---|---|
| `SessionStart`, `UserPromptSubmit`, `PostToolUse` | läuft |
| `Notification` (Freigabe, Leerlauf) | wartet |
| `Stop` | fertig |
| `SessionEnd` | Eintrag entfernen |

`PostToolUse` hält *läuft* frisch und holt einen Eintrag nach einer Freigabe
aus *wartet* zurück. Der Hook-Befehl ist fehlertolerant: Läuft die App nicht,
endet es still mit Exit 0 und verzögert Claude nie (Timeout 1 s).

**Codex CLI** über Hooks in `~/.codex/hooks.json` (gleiches Format und
gleiche stdin-Nutzlast wie Claude Code; je nach Codex-Version per
`[features] hooks = true` in `config.toml` einzuschalten). Zusätzlich zu den
Claude-Ereignissen: `PermissionRequest` → wartet.

Beide rufen dasselbe Programm auf: die App-Binärdatei selbst mit dem
Unterbefehl `hook <quelle>` (z. B. `StatusDisplay hook codex`). So braucht es
kein Skript, kein `jq` und kein Python auf dem Arbeitgeber-Mac. Der Unterbefehl
liest Token und Port aus Application Support und gibt nie etwas auf stdout aus
(Claude würde es sonst als Kontext übernehmen).

Leerlauf-Hinweise von Claude (`Notification` mit `notification_type`
`idle_prompt`) werden ignoriert: nach `Stop` gilt *fertig*, sonst stünde jede
offene Session dauerhaft auf *wartet*.

**MCP** für alle lokalen Agenten mit MCP-Unterstützung (Copilot im
Agent-Modus in VS Code u. a.): Eintrag `http://127.0.0.1:47615/mcp` mit
Token-Header in der jeweiligen MCP-Konfiguration, dazu eine Zeile in den
Agent-Anweisungen. Verlässlich ist das nur, soweit der Agent das Tool aufruft;
deshalb gilt die 30-Minuten-Regel für *unklar* auch hier.

### 7. `PRProvider`

- Konfigurierte Hosts, je Mac eigene Liste: `github.com` und/oder der GHE-Host.
- Token pro Host über `gh auth token --hostname <host>`. Die App speichert kein
  eigenes Token. `gh` wird unter `/opt/homebrew/bin`, `/usr/local/bin` und
  einem konfigurierbaren Pfad gesucht, weil Menüleisten-Apps kein Shell-`PATH`
  haben.
- Eine GraphQL-Abfrage pro Host alle 2 min (und sofort per Menüpunkt
  „Aktualisieren"):
  - `is:open is:pr review-requested:@me` → „zu reviewen"
  - `is:open is:pr author:@me` mit `statusCheckRollup` → „eigene offen",
    „CI rot"
- GHE-API-Endpunkt: `https://<host>/api/graphql`.
- Fehler (kein `gh`, nicht angemeldet, Netz) erscheinen als Klartext in der
  Menüleiste; die Zone wird nach der Veraltungsregel grau.

### 8. Menüleiste und Einstellungen

- Symbol in der Menüleiste in der Farbe des aktuellen Status, mit Punkt, wenn
  ein Agent wartet.
- Menü: Status-Auswahl (mit Ablauf-Untermenü) · Agentenliste (Klick öffnet
  `url`, Wegklicken für *wartet*) · PR-Listen je Host (Klick öffnet den PR) ·
  Display-Zustand (verbunden / nicht gefunden) · Einstellungen · Beenden.
- Einstellungen: Status-Vorgaben, Hosts, Helligkeit, Port, Token neu erzeugen,
  Hook-Block zum Kopieren, Start bei Anmeldung (`SMAppService`).
- Konfiguration liegt lokal pro Mac (`UserDefaults` bzw. Application Support);
  nichts wird synchronisiert.

## Fehlerbehandlung

| Lage | Verhalten |
|---|---|
| Display nicht angesteckt | App läuft weiter, Menü zeigt „Display nicht gefunden", verbindet automatisch beim Anstecken |
| Display nach Ruhezustand oder Reconnect | screenOn, Helligkeit, Vollbild |
| App beendet | Panel fällt nach dem letzten Heartbeat auf das AJAZZ-Logo zurück — sichtbares Zeichen, dass die App nicht läuft |
| `gh` fehlt oder nicht angemeldet | Hinweis in der Menüleiste, PR-Zone grau mit „?" |
| Quelle liefert nicht mehr | Zone grau mit Zeitstempel des letzten Erfolgs |
| Port belegt | Hinweis in der Menüleiste; Port in den Einstellungen änderbar |
| Ungültiges Ereignis oder falsches Token | HTTP 400/401, nichts an der Anzeige ändert sich |

## Tests

- `AKP02Protocol`: Byte-Tests gegen das in `akp02` dokumentierte Protokoll
  (Befehle, Header, Aufteilung, Commit). Fremder Code wird dafür nicht
  ausgeführt.
- `AgentRegistry`: Zustandsübergänge und Zeitregeln mit injizierter Uhr.
- `IngressServer`: Token-Prüfung, Ereignis-Parsing, MCP-Tool-Aufruf.
- `PRProvider`: Parsing aufgezeichneter GraphQL-Antworten, Fehlerfälle.
- `Renderer`: Pixel-Stichproben (Statusfarbe, roter CI-Rand, Drehung ins
  Hochformat) und reine Textfunktionen („seit 47 min", „+2 weitere",
  Kürzung). Dazu der Unterbefehl `preview <datei.png>` für die Sichtprüfung.
  Keine PNG-Vergleiche, weil Schriftglättung zwischen Macs abweicht.
- Gerät und Menüleiste: manuelle Checkliste.
- CI: GitHub Actions auf macOS, ohne Secrets (Konvention aller Repos).

## Bauen und Verteilen

- Swift Package (Bibliothek `StatusCore` mit aller Logik, ausführbares Ziel
  `StatusDisplay` mit Menüleiste und Unterbefehlen). `scripts/build.sh` baut
  universal (arm64 + x86_64) und packt `build/StatusDisplay.app` mit
  `Info.plist` (`LSUIElement`), ad-hoc signiert. Kein Xcode-Projekt im Repo.
- Auf den Arbeitgeber-Mac per Kopie; erster Start per Rechtsklick → Öffnen.
- Die bisherige ESP32-Firmware wandert nach `legacy-esp32/`.

## Version 2: Microsoft Teams in beide Richtungen

Gewünscht (Florian, 27.09.2026): Teams und App gleichen den Status in beide
Richtungen ab. Nicht in Version 1, weil beide Wege am Arbeitgeber-Mac erst
geprüft werden müssen. Version 1 bereitet es nur im `StatusStore` vor.

**Teams → App** („in einem Call" → *In Meeting*)

- Weg 1, bevorzugt: die lokale Drittanbieter-API des neuen Teams-Clients
  (Datenschutz → „API von Drittanbietern verwalten"). Liefert
  Besprechungszustand, Stummschaltung und Kamera, ohne App-Registrierung im
  Tenant; Teams fragt einmal selbst nach. Vorab zu prüfen: ob die Einstellung
  am Arbeitgeber-Mac freigegeben ist und welche Zustände die API heute liefert.
- Weg 2: Graph `/me/presence` (`Presence.Read`) — liefert auch *Beschäftigt*
  und *Nicht stören*, braucht aber eine App-Registrierung im Firmen-Tenant.

**App → Teams** (*Deep Focus* → *Nicht stören*)

- Nur über Graph `setUserPreferredPresence` (`Presence.ReadWrite`),
  Device-Code-Anmeldung, Token im Schlüsselbund. Setzt eine App-Registrierung
  mit Zustimmung der IT voraus.
- Zuordnung konfigurierbar, Vorschlag: *Deep Focus* → Nicht stören,
  *In Meeting* → Beschäftigt, *Pause* → Abwesend, sonst → Verfügbar.

**Kein Pingpong**: Setzt die App den Teams-Status, ignoriert sie das daraus
folgende Teams-Ereignis. Ein automatisch gesetzter Status wird nie nach Teams
zurückgeschrieben, wenn er aus Teams kam.

**Vorbereitung in Version 1**: Der `StatusStore` kennt neben dem manuellen
Status einen *automatischen* Status mit Quelle (zunächst ungenutzt). Ist er
gesetzt, hat er Vorrang; endet er, gilt wieder der manuelle Status. So braucht
Version 2 keinen Umbau.

**Vor dem Bau zu klären (Florian, Arbeitgeber)**: Drittanbieter-API in Teams
freigegeben? Graph-App-Registrierung mit `Presence.ReadWrite` möglich?

## Nicht in Version 1

- Microsoft Teams (siehe Version 2 oben).
- Cloud-Agenten (Devin, Copilot Coding Agent, Codex Cloud) — Version 2, je
  Anbieter eigene Zugangsdaten, am Arbeitgeber-Mac erst zu klären.
- Kalender/nächster Termin — Version 2 (am Arbeitgeber-Mac vermutlich Outlook).
- Slack-Präsenz, Spotify, Systemwerte (CPU usw.).
- Synchronisation zwischen den Macs.
- Frei konfigurierbares Layout.

## Geklärte Punkte (27.09.2026)

1. Codex hat Hooks im Claude-Format (`~/.codex/hooks.json`); `notify` wird
   nicht gebraucht.
2. MCP ohne Bibliothek, von Hand (siehe `IngressServer`).
3. Eingabeüberwachung: Das Gerät hat eine herstellerspezifische Usage Page;
   der Spike hat es ohne Freigabe geöffnet. Die App prüft das beim ersten
   Start, der Plan enthält den Schritt.
