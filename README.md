# status-display

Menüleisten-App für macOS, die auf dem AJAZZ AKP02 (9,2″, 1920×462) den
eigenen Arbeitsstatus, laufende Agenten und PRs zeigt.

Spec: `docs/superpowers/specs/2026-09-27-status-display-mac-app-design.md`

## Bauen

    swift test
    scripts/build.sh      # → build/StatusDisplay.app

Die App ist ad-hoc signiert. Auf einem anderen Mac einmal per Rechtsklick →
Öffnen starten.

## Einrichten

1. `StatusDisplay.app` nach `/Applications` kopieren, einmal per Rechtsklick → Öffnen starten.
2. Einstellungen → Allgemein: GitHub-Hosts eintragen (`github.com` und/oder GHE-Host).
   Voraussetzung: `gh auth login --hostname <host>`.
3. Einstellungen → Agenten: Blöcke für Claude Code (`~/.claude/settings.json`),
   Codex (`~/.codex/hooks.json`) und MCP-Clients kopieren und einfügen. Codex-Hooks sind
   standardmäßig aktiv; der zusätzliche `~/.codex/config.toml`-Block ist nur nötig, falls eine
   andere Konfiguration sie zuvor abgeschaltet hat.
4. Optional: „Bei Anmeldung starten“.

## Schnittstelle

Alle Anfragen gehen an `http://127.0.0.1:47615` mit
`Authorization: Bearer <~/Library/Application Support/status-display/token>`.

| Methode | Pfad | Inhalt |
|---|---|---|
| GET | `/v1/health` | ohne Token |
| POST | `/v1/events` | `{"source","session","state","name","project","detail","url"}`, state ∈ running, waiting, done, error, ended |
| POST | `/v1/status` | `{"preset":"deep-focus","minutes":60}`, minutes optional, gültig ist (0, 1440] |
| POST | `/mcp` | MCP (Streamable HTTP), Tool `report_status` |

Port (Einstellungen → Agenten) ist frei wählbar zwischen 1024 und 65535; ein GitHub-Host
wird beim Eintragen normalisiert (Schema `http(s)://` und abschließender `/` entfernt,
kleingeschrieben).

## Unterbefehle

    StatusDisplay hook claude-code|codex   # von Hooks aufgerufen, liest stdin
    StatusDisplay preview board.png        # Beispielbild rendern
    StatusDisplay display-test             # 15 s Farbfelder aufs Panel
    StatusDisplay version

## Lizenz

`Sources/StatusCore/Display/AKP02Protocol.swift` ist aus
[deonspengler/akp02](https://github.com/deonspengler/akp02) portiert und
steht unter MPL-2.0 (siehe Dateikopf). Die ESP32-Firmware liegt in
`legacy-esp32/`.
