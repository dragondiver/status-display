# status-display

Menüleisten-App für macOS, die auf dem AJAZZ AKP02 (9,2″, 1920×462) den
eigenen Arbeitsstatus, laufende Agenten und PRs zeigt.

Spec: `docs/superpowers/specs/2026-09-27-status-display-mac-app-design.md`

## Bauen

    swift test
    scripts/build.sh      # → build/StatusDisplay.app

Die App ist ad-hoc signiert. Auf einem anderen Mac einmal per Rechtsklick →
Öffnen starten.

## Lizenz

`Sources/StatusCore/Display/AKP02Protocol.swift` ist aus
[deonspengler/akp02](https://github.com/deonspengler/akp02) portiert und
steht unter MPL-2.0 (siehe Dateikopf). Die ESP32-Firmware liegt in
`legacy-esp32/`.
