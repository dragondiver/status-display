# status-display Mac-App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eine native Menüleisten-App für macOS, die auf dem AJAZZ AKP02 (1920×462, USB-HID) Arbeitsstatus, laufende Agenten und PRs zeigt und Agenten über Hooks und MCP entgegennimmt.

**Architecture:** Swift Package mit zwei Zielen. `StatusCore` enthält die gesamte Logik (Protokoll, Status, Agenten, HTTP/MCP, PRs, Renderer) und ist ohne Gerät und Netz testbar. `StatusDisplay` ist die Menüleisten-App mit Unterbefehlen (`hook`, `preview`, `display-test`, `version`). Alle Eingänge münden in `AppModel` auf dem Main-Thread, das bei jeder Änderung ein Vollbild rendert und an den `DisplayController` gibt.

**Tech Stack:** Swift 6.4 Toolchain im Sprachmodus 5, SwiftUI `MenuBarExtra`, IOKit HID, Network.framework (`NWListener`), Core Graphics/Core Text/ImageIO, XCTest. Keine externen Pakete.

**Spec:** `docs/superpowers/specs/2026-09-27-status-display-mac-app-design.md`

## Global Constraints

- macOS 14+ (`platforms: [.macOS(.v14)]`), keine externen Swift-Pakete.
- Gerät: VID `0x0300`, PID `0x3017`, Output-Reports 1024 Byte, Bildpuffer 462×1920 Hochformat, Querformat wird 90° im Uhrzeigersinn gedreht.
- Heartbeat alle 5 s; nach jedem (Re-)Connect: `DIS`, `LIG <helligkeit>`, letztes Vollbild.
- Nur Vollbilder, höchstens 2 Renderläufe pro Sekunde.
- HTTP-Server nur auf `127.0.0.1`, Standardport `47615`, jede Anfrage außer `GET /v1/health` mit `Authorization: Bearer <token>`.
- Token und Endpoint in `~/Library/Application Support/status-display/` (`token` mit 0600, Verzeichnis 0700, `endpoint.json`).
- Agentenregeln: *fertig* verschwindet nach 600 s; *läuft* ohne Meldung seit 1800 s → *unklar*; *läuft*/*unklar* ohne Meldung seit 14 400 s → entfernt; *wartet* und *Fehler* bleiben bis zur nächsten Meldung oder bis zum Wegklicken.
- PRs: Abfrage alle 120 s je Host; Zone veraltet, wenn der älteste Erfolg länger als 360 s zurückliegt oder es keinen gibt.
- Token pro Host nur über `gh auth token --hostname <host>`; die App speichert kein GitHub-Token.
- Der Hook-Unterbefehl schreibt nie auf stdout und endet immer mit Exit 0.
- Nutzersichtbare Texte auf Deutsch.
- CI in GitHub Actions ohne Secrets.
- `Sources/StatusCore/Display/AKP02Protocol.swift` steht unter MPL-2.0 mit Quellenangabe; alle anderen Dateien nicht.

## Review Focus

1. **Display während einer Übertragung abgezogen oder Mac aus dem Ruhezustand** → App stürzt nicht ab, Menü zeigt „Display nicht gefunden“, beim Wiederanstecken erscheinen Helligkeit und letztes Bild sofort (Test in Task 3: Schreibfehler → getrennt, erneutes `attach` → Init + letztes Bild).
2. **`gh` fehlt oder ist für den GHE-Host nicht angemeldet** (typisch am Arbeitgeber-Mac) → klare Meldung in der Menüleiste, PR-Zone grau mit „?“, kein Absturz (Tests in Task 10: fehlendes Binary → `ghNotFound`, Exit ≠ 0 → `notLoggedIn`, HTTP 401 → `http(401)`).
3. **Hook läuft, während die App nicht läuft** → Hook endet still und schnell, Claude/Codex werden nicht aufgehalten (Test in Task 9: Senden an geschlossenen Port liefert `false` in unter 2 s).
4. **Viele Agenten oder lange Namen** → höchstens 4 Zeilen, „+N weitere“, Namen mit „…“ gekürzt, Statusname passt in die Zone (Tests in Task 6).
5. **Fremde Anfragen an localhost** (Browser, anderer Prozess, kaputtes JSON) → 401 bzw. 400, nie ein Absturz, Anzeige unverändert (Tests in Task 7 und 8).

---

## Dateistruktur

```
status-display/
  Package.swift
  Resources/Info.plist
  scripts/build.sh
  .github/workflows/ci.yml
  legacy-esp32/                      (bisherige Firmware, unverändert verschoben)
  Sources/StatusCore/
    Support/TimeSource.swift         Uhr-Abstraktion für Tests
    Support/Locked.swift             threadsicherer Wert
    Support/RGBColor.swift           Farben aus Hex
    Support/AppSupport.swift         Token, endpoint.json
    Settings/AppSettings.swift       Einstellungen pro Mac
    Display/AKP02Protocol.swift      Byte-Protokoll (MPL-2.0)
    Display/AKP02Transport.swift     IOKit-Gerätesuche und Schreiben
    Display/DisplayController.swift  Init, Heartbeat, Reconnect, letztes Bild
    Display/PanelImage.swift         Drehung, JPEG, PNG
    Status/StatusPreset.swift        Vorgaben
    Status/StatusStore.swift         manueller + automatischer Status
    Agents/AgentEvent.swift          Ereignis + Validierung
    Agents/AgentActivity.swift       Zustand eines Agenten
    Agents/AgentRegistry.swift       Regeln, Sortierung
    Agents/HookEventMapper.swift     Claude/Codex-Hook → Ereignis
    Agents/EventSender.swift         Hook → App (HTTP)
    Agents/HookSnippets.swift        Konfigurationsblöcke zum Kopieren
    Server/HTTPMessage.swift         Request, Response, Parser
    Server/HTTPServer.swift          NWListener
    Server/IngressRouter.swift       /v1/*, Auth, /mcp-Weiterleitung
    Server/MCPHandler.swift          JSON-RPC, Tool report_status
    PRs/PullRequest.swift            Modelle, Fehler
    PRs/GitHubAPI.swift              GraphQL-Abfrage und Parsing
    PRs/GHCLITokenProvider.swift     gh auth token
    PRs/PRService.swift              Abruf
    PRs/PRAggregator.swift           Hosts zusammenführen, Veraltung
    Render/BoardState.swift          Eingabe des Renderers
    Render/BoardText.swift           reine Textfunktionen
    Render/BoardRenderer.swift       Zeichnen 1920×462
  Sources/StatusDisplay/
    main.swift                       Unterbefehle, sonst App
    StatusDisplayApp.swift           Scenes
    AppModel.swift                   Verdrahtung
    MenuContent.swift                Menü
    SettingsView.swift               Einstellungen
    StatusIcon.swift                 farbiges Menüleisten-Symbol
    CLI.swift                        hook, preview, display-test
  Tests/StatusCoreTests/             ein Testfile je Einheit
```

---

### Task 1: Projektgerüst, Legacy-Umzug, Build und CI

**Files:**
- Move: `platformio.ini`, `src/` → `legacy-esp32/`
- Create: `legacy-esp32/README.md`, `Package.swift`, `Sources/StatusCore/Support/TimeSource.swift`, `Sources/StatusDisplay/main.swift`, `Sources/StatusDisplay/StatusDisplayApp.swift`, `Resources/Info.plist`, `scripts/build.sh`, `.github/workflows/ci.yml`, `Tests/StatusCoreTests/TimeSourceTests.swift`
- Modify: `README.md` (neu schreiben), `.gitignore`

**Interfaces:**
- Produces: `protocol TimeSource: AnyObject { var now: Date { get } }`, `final class SystemTime: TimeSource`, `final class ManualTime: TimeSource { var now: Date; init(_ start: Date = Date(timeIntervalSince1970: 1_790_000_000)); func advance(_ seconds: TimeInterval) }`

- [ ] **Step 1: Legacy verschieben**

```bash
cd /Users/florian/Development/status-display
mkdir -p legacy-esp32
git mv platformio.ini legacy-esp32/platformio.ini
git mv src legacy-esp32/src
git mv README.md legacy-esp32/README.md
```

- [ ] **Step 2: Package.swift anlegen**

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "StatusDisplay",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "StatusCore",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .executableTarget(name: "StatusDisplay", dependencies: ["StatusCore"]),
        .testTarget(name: "StatusCoreTests", dependencies: ["StatusCore"]),
    ],
    swiftLanguageModes: [.v5]
)
```

- [ ] **Step 3: Failing test schreiben** — `Tests/StatusCoreTests/TimeSourceTests.swift`

```swift
import XCTest
@testable import StatusCore

final class TimeSourceTests: XCTestCase {
    func testManualTimeAdvances() {
        let t = ManualTime(Date(timeIntervalSince1970: 100))
        t.advance(60)
        XCTAssertEqual(t.now, Date(timeIntervalSince1970: 160))
    }
}
```

- [ ] **Step 4: Test laufen lassen, muss fehlschlagen**

Run: `swift test --filter TimeSourceTests`
Expected: Build-Fehler „cannot find 'ManualTime' in scope“.

- [ ] **Step 5: TimeSource implementieren** — `Sources/StatusCore/Support/TimeSource.swift`

```swift
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
```

- [ ] **Step 6: App-Skelett** — `Sources/StatusDisplay/StatusDisplayApp.swift`

```swift
import SwiftUI

struct StatusDisplayApp: App {
    var body: some Scene {
        MenuBarExtra("Status", systemImage: "circle.fill") {
            Button("Beenden") { NSApp.terminate(nil) }
        }
        .menuBarExtraStyle(.menu)
    }
}
```

`Sources/StatusDisplay/main.swift`:

```swift
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "version":
    print("status-display 1.0")
    exit(0)
default:
    StatusDisplayApp.main()
}
```

- [ ] **Step 7: Info.plist** — `Resources/Info.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.fhuber.status-display</string>
    <key>CFBundleName</key><string>StatusDisplay</string>
    <key>CFBundleExecutable</key><string>StatusDisplay</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
```

- [ ] **Step 8: Build-Skript** — `scripts/build.sh` (danach `chmod +x scripts/build.sh`)

```bash
#!/bin/bash
# Baut build/StatusDisplay.app (universal, ad-hoc signiert).
set -euo pipefail
cd "$(dirname "$0")/.."
ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}" --product StatusDisplay
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/StatusDisplay"
APP=build/StatusDisplay.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/StatusDisplay"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "$APP"
```

- [ ] **Step 9: CI** — `.github/workflows/ci.yml`

```yaml
name: ci
on:
  push:
    branches: [main]
  pull_request:
jobs:
  test:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - run: swift test
      - run: scripts/build.sh
```

- [ ] **Step 10: README und .gitignore**

`legacy-esp32/README.md` bekommt oben einen Absatz:

```markdown
> **Archiv.** Diese ESP32-Firmware ist seit 27.09.2026 abgelöst durch die
> Mac-App im Repo-Wurzelverzeichnis. Sie bleibt hier unverändert liegen.
```

`README.md` (neu):

```markdown
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
```

`.gitignore` ergänzen:

```
.build/
build/
.swiftpm/
```

- [ ] **Step 11: Tests und Build prüfen**

Run: `swift test && scripts/build.sh && build/StatusDisplay.app/Contents/MacOS/StatusDisplay version`
Expected: `Executed 1 test, with 0 failures`, dann `build/StatusDisplay.app`, dann `status-display 1.0`.

- [ ] **Step 12: Commit**

```bash
git add -A
git commit -m "Gerüst: Swift Package, Build-Skript, CI; ESP32-Firmware nach legacy-esp32/"
```

---

### Task 2: AKP02-Protokoll

**Files:**
- Create: `Sources/StatusCore/Display/AKP02Protocol.swift`
- Test: `Tests/StatusCoreTests/AKP02ProtocolTests.swift`

**Interfaces:**
- Produces: `enum AKP02Protocol { static let vendorID: Int; static let productID: Int; static let reportSize: Int; static let longSide: Int; static let shortSide: Int; static func screenOn() -> [UInt8]; static func brightness(_ percent: Int) -> [UInt8]; static func heartbeat() -> [UInt8]; static func commit() -> [UInt8]; static func fullFrameHeader(jpegLength: Int) -> [UInt8]; static func fullFrameReports(jpeg: [UInt8]) -> [[UInt8]] }`

- [ ] **Step 1: Failing tests schreiben**

```swift
import XCTest
@testable import StatusCore

final class AKP02ProtocolTests: XCTestCase {
    private func ascii(_ s: String) -> [UInt8] { Array(s.utf8) }

    func testCommandsArePaddedTo1024() {
        for report in [AKP02Protocol.screenOn(), AKP02Protocol.heartbeat(),
                       AKP02Protocol.commit(), AKP02Protocol.brightness(50)] {
            XCTAssertEqual(report.count, 1024)
        }
    }

    func testScreenOnLayout() {
        let r = AKP02Protocol.screenOn()
        XCTAssertEqual(Array(r[0..<10]), ascii("CRT") + [0, 0] + ascii("DIS") + [0, 0])
        XCTAssertTrue(r[10...].allSatisfy { $0 == 0 })
    }

    func testHeartbeatLayout() {
        let r = AKP02Protocol.heartbeat()
        XCTAssertEqual(Array(r[0..<14]), ascii("CRT") + [0, 0] + ascii("CONNECT") + [0, 0])
    }

    func testBrightnessParamAndClamp() {
        XCTAssertEqual(Array(AKP02Protocol.brightness(60)[0..<11]),
                       ascii("CRT") + [0, 0] + ascii("LIG") + [0, 0] + [60])
        XCTAssertEqual(AKP02Protocol.brightness(150)[10], 100)
        XCTAssertEqual(AKP02Protocol.brightness(-5)[10], 0)
    }

    func testFullFrameHeader() {
        let h = AKP02Protocol.fullFrameHeader(jpegLength: 1000)
        XCTAssertEqual(h.count, 32)
        XCTAssertEqual(Array(h[0..<3]), ascii("CRT"))
        XCTAssertEqual(Array(h[3..<5]), [0, 0])
        XCTAssertEqual(Array(h[5..<8]), ascii("DRA"))
        XCTAssertEqual(Array(h[8..<12]), [0x00, 0x00, 0x04, 0x08]) // 1000 + 0x20, big endian
        XCTAssertEqual(h[12], 0xB1)
        XCTAssertTrue(h[13...].allSatisfy { $0 == 0 }) // Vollbild: w/h/x/y = 0
    }

    func testFullFrameReportsChunkAndCommit() {
        let jpeg = (0..<2000).map { UInt8($0 % 251) }
        let reports = AKP02Protocol.fullFrameReports(jpeg: jpeg)
        XCTAssertEqual(reports.count, 3) // 2032 Byte Nutzlast → 2 Reports + Commit
        XCTAssertTrue(reports.allSatisfy { $0.count == 1024 })
        XCTAssertEqual(Array(reports[0][0..<32]), AKP02Protocol.fullFrameHeader(jpegLength: 2000))
        XCTAssertEqual(Array(reports[0][32..<1024]), Array(jpeg[0..<992]))
        XCTAssertEqual(Array(reports[1][0..<1008]), Array(jpeg[992..<2000]))
        XCTAssertTrue(reports[1][1008...].allSatisfy { $0 == 0 })
        XCTAssertEqual(reports[2], AKP02Protocol.commit())
    }
}
```

- [ ] **Step 2: Test laufen lassen, muss fehlschlagen**

Run: `swift test --filter AKP02ProtocolTests`
Expected: Build-Fehler „cannot find 'AKP02Protocol' in scope“.

- [ ] **Step 3: Implementieren** — `Sources/StatusCore/Display/AKP02Protocol.swift`

```swift
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Protokoll portiert aus deonspengler/akp02 v2.0.0 (akp02/__init__.py),
// reverse-engineered von Deon Spengler. Nur Vollbilder; Teilbilder mit
// ihrer Farbausrichtungsregel werden bewusst nicht unterstützt.

import Foundation

public enum AKP02Protocol {
    public static let vendorID = 0x0300
    public static let productID = 0x3017
    public static let reportSize = 1024
    public static let longSide = 1920
    public static let shortSide = 462

    public static func screenOn() -> [UInt8] { command("DIS") }
    public static func heartbeat() -> [UInt8] { command("CONNECT") }
    public static func commit() -> [UInt8] { command("STP") }

    public static func brightness(_ percent: Int) -> [UInt8] {
        command("LIG", params: [UInt8(min(max(percent, 0), 100))])
    }

    /// 32-Byte-Header einer Bildübertragung; alle Koordinaten 0 = ganzes Panel.
    public static func fullFrameHeader(jpegLength: Int) -> [UInt8] {
        var h = [UInt8](repeating: 0, count: 32)
        h.replaceSubrange(0..<3, with: Array("CRT".utf8))
        h.replaceSubrange(5..<8, with: Array("DRA".utf8))
        let total = UInt32(jpegLength + 0x20)
        h[8] = UInt8((total >> 24) & 0xFF)
        h[9] = UInt8((total >> 16) & 0xFF)
        h[10] = UInt8((total >> 8) & 0xFF)
        h[11] = UInt8(total & 0xFF)
        h[12] = 0xB1
        return h
    }

    /// Header + JPEG in 1024-Byte-Reports, danach der Commit (`STP`).
    public static func fullFrameReports(jpeg: [UInt8]) -> [[UInt8]] {
        let payload = fullFrameHeader(jpegLength: jpeg.count) + jpeg
        var reports: [[UInt8]] = []
        var offset = 0
        while offset < payload.count {
            let end = min(offset + reportSize, payload.count)
            reports.append(pad(Array(payload[offset..<end])))
            offset = end
        }
        reports.append(commit())
        return reports
    }

    static func command(_ mnemonic: String, params: [UInt8] = []) -> [UInt8] {
        pad(Array("CRT".utf8) + [0, 0] + Array(mnemonic.utf8) + [0, 0] + params)
    }

    static func pad(_ bytes: [UInt8]) -> [UInt8] {
        precondition(bytes.count <= reportSize, "Report zu lang")
        return bytes + [UInt8](repeating: 0, count: reportSize - bytes.count)
    }
}
```

- [ ] **Step 4: Tests laufen lassen**

Run: `swift test --filter AKP02ProtocolTests`
Expected: `Executed 6 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/StatusCore/Display/AKP02Protocol.swift Tests/StatusCoreTests/AKP02ProtocolTests.swift
git commit -m "AKP02-Protokoll: Befehle, Vollbild-Header, Reports (MPL-2.0-Port)"
```

---

### Task 3: Panel-Bild, Gerätetreiber und DisplayController

**Files:**
- Create: `Sources/StatusCore/Display/PanelImage.swift`, `Sources/StatusCore/Display/AKP02Transport.swift`, `Sources/StatusCore/Display/DisplayController.swift`, `Sources/StatusDisplay/CLI.swift`
- Modify: `Sources/StatusDisplay/main.swift`
- Test: `Tests/StatusCoreTests/PanelImageTests.swift`, `Tests/StatusCoreTests/DisplayControllerTests.swift`, `Tests/StatusCoreTests/TestSupport.swift`

**Interfaces:**
- Consumes: `AKP02Protocol` (Task 2)
- Produces:
  - `enum PanelImage { static func makeContext(width: Int, height: Int) -> CGContext; static func rotateForPanel(_ landscape: CGImage) -> CGImage; static func jpeg(_ image: CGImage, quality: Double = 0.85) -> [UInt8]; static func png(_ image: CGImage) -> Data; static func encode(landscape: CGImage) -> [UInt8] }`
  - `protocol HIDReportWriter: AnyObject { func write(_ report: [UInt8]) throws }`
  - `enum AKP02Error: Error, Equatable { case writeFailed(Int32) }`
  - `final class AKP02Transport { var onConnect: ((HIDReportWriter) -> Void)?; var onDisconnect: (() -> Void)?; init(); func start() }`
  - `final class DisplayController { enum State: Equatable { case disconnected, connected }; var onStateChange: ((State) -> Void)?; init(brightness: Int = 60); func attach(_ writer: HIDReportWriter); func detach(); func reinitialize(); func show(jpeg: [UInt8]); func setBrightness(_ percent: Int); func flush() }`
  - Testhilfe `func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8)` (Koordinaten von oben links)

- [ ] **Step 1: Testhilfe** — `Tests/StatusCoreTests/TestSupport.swift`

```swift
import CoreGraphics
@testable import StatusCore

/// Liest ein Pixel, Koordinaten von oben links.
func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
    var buffer = [UInt8](repeating: 0, count: 4)
    let ctx = CGContext(data: &buffer, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.interpolationQuality = .none
    ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return (buffer[0], buffer[1], buffer[2])
}

func isRed(_ p: (r: UInt8, g: UInt8, b: UInt8)) -> Bool { p.r > 200 && p.g < 60 && p.b < 60 }
func isBlue(_ p: (r: UInt8, g: UInt8, b: UInt8)) -> Bool { p.b > 200 && p.r < 60 && p.g < 60 }

final class FakeWriter: HIDReportWriter {
    var reports: [[UInt8]] = []
    var failWhenCountReaches: Int?
    func write(_ report: [UInt8]) throws {
        if let limit = failWhenCountReaches, reports.count >= limit { throw AKP02Error.writeFailed(-1) }
        reports.append(report)
    }
}
```

- [ ] **Step 2: Failing tests für PanelImage** — `Tests/StatusCoreTests/PanelImageTests.swift`

```swift
import XCTest
import CoreGraphics
@testable import StatusCore

final class PanelImageTests: XCTestCase {
    /// Querformat 1920×462, blau, rotes 50×50-Quadrat oben links.
    private func landscapeWithRedCorner() -> CGImage {
        let ctx = PanelImage.makeContext(width: 1920, height: 462)
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 1920, height: 462))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 462 - 50, width: 50, height: 50)) // CG: Ursprung unten links
        return ctx.makeImage()!
    }

    func testRotationIsClockwiseIntoPortrait() {
        let rotated = PanelImage.rotateForPanel(landscapeWithRedCorner())
        XCTAssertEqual(rotated.width, 462)
        XCTAssertEqual(rotated.height, 1920)
        XCTAssertTrue(isRed(pixel(rotated, 440, 10)), "oben links im Querformat → oben rechts im Hochformat")
        XCTAssertTrue(isBlue(pixel(rotated, 10, 10)))
    }

    func testJPEGHasJPEGMagic() {
        let bytes = PanelImage.encode(landscape: landscapeWithRedCorner())
        XCTAssertEqual(Array(bytes.prefix(3)), [0xFF, 0xD8, 0xFF])
        XCTAssertLessThan(bytes.count, 500_000)
    }
}
```

- [ ] **Step 3: Test laufen lassen, muss fehlschlagen**

Run: `swift test --filter PanelImageTests`
Expected: Build-Fehler „cannot find 'PanelImage' in scope“.

- [ ] **Step 4: PanelImage implementieren** — `Sources/StatusCore/Display/PanelImage.swift`

```swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum PanelImage {
    public static func makeContext(width: Int, height: Int) -> CGContext {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    }

    /// Dreht ein 1920×462-Querformatbild 90° im Uhrzeigersinn in den 462×1920-Puffer des Panels.
    public static func rotateForPanel(_ landscape: CGImage) -> CGImage {
        let ctx = makeContext(width: AKP02Protocol.shortSide, height: AKP02Protocol.longSide)
        ctx.translateBy(x: 0, y: CGFloat(AKP02Protocol.longSide))
        ctx.rotate(by: -.pi / 2)
        ctx.draw(landscape, in: CGRect(x: 0, y: 0, width: landscape.width, height: landscape.height))
        return ctx.makeImage()!
    }

    public static func jpeg(_ image: CGImage, quality: Double = 0.85) -> [UInt8] {
        encode(image, type: .jpeg, options: [kCGImageDestinationLossyCompressionQuality: quality])
    }

    public static func png(_ image: CGImage) -> Data {
        Data(encode(image, type: .png, options: [:]))
    }

    public static func encode(landscape: CGImage) -> [UInt8] {
        jpeg(rotateForPanel(landscape))
    }

    private static func encode(_ image: CGImage, type: UTType, options: [CFString: Any]) -> [UInt8] {
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        CGImageDestinationFinalize(dest)
        return [UInt8](data as Data)
    }
}
```

- [ ] **Step 5: Tests laufen lassen**

Run: `swift test --filter PanelImageTests`
Expected: `Executed 2 tests, with 0 failures`.

- [ ] **Step 6: Failing tests für DisplayController** — `Tests/StatusCoreTests/DisplayControllerTests.swift`

```swift
import XCTest
@testable import StatusCore

final class DisplayControllerTests: XCTestCase {
    func testAttachSendsScreenOnAndBrightness() {
        let c = DisplayController(brightness: 42)
        let w = FakeWriter()
        c.attach(w); c.flush()
        XCTAssertEqual(w.reports, [AKP02Protocol.screenOn(), AKP02Protocol.brightness(42)])
    }

    func testShowSendsFullFrame() {
        let c = DisplayController()
        let w = FakeWriter()
        c.attach(w); c.flush()
        w.reports.removeAll()
        c.show(jpeg: [1, 2, 3]); c.flush()
        XCTAssertEqual(w.reports, AKP02Protocol.fullFrameReports(jpeg: [1, 2, 3]))
    }

    func testReattachRestoresBrightnessAndLastFrame() {
        let c = DisplayController(brightness: 60)
        c.show(jpeg: [9, 9]) // noch kein Gerät: wird gemerkt
        c.setBrightness(30)
        let w = FakeWriter()
        c.attach(w); c.flush()
        XCTAssertEqual(w.reports, [AKP02Protocol.screenOn(), AKP02Protocol.brightness(30)]
                       + AKP02Protocol.fullFrameReports(jpeg: [9, 9]))
    }

    func testWriteFailureDisconnectsAndStopsWriting() {
        let c = DisplayController()
        let w = FakeWriter()
        w.failWhenCountReaches = 3
        let disconnected = expectation(description: "getrennt")
        var states: [DisplayController.State] = []
        c.onStateChange = { s in states.append(s); if s == .disconnected { disconnected.fulfill() } }
        c.attach(w)
        c.show(jpeg: [UInt8](repeating: 7, count: 3000)); c.flush()
        wait(for: [disconnected], timeout: 1)
        let count = w.reports.count
        c.show(jpeg: [1]); c.flush()
        XCTAssertEqual(w.reports.count, count, "nach Fehler wird nichts mehr geschrieben")

        let w2 = FakeWriter()
        c.attach(w2); c.flush()
        XCTAssertEqual(Array(w2.reports.prefix(2)), [AKP02Protocol.screenOn(), AKP02Protocol.brightness(60)])
        XCTAssertEqual(Array(w2.reports.dropFirst(2)), AKP02Protocol.fullFrameReports(jpeg: [1]))
    }

    func testHeartbeatWritesConnect() {
        let c = DisplayController()
        let w = FakeWriter()
        c.attach(w); c.flush()
        w.reports.removeAll()
        c.beat(); c.flush()
        XCTAssertEqual(w.reports, [AKP02Protocol.heartbeat()])
    }
}
```

- [ ] **Step 7: Test laufen lassen, muss fehlschlagen**

Run: `swift test --filter DisplayControllerTests`
Expected: Build-Fehler „cannot find 'DisplayController' in scope“.

- [ ] **Step 8: Transport implementieren** — `Sources/StatusCore/Display/AKP02Transport.swift`

```swift
import Foundation
import IOKit.hid

public protocol HIDReportWriter: AnyObject {
    func write(_ report: [UInt8]) throws
}

public enum AKP02Error: Error, Equatable {
    case writeFailed(Int32)
}

final class IOHIDWriter: HIDReportWriter {
    let device: IOHIDDevice
    init(device: IOHIDDevice) { self.device = device }

    func write(_ report: [UInt8]) throws {
        let result = report.withUnsafeBufferPointer { buf in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, buf.baseAddress!, buf.count)
        }
        if result != kIOReturnSuccess { throw AKP02Error.writeFailed(result) }
    }
}

/// Findet das AKP02 über IOHIDManager und meldet An- und Abstecken (Callbacks auf dem Main-Runloop).
public final class AKP02Transport {
    public var onConnect: ((HIDReportWriter) -> Void)?
    public var onDisconnect: (() -> Void)?
    private let manager: IOHIDManager
    private var current: IOHIDDevice?

    public init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Any] = [kIOHIDVendorIDKey: AKP02Protocol.vendorID,
                                    kIOHIDProductIDKey: AKP02Protocol.productID]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
    }

    public func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            Unmanaged<AKP02Transport>.fromOpaque(context!).takeUnretainedValue().attach(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            Unmanaged<AKP02Transport>.fromOpaque(context!).takeUnretainedValue().detach(device)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func attach(_ device: IOHIDDevice) {
        guard current == nil else { return } // dasselbe Gerät meldet sich je Usage
        current = device
        onConnect?(IOHIDWriter(device: device))
    }

    private func detach(_ device: IOHIDDevice) {
        guard let current, CFEqual(current, device) else { return }
        self.current = nil
        onDisconnect?()
    }
}
```

- [ ] **Step 9: DisplayController implementieren** — `Sources/StatusCore/Display/DisplayController.swift`

```swift
import Foundation

/// Serialisiert alles, was ans Panel geht: Init, Helligkeit, Bilder, Heartbeat.
/// Merkt sich Helligkeit und letztes Bild und stellt beides nach jedem (Re-)Connect wieder her.
public final class DisplayController {
    public enum State: Equatable { case disconnected, connected }
    public static let heartbeatInterval: TimeInterval = 5

    /// Wird auf dem Main-Thread aufgerufen.
    public var onStateChange: ((State) -> Void)?

    private let queue = DispatchQueue(label: "status-display.akp02")
    private var writer: HIDReportWriter?
    private var lastFrame: [UInt8]?
    private var brightness: Int
    private var timer: DispatchSourceTimer?

    public init(brightness: Int = 60) { self.brightness = brightness }

    public func attach(_ writer: HIDReportWriter) {
        queue.async {
            self.writer = writer
            self.initializeAndRestore()
            guard self.writer != nil else { return }
            self.startHeartbeat()
            self.publish(.connected)
        }
    }

    public func detach() { queue.async { self.drop() } }

    /// Nach dem Aufwachen: Panel kann Helligkeit und Bild verloren haben.
    public func reinitialize() { queue.async { self.initializeAndRestore() } }

    public func show(jpeg: [UInt8]) {
        queue.async {
            self.lastFrame = jpeg
            self.send(AKP02Protocol.fullFrameReports(jpeg: jpeg))
        }
    }

    public func setBrightness(_ percent: Int) {
        queue.async {
            self.brightness = percent
            self.send([AKP02Protocol.brightness(percent)])
        }
    }

    /// Wartet, bis alle bisher eingereihten Aufträge erledigt sind (für Tests und CLI).
    public func flush() { queue.sync {} }

    func beat() { queue.async { self.send([AKP02Protocol.heartbeat()]) } }

    private func initializeAndRestore() {
        send([AKP02Protocol.screenOn(), AKP02Protocol.brightness(brightness)])
        if let frame = lastFrame { send(AKP02Protocol.fullFrameReports(jpeg: frame)) }
    }

    private func send(_ reports: [[UInt8]]) {
        guard let writer else { return }
        do {
            for report in reports { try writer.write(report) }
        } catch {
            drop()
        }
    }

    private func drop() {
        let wasConnected = writer != nil
        writer = nil
        timer?.cancel()
        timer = nil
        if wasConnected { publish(.disconnected) }
    }

    private func startHeartbeat() {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + Self.heartbeatInterval, repeating: Self.heartbeatInterval)
        t.setEventHandler { [weak self] in self?.send([AKP02Protocol.heartbeat()]) }
        t.resume()
        timer = t
    }

    private func publish(_ state: State) {
        DispatchQueue.main.async { self.onStateChange?(state) }
    }
}
```

- [ ] **Step 10: Tests laufen lassen**

Run: `swift test --filter DisplayControllerTests`
Expected: `Executed 5 tests, with 0 failures`.

- [ ] **Step 11: Unterbefehl `display-test`** — `Sources/StatusDisplay/CLI.swift`

```swift
import CoreGraphics
import Foundation
import StatusCore

enum CLI {
    /// Zeigt 15 s lang vier Farbfelder auf dem Panel. Prüft Gerätezugriff ohne App.
    static func displayTest() -> Int32 {
        let ctx = PanelImage.makeContext(width: 1920, height: 462)
        let colors: [(CGFloat, CGFloat, CGFloat)] = [(0.7, 0.15, 0.24), (0.35, 0.78, 0.47), (0.94, 0.7, 0.24), (0.18, 0.43, 0.71)]
        for (i, c) in colors.enumerated() {
            ctx.setFillColor(CGColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1))
            ctx.fill(CGRect(x: i * 480, y: 0, width: 480, height: 462))
        }
        let jpeg = PanelImage.encode(landscape: ctx.makeImage()!)
        let controller = DisplayController(brightness: 60)
        let transport = AKP02Transport()
        var connected = false
        controller.onStateChange = { state in
            connected = state == .connected
            print(state == .connected ? "Display verbunden" : "Display getrennt")
        }
        transport.onConnect = { controller.attach($0); controller.show(jpeg: jpeg) }
        transport.onDisconnect = { controller.detach() }
        transport.start()
        RunLoop.main.run(until: Date().addingTimeInterval(15))
        if !connected { print("Kein AKP02 gefunden (0300:3017)") }
        return connected ? 0 : 1
    }
}
```

`main.swift` erweitern:

```swift
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "version":
    print("status-display 1.0")
    exit(0)
case "display-test":
    exit(CLI.displayTest())
default:
    StatusDisplayApp.main()
}
```

- [ ] **Step 12: Am Gerät prüfen** (AKP02 angesteckt)

Run: `swift build && .build/debug/StatusDisplay display-test`
Expected: Ausgabe `Display verbunden`, vier Farbfelder (rot, grün, gelb, blau von links) für 15 s, danach nach einigen Sekunden das AJAZZ-Logo. Kommt stattdessen eine macOS-Abfrage „Eingabeüberwachung“, im Abschlussbericht vermerken (Spec: „Geklärte Punkte“ 3). Ist das Gerät nicht angesteckt: `Kein AKP02 gefunden (0300:3017)`, Exit 1.

- [ ] **Step 13: Commit**

```bash
git add Sources Tests
git commit -m "Display: IOKit-Transport, DisplayController mit Heartbeat und Reconnect, display-test"
```

---

### Task 4: Farben, Status-Vorgaben und StatusStore

**Files:**
- Create: `Sources/StatusCore/Support/RGBColor.swift`, `Sources/StatusCore/Status/StatusPreset.swift`, `Sources/StatusCore/Status/StatusStore.swift`
- Test: `Tests/StatusCoreTests/RGBColorTests.swift`, `Tests/StatusCoreTests/StatusStoreTests.swift`

**Interfaces:**
- Consumes: `TimeSource`, `ManualTime` (Task 1)
- Produces:
  - `struct RGBColor: Codable, Equatable { var r, g, b, a: Double; init(r:g:b:a:); init?(hex:); var hex: String; var cgColor: CGColor; func withAlpha(_:) -> RGBColor }`
  - `struct StatusPreset: Codable, Equatable, Identifiable { var id: String; var name: String; var colorHex: String; var color: RGBColor; static let defaults: [StatusPreset]; static let availableID = "available" }`
  - `struct ActiveStatus: Codable, Equatable { var presetID: String; var since: Date; var until: Date? }`
  - `struct AutoStatus: Equatable { var presetID: String; var source: String; var since: Date }`
  - `final class StatusStore { private(set) var presets: [StatusPreset]; private(set) var manual: ActiveStatus; private(set) var automatic: AutoStatus?; init(defaults: UserDefaults = .standard, time: TimeSource = SystemTime(), calendar: Calendar = .current); func set(_ presetID: String, for duration: TimeInterval? = nil); func setUntilEndOfDay(_ presetID: String); func setAutomatic(_ presetID: String?, source: String); func setPresets(_ presets: [StatusPreset]); func effective() -> (preset: StatusPreset, since: Date); func preset(_ id: String) -> StatusPreset? }`

- [ ] **Step 1: Failing tests** — `Tests/StatusCoreTests/RGBColorTests.swift`

```swift
import XCTest
@testable import StatusCore

final class RGBColorTests: XCTestCase {
    func testHexRoundTrip() {
        let c = RGBColor(hex: "#B3263E")!
        XCTAssertEqual(c.hex, "#B3263E")
        XCTAssertEqual(c.r, 0xB3 / 255.0, accuracy: 0.0001)
    }
    func testHexWithoutHashAndInvalid() {
        XCTAssertEqual(RGBColor(hex: "00ff00")?.hex, "#00FF00")
        XCTAssertNil(RGBColor(hex: "#12345"))
        XCTAssertNil(RGBColor(hex: "zzzzzz"))
    }
}
```

`Tests/StatusCoreTests/StatusStoreTests.swift`:

```swift
import XCTest
@testable import StatusCore

final class StatusStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let time = ManualTime()

    override func setUp() {
        defaults = UserDefaults(suiteName: "StatusStoreTests-\(UUID().uuidString)")!
    }

    private func makeStore() -> StatusStore {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return StatusStore(defaults: defaults, time: time, calendar: cal)
    }

    func testStartsAvailable() {
        XCTAssertEqual(makeStore().effective().preset.id, "available")
    }

    func testSetAndPersist() {
        let s = makeStore()
        s.set("deep-focus")
        XCTAssertEqual(makeStore().effective().preset.id, "deep-focus")
        XCTAssertEqual(makeStore().effective().since, time.now)
    }

    func testDurationExpiresToAvailableAcrossRestart() {
        let s = makeStore()
        s.set("in-meeting", for: 3600)
        time.advance(3599)
        XCTAssertEqual(s.effective().preset.id, "in-meeting")
        time.advance(2)
        let reloaded = makeStore()
        let e = reloaded.effective()
        XCTAssertEqual(e.preset.id, "available")
        XCTAssertEqual(e.since, time.now.addingTimeInterval(-1), "seit dem Ablaufzeitpunkt")
    }

    func testUntilEndOfDay() {
        let s = makeStore()
        s.setUntilEndOfDay("deep-focus")
        let until = s.manual.until!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
        XCTAssertEqual(cal.component(.hour, from: until), 0)
        XCTAssertGreaterThan(until, time.now)
        XCTAssertLessThanOrEqual(until.timeIntervalSince(time.now), 86_400)
    }

    func testAutomaticOverridesAndReleases() {
        let s = makeStore()
        s.set("deep-focus")
        time.advance(10)
        s.setAutomatic("in-meeting", source: "teams")
        XCTAssertEqual(s.effective().preset.id, "in-meeting")
        XCTAssertEqual(s.effective().since, time.now)
        s.setAutomatic(nil, source: "teams")
        XCTAssertEqual(s.effective().preset.id, "deep-focus")
    }

    func testUnknownPresetFallsBack() {
        let s = makeStore()
        s.set("gibt-es-nicht")
        XCTAssertEqual(s.effective().preset.id, "available")
        s.setPresets([StatusPreset(id: "x", name: "X", colorHex: "#000000")])
        XCTAssertEqual(s.effective().preset.id, "x", "ohne 'available' gilt die erste Vorgabe")
    }

    func testEmptyPresetListIsRejected() {
        let s = makeStore()
        s.setPresets([])
        XCTAssertEqual(s.presets, StatusPreset.defaults)
    }
}
```

- [ ] **Step 2: Tests laufen lassen, müssen fehlschlagen**

Run: `swift test --filter "RGBColorTests|StatusStoreTests"`
Expected: Build-Fehler „cannot find 'RGBColor' in scope“.

- [ ] **Step 3: RGBColor** — `Sources/StatusCore/Support/RGBColor.swift`

```swift
import CoreGraphics
import Foundation

public struct RGBColor: Codable, Equatable {
    public var r, g, b, a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(r: Double((v >> 16) & 0xFF) / 255, g: Double((v >> 8) & 0xFF) / 255, b: Double(v & 0xFF) / 255)
    }

    public var hex: String {
        String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    public var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }

    public func withAlpha(_ alpha: Double) -> RGBColor { RGBColor(r: r, g: g, b: b, a: alpha) }
}
```

- [ ] **Step 4: StatusPreset** — `Sources/StatusCore/Status/StatusPreset.swift`

```swift
import Foundation

public struct StatusPreset: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var colorHex: String

    public init(id: String, name: String, colorHex: String) {
        self.id = id; self.name = name; self.colorHex = colorHex
    }

    public var color: RGBColor { RGBColor(hex: colorHex) ?? RGBColor(r: 0.35, g: 0.37, b: 0.4) }

    public static let availableID = "available"

    public static let defaults: [StatusPreset] = [
        StatusPreset(id: "deep-focus", name: "Deep Focus", colorHex: "#B3263E"),
        StatusPreset(id: "in-meeting", name: "In Meeting", colorHex: "#6B3FA0"),
        StatusPreset(id: "easy-coding", name: "Easy Coding", colorHex: "#2E8B57"),
        StatusPreset(id: availableID, name: "Verfügbar", colorHex: "#5A5F66"),
        StatusPreset(id: "pause", name: "Pause", colorHex: "#2F6DB5"),
    ]
}

public struct ActiveStatus: Codable, Equatable {
    public var presetID: String
    public var since: Date
    public var until: Date?
}

public struct AutoStatus: Equatable {
    public var presetID: String
    public var source: String
    public var since: Date
}
```

- [ ] **Step 5: StatusStore** — `Sources/StatusCore/Status/StatusStore.swift`

```swift
import Foundation

/// Manueller Status (persistent, optional mit Ablauf) und automatischer Status (Vorrang, flüchtig).
/// Nur vom Main-Thread benutzen.
public final class StatusStore {
    public private(set) var presets: [StatusPreset]
    public private(set) var manual: ActiveStatus
    public private(set) var automatic: AutoStatus?

    private let defaults: UserDefaults
    private let time: TimeSource
    private let calendar: Calendar
    private static let presetsKey = "status.presets"
    private static let manualKey = "status.manual"

    public init(defaults: UserDefaults = .standard, time: TimeSource = SystemTime(), calendar: Calendar = .current) {
        self.defaults = defaults
        self.time = time
        self.calendar = calendar
        presets = Self.decode([StatusPreset].self, defaults.data(forKey: Self.presetsKey)) ?? StatusPreset.defaults
        manual = Self.decode(ActiveStatus.self, defaults.data(forKey: Self.manualKey))
            ?? ActiveStatus(presetID: StatusPreset.availableID, since: time.now, until: nil)
    }

    public func set(_ presetID: String, for duration: TimeInterval? = nil) {
        manual = ActiveStatus(presetID: presetID, since: time.now, until: duration.map { time.now.addingTimeInterval($0) })
        save()
    }

    public func setUntilEndOfDay(_ presetID: String) {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: time.now)!
        manual = ActiveStatus(presetID: presetID, since: time.now, until: calendar.startOfDay(for: tomorrow))
        save()
    }

    public func setAutomatic(_ presetID: String?, source: String) {
        automatic = presetID.map { AutoStatus(presetID: $0, source: source, since: time.now) }
    }

    public func setPresets(_ newPresets: [StatusPreset]) {
        guard !newPresets.isEmpty else { return }
        presets = newPresets
        save()
    }

    public func effective() -> (preset: StatusPreset, since: Date) {
        if let auto = automatic, let p = preset(auto.presetID) { return (p, auto.since) }
        if let until = manual.until, until <= time.now {
            manual = ActiveStatus(presetID: StatusPreset.availableID, since: until, until: nil)
            save()
        }
        let p = preset(manual.presetID) ?? preset(StatusPreset.availableID) ?? presets[0]
        return (p, manual.since)
    }

    public func preset(_ id: String) -> StatusPreset? { presets.first { $0.id == id } }

    private func save() {
        defaults.set(try? JSONEncoder().encode(presets), forKey: Self.presetsKey)
        defaults.set(try? JSONEncoder().encode(manual), forKey: Self.manualKey)
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data?) -> T? {
        data.flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}
```

- [ ] **Step 6: Tests laufen lassen**

Run: `swift test --filter "RGBColorTests|StatusStoreTests"`
Expected: `Executed 9 tests, with 0 failures`.

- [ ] **Step 7: Commit**

```bash
git add Sources Tests
git commit -m "Status: Vorgaben, manueller Status mit Ablauf, automatischer Status mit Vorrang"
```

---

### Task 5: Agenten-Ereignis und AgentRegistry

**Files:**
- Create: `Sources/StatusCore/Agents/AgentEvent.swift`, `Sources/StatusCore/Agents/AgentActivity.swift`, `Sources/StatusCore/Agents/AgentRegistry.swift`
- Test: `Tests/StatusCoreTests/AgentRegistryTests.swift`

**Interfaces:**
- Consumes: `TimeSource`, `ManualTime` (Task 1)
- Produces:
  - `struct AgentEvent: Codable, Equatable { var source, session, state: String; var name, project, detail, url: String?; init(source:session:state:name:project:detail:url:); static let states: [String]; func validate() throws }`
  - `enum AgentEventError: Error, Equatable { case missingField(String), unknownState(String); var message: String }`
  - `enum AgentState: String, Codable { case running, waiting, done, error }`
  - `struct AgentActivity: Equatable, Identifiable { let id, source: String; var name: String; var project: String?; var state: AgentState; var since: Date; var detail: String?; var url: URL?; var lastSeen: Date; var isStale: Bool }`
  - `final class AgentRegistry { static let doneTTL, staleAfter, removeAfter: TimeInterval; init(time: TimeSource); func apply(_ event: AgentEvent) throws; func dismiss(id: String); func snapshot() -> [AgentActivity] }`

- [ ] **Step 1: Failing tests** — `Tests/StatusCoreTests/AgentRegistryTests.swift`

```swift
import XCTest
@testable import StatusCore

final class AgentRegistryTests: XCTestCase {
    private let time = ManualTime()
    private lazy var registry = AgentRegistry(time: time)

    private func event(_ state: String, session: String = "s1", project: String? = "telefon-ai") -> AgentEvent {
        AgentEvent(source: "claude-code", session: session, state: state, name: nil, project: project, detail: nil, url: nil)
    }

    func testValidation() {
        XCTAssertThrowsError(try AgentEvent(source: "", session: "a", state: "running").validate()) {
            XCTAssertEqual($0 as? AgentEventError, .missingField("source"))
        }
        XCTAssertThrowsError(try AgentEvent(source: "x", session: "", state: "running").validate()) {
            XCTAssertEqual($0 as? AgentEventError, .missingField("session"))
        }
        XCTAssertThrowsError(try AgentEvent(source: "x", session: "a", state: "busy").validate()) {
            XCTAssertEqual($0 as? AgentEventError, .unknownState("busy"))
        }
        XCTAssertNoThrow(try AgentEvent(source: "x", session: "a", state: "ended").validate())
    }

    func testRunningEntryUsesProjectAsName() throws {
        try registry.apply(event("running"))
        let a = registry.snapshot()
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(a[0].id, "claude-code:s1")
        XCTAssertEqual(a[0].name, "telefon-ai")
        XCTAssertEqual(a[0].state, .running)
    }

    func testSameStateKeepsSinceButRefreshesLastSeen() throws {
        try registry.apply(event("running"))
        let start = time.now
        time.advance(100)
        try registry.apply(event("running"))
        let a = registry.snapshot()[0]
        XCTAssertEqual(a.since, start)
        XCTAssertEqual(a.lastSeen, time.now)
    }

    func testStateChangeResetsSince() throws {
        try registry.apply(event("running"))
        time.advance(100)
        try registry.apply(event("waiting"))
        XCTAssertEqual(registry.snapshot()[0].since, time.now)
    }

    func testEndedRemoves() throws {
        try registry.apply(event("running"))
        try registry.apply(event("ended"))
        XCTAssertTrue(registry.snapshot().isEmpty)
    }

    func testDoneDisappearsAfterTenMinutes() throws {
        try registry.apply(event("done"))
        time.advance(599)
        XCTAssertEqual(registry.snapshot().count, 1)
        time.advance(2)
        XCTAssertTrue(registry.snapshot().isEmpty)
    }

    func testRunningBecomesStaleThenRemoved() throws {
        try registry.apply(event("running"))
        time.advance(1801)
        XCTAssertTrue(registry.snapshot()[0].isStale)
        time.advance(14_400)
        XCTAssertTrue(registry.snapshot().isEmpty)
    }

    func testWaitingAndErrorStayUntilDismissed() throws {
        try registry.apply(event("waiting", session: "a"))
        try registry.apply(event("error", session: "b"))
        time.advance(100_000)
        let a = registry.snapshot()
        XCTAssertEqual(a.count, 2)
        XCTAssertFalse(a.contains { $0.isStale })
        registry.dismiss(id: "claude-code:a")
        XCTAssertEqual(registry.snapshot().map(\.id), ["claude-code:b"])
    }

    func testSortOrderWaitingErrorRunningStaleDone() throws {
        try registry.apply(event("running", session: "stale"))
        time.advance(1801)
        try registry.apply(event("done", session: "done"))
        try registry.apply(event("running", session: "run"))
        try registry.apply(event("error", session: "err"))
        try registry.apply(event("waiting", session: "wait2"))
        time.advance(1)
        try registry.apply(event("waiting", session: "wait1b"))
        XCTAssertEqual(registry.snapshot().map(\.id).map { $0.replacingOccurrences(of: "claude-code:", with: "") },
                       ["wait2", "wait1b", "err", "run", "stale", "done"])
    }

    func testInvalidEventThrowsAndChangesNothing() {
        XCTAssertThrowsError(try registry.apply(event("busy")))
        XCTAssertTrue(registry.snapshot().isEmpty)
    }
}
```

- [ ] **Step 2: Tests laufen lassen, müssen fehlschlagen**

Run: `swift test --filter AgentRegistryTests`
Expected: Build-Fehler „cannot find 'AgentEvent' in scope“.

- [ ] **Step 3: AgentEvent** — `Sources/StatusCore/Agents/AgentEvent.swift`

```swift
import Foundation

/// Eine Meldung eines Agenten, egal ob per Hook, HTTP oder MCP.
public struct AgentEvent: Codable, Equatable {
    public var source: String
    public var session: String
    public var state: String
    public var name: String?
    public var project: String?
    public var detail: String?
    public var url: String?

    public init(source: String, session: String, state: String, name: String? = nil,
                project: String? = nil, detail: String? = nil, url: String? = nil) {
        self.source = source; self.session = session; self.state = state
        self.name = name; self.project = project; self.detail = detail; self.url = url
    }

    /// `ended` entfernt den Eintrag; alle anderen entsprechen `AgentState`.
    public static let states = ["running", "waiting", "done", "error", "ended"]

    public func validate() throws {
        if source.isEmpty { throw AgentEventError.missingField("source") }
        if session.isEmpty { throw AgentEventError.missingField("session") }
        guard Self.states.contains(state) else { throw AgentEventError.unknownState(state) }
    }
}

public enum AgentEventError: Error, Equatable {
    case missingField(String)
    case unknownState(String)

    public var message: String {
        switch self {
        case .missingField(let f): return "Feld fehlt: \(f)"
        case .unknownState(let s): return "unbekannter Zustand: \(s) (erlaubt: \(AgentEvent.states.joined(separator: ", ")))"
        }
    }
}
```

- [ ] **Step 4: AgentActivity** — `Sources/StatusCore/Agents/AgentActivity.swift`

```swift
import Foundation

public enum AgentState: String, Codable {
    case running, waiting, done, error
}

public struct AgentActivity: Equatable, Identifiable {
    public let id: String
    public let source: String
    public var name: String
    public var project: String?
    public var state: AgentState
    public var since: Date
    public var detail: String?
    public var url: URL?
    public var lastSeen: Date
    /// Nur für `.running`: seit `AgentRegistry.staleAfter` keine Meldung.
    public var isStale: Bool = false

    public init(id: String, source: String, name: String, project: String? = nil, state: AgentState,
                since: Date, detail: String? = nil, url: URL? = nil, lastSeen: Date, isStale: Bool = false) {
        self.id = id; self.source = source; self.name = name; self.project = project; self.state = state
        self.since = since; self.detail = detail; self.url = url; self.lastSeen = lastSeen; self.isStale = isStale
    }
}
```

- [ ] **Step 5: AgentRegistry** — `Sources/StatusCore/Agents/AgentRegistry.swift`

```swift
import Foundation

/// Hält den Zustand aller Agenten. Die Zeitregeln stehen hier, nicht beim Agenten.
/// Nur vom Main-Thread benutzen.
public final class AgentRegistry {
    public static let doneTTL: TimeInterval = 600
    public static let staleAfter: TimeInterval = 1800
    public static let removeAfter: TimeInterval = 14_400

    private let time: TimeSource
    private var items: [String: AgentActivity] = [:]

    public init(time: TimeSource) { self.time = time }

    public func apply(_ event: AgentEvent) throws {
        try event.validate()
        let id = "\(event.source):\(event.session)"
        guard let state = AgentState(rawValue: event.state) else {
            items[id] = nil // "ended"
            return
        }
        let now = time.now
        var item = items[id] ?? AgentActivity(id: id, source: event.source, name: event.source,
                                              state: state, since: now, lastSeen: now)
        if item.state != state { item.since = now }
        item.state = state
        item.lastSeen = now
        item.project = event.project ?? item.project
        item.name = event.name ?? event.project ?? item.project ?? item.name
        item.detail = event.detail
        if let u = event.url { item.url = URL(string: u) }
        items[id] = item
    }

    public func dismiss(id: String) { items[id] = nil }

    public func snapshot() -> [AgentActivity] {
        let now = time.now
        items = items.filter { _, a in
            switch a.state {
            case .done: return now.timeIntervalSince(a.since) <= Self.doneTTL
            case .running: return now.timeIntervalSince(a.lastSeen) <= Self.removeAfter
            case .waiting, .error: return true
            }
        }
        return items.values
            .map { a -> AgentActivity in
                var a = a
                a.isStale = a.state == .running && now.timeIntervalSince(a.lastSeen) > Self.staleAfter
                return a
            }
            .sorted { l, r in
                let (lr, rr) = (rank(l), rank(r))
                return lr != rr ? lr < rr : l.since < r.since
            }
    }

    private func rank(_ a: AgentActivity) -> Int {
        switch a.state {
        case .waiting: return 0
        case .error: return 1
        case .running: return a.isStale ? 3 : 2
        case .done: return 4
        }
    }
}
```

- [ ] **Step 6: Tests laufen lassen**

Run: `swift test --filter AgentRegistryTests`
Expected: `Executed 10 tests, with 0 failures`.

- [ ] **Step 7: Commit**

```bash
git add Sources Tests
git commit -m "Agenten: Ereignis mit Validierung, Registry mit Zeitregeln und Sortierung"
```

---

### Task 6: Renderer und Vorschau

**Files:**
- Create: `Sources/StatusCore/Render/BoardState.swift`, `Sources/StatusCore/Render/BoardText.swift`, `Sources/StatusCore/Render/BoardRenderer.swift`
- Modify: `Sources/StatusDisplay/CLI.swift`, `Sources/StatusDisplay/main.swift`
- Test: `Tests/StatusCoreTests/BoardTextTests.swift`, `Tests/StatusCoreTests/BoardRendererTests.swift`

**Interfaces:**
- Consumes: `RGBColor` (Task 4), `AgentActivity`, `AgentState` (Task 5), `PanelImage` (Task 3)
- Produces:
  - `struct PRZone: Equatable { var toReview, mine, ciFailing: Int; var lastSuccess: Date?; var isStale: Bool; static let unknown: PRZone }`
  - `struct BoardState: Equatable { var statusName: String; var statusColor: RGBColor; var statusSince: Date; var agents: [AgentActivity]; var prs: PRZone; var now: Date }`
  - `enum BoardText { static func since(_:now:) -> String; static func agentLabel(_:now:) -> String; static func truncate(_:max:) -> String; static func visibleAgents(_:maxRows:) -> (rows: [AgentActivity], more: Int); static func statusFontSize(for:width:maxSize:) -> CGFloat; static func clock(_:timeZone:) -> String }`
  - `enum BoardRenderer { static let width = 1920; static let height = 462; static func render(_ state: BoardState) -> CGImage }`

- [ ] **Step 1: Failing tests** — `Tests/StatusCoreTests/BoardTextTests.swift`

```swift
import XCTest
@testable import StatusCore

final class BoardTextTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func agent(_ state: AgentState, stale: Bool = false, since: Date? = nil) -> AgentActivity {
        AgentActivity(id: UUID().uuidString, source: "x", name: "n", state: state,
                      since: since ?? t0, lastSeen: t0, isStale: stale)
    }

    func testSince() {
        XCTAssertEqual(BoardText.since(t0, now: t0.addingTimeInterval(47 * 60 + 30)), "seit 47 min")
        XCTAssertEqual(BoardText.since(t0, now: t0.addingTimeInterval(125 * 60)), "seit 2:05 h")
        XCTAssertEqual(BoardText.since(t0, now: t0.addingTimeInterval(-10)), "seit 0 min")
    }

    func testAgentLabel() {
        let now = t0.addingTimeInterval(4 * 60)
        XCTAssertEqual(BoardText.agentLabel(agent(.running), now: now), "läuft")
        XCTAssertEqual(BoardText.agentLabel(agent(.running, stale: true), now: now), "unklar")
        XCTAssertEqual(BoardText.agentLabel(agent(.waiting), now: now), "wartet 4 min")
        XCTAssertEqual(BoardText.agentLabel(agent(.error), now: now), "Fehler")
        XCTAssertEqual(BoardText.agentLabel(agent(.done), now: now), "fertig")
    }

    func testTruncate() {
        XCTAssertEqual(BoardText.truncate("telefon-ai", max: 20), "telefon-ai")
        XCTAssertEqual(BoardText.truncate("ein-sehr-langer-projektname-x", max: 12), "ein-sehr-la…")
    }

    func testVisibleAgents() {
        let four = (0..<4).map { _ in agent(.running) }
        XCTAssertEqual(BoardText.visibleAgents(four).rows.count, 4)
        XCTAssertEqual(BoardText.visibleAgents(four).more, 0)
        let six = (0..<6).map { _ in agent(.running) }
        XCTAssertEqual(BoardText.visibleAgents(six).rows.count, 3)
        XCTAssertEqual(BoardText.visibleAgents(six).more, 3)
    }

    func testStatusFontShrinksForLongWords() {
        XCTAssertEqual(BoardText.statusFontSize(for: "DEEP", width: 420, maxSize: 92), 92)
        XCTAssertLessThan(BoardText.statusFontSize(for: "VERFÜGBARKEIT", width: 420, maxSize: 92), 60)
    }

    func testClock() {
        XCTAssertEqual(BoardText.clock(t0, timeZone: TimeZone(identifier: "UTC")!), "14:13")
    }
}
```

`Tests/StatusCoreTests/BoardRendererTests.swift`:

```swift
import XCTest
@testable import StatusCore

final class BoardRendererTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func state(prs: PRZone = .unknown, agents: [AgentActivity] = []) -> BoardState {
        BoardState(statusName: "Deep Focus", statusColor: RGBColor(hex: "#FF0000")!, statusSince: t0,
                   agents: agents, prs: prs, now: t0.addingTimeInterval(600))
    }

    func testSizeAndStatusColor() {
        let img = BoardRenderer.render(state())
        XCTAssertEqual(img.width, 1920)
        XCTAssertEqual(img.height, 462)
        XCTAssertTrue(isRed(pixel(img, 5, 5)), "Statuszone in Statusfarbe")
        XCTAssertFalse(isRed(pixel(img, 1000, 5)))
    }

    func testRedBorderWhenOwnCIFails() {
        let failing = PRZone(toReview: 1, mine: 2, ciFailing: 1, lastSuccess: t0, isStale: false)
        XCTAssertTrue(isRed(pixel(BoardRenderer.render(state(prs: failing)), 1246, 230)))
        let fine = PRZone(toReview: 1, mine: 2, ciFailing: 0, lastSuccess: t0, isStale: false)
        XCTAssertFalse(isRed(pixel(BoardRenderer.render(state(prs: fine)), 1246, 230)))
        let stale = PRZone(toReview: 1, mine: 2, ciFailing: 1, lastSuccess: t0, isStale: true)
        XCTAssertFalse(isRed(pixel(BoardRenderer.render(state(prs: stale)), 1246, 230)), "veraltet: kein Alarm")
    }

    func testWaitingAgentGetsHighlightBand() {
        let waiting = AgentActivity(id: "a", source: "x", name: "rundfunk", state: .waiting,
                                    since: t0, lastSeen: t0)
        let img = BoardRenderer.render(state(agents: [waiting]))
        let p = pixel(img, 1210, 110)
        XCTAssertGreaterThan(Int(p.r), Int(p.b) + 20, "gelblicher Hintergrund in der Zeile")
    }
}
```

- [ ] **Step 2: Tests laufen lassen, müssen fehlschlagen**

Run: `swift test --filter "BoardTextTests|BoardRendererTests"`
Expected: Build-Fehler „cannot find 'BoardText' in scope“.

- [ ] **Step 3: BoardState** — `Sources/StatusCore/Render/BoardState.swift`

```swift
import Foundation

public struct PRZone: Equatable {
    public var toReview: Int
    public var mine: Int
    public var ciFailing: Int
    /// Ältester erfolgreicher Abruf über alle Hosts; nil = noch nie.
    public var lastSuccess: Date?
    public var isStale: Bool

    public init(toReview: Int, mine: Int, ciFailing: Int, lastSuccess: Date?, isStale: Bool) {
        self.toReview = toReview; self.mine = mine; self.ciFailing = ciFailing
        self.lastSuccess = lastSuccess; self.isStale = isStale
    }

    public static let unknown = PRZone(toReview: 0, mine: 0, ciFailing: 0, lastSuccess: nil, isStale: true)
}

public struct BoardState: Equatable {
    public var statusName: String
    public var statusColor: RGBColor
    public var statusSince: Date
    public var agents: [AgentActivity]
    public var prs: PRZone
    public var now: Date

    public init(statusName: String, statusColor: RGBColor, statusSince: Date,
                agents: [AgentActivity], prs: PRZone, now: Date) {
        self.statusName = statusName; self.statusColor = statusColor; self.statusSince = statusSince
        self.agents = agents; self.prs = prs; self.now = now
    }
}
```

- [ ] **Step 4: BoardText** — `Sources/StatusCore/Render/BoardText.swift`

```swift
import CoreGraphics
import Foundation

public enum BoardText {
    public static func since(_ start: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(start) / 60))
        return minutes < 60 ? "seit \(minutes) min" : String(format: "seit %d:%02d h", minutes / 60, minutes % 60)
    }

    public static func agentLabel(_ a: AgentActivity, now: Date) -> String {
        if a.isStale { return "unklar" }
        switch a.state {
        case .running: return "läuft"
        case .waiting: return "wartet \(max(0, Int(now.timeIntervalSince(a.since) / 60))) min"
        case .error: return "Fehler"
        case .done: return "fertig"
        }
    }

    public static func truncate(_ s: String, max: Int) -> String {
        s.count <= max ? s : String(s.prefix(max - 1)) + "…"
    }

    /// Höchstens `maxRows` Zeilen; bei Überlauf eine Zeile weniger plus „+N weitere“.
    public static func visibleAgents(_ agents: [AgentActivity], maxRows: Int = 4) -> (rows: [AgentActivity], more: Int) {
        guard agents.count > maxRows else { return (agents, 0) }
        return (Array(agents.prefix(maxRows - 1)), agents.count - (maxRows - 1))
    }

    /// Grobe Breitenschätzung für fette Großbuchstaben (0,68 × Schriftgröße je Zeichen).
    public static func statusFontSize(for word: String, width: CGFloat, maxSize: CGFloat) -> CGFloat {
        let estimated = width / (0.68 * CGFloat(max(word.count, 1)))
        return min(maxSize, estimated.rounded(.down))
    }

    public static func clock(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.timeZone = timeZone
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
```

- [ ] **Step 5: BoardRenderer** — `Sources/StatusCore/Render/BoardRenderer.swift`

```swift
import CoreGraphics
import CoreText
import Foundation

/// Zeichnet das Board als 1920×462-Querformat. Koordinaten von oben links.
public enum BoardRenderer {
    public static let width = 1920
    public static let height = 462

    static let background = RGBColor(hex: "#121216")!
    static let separator = RGBColor(hex: "#2A2A30")!
    static let muted = RGBColor(hex: "#8C8C96")!
    static let white = RGBColor(hex: "#FFFFFF")!
    static let green = RGBColor(hex: "#5AC878")!
    static let amber = RGBColor(hex: "#F0B43C")!
    static let red = RGBColor(hex: "#E5484D")!
    static let grey = RGBColor(hex: "#6B6F76")!

    public static func render(_ s: BoardState) -> CGImage {
        let ctx = PanelImage.makeContext(width: width, height: height)
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        fill(ctx, CGRect(x: 0, y: 0, width: width, height: height), background)
        drawStatus(ctx, s)
        drawAgents(ctx, s)
        drawPRs(ctx, s)
        drawClock(ctx, s)
        for x in [1240, 1660] { fill(ctx, CGRect(x: x - 1, y: 40, width: 2, height: 382), separator) }
        return ctx.makeImage()!
    }

    // MARK: Zonen

    private static func drawStatus(_ ctx: CGContext, _ s: BoardState) {
        fill(ctx, CGRect(x: 0, y: 0, width: 480, height: height), s.statusColor)
        let words = s.statusName.uppercased().split(separator: " ").map(String.init).prefix(2)
        let size = words.map { BoardText.statusFontSize(for: $0, width: 420, maxSize: 92) }.min() ?? 92
        var baseline: CGFloat = words.count > 1 ? 170 : 230
        for w in words {
            text(ctx, w, x: 40, baseline: baseline, size: size, bold: true, color: white)
            baseline += size + 8
        }
        text(ctx, BoardText.since(s.statusSince, now: s.now), x: 40, baseline: 420, size: 38,
             color: white.withAlpha(0.8))
    }

    private static func drawAgents(_ ctx: CGContext, _ s: BoardState) {
        let x0: CGFloat = 520
        text(ctx, "AGENTEN", x: x0, baseline: 70, size: 34, color: muted)
        let (rows, more) = BoardText.visibleAgents(s.agents)
        if rows.isEmpty {
            text(ctx, "keine aktiven Agenten", x: x0, baseline: 170, size: 40, color: muted)
        }
        var baseline: CGFloat = 150
        for a in rows {
            let color = stateColor(a)
            if a.state == .waiting {
                fill(ctx, CGRect(x: 500, y: baseline - 54, width: 730, height: 74), amber.withAlpha(0.22))
            }
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: CGRect(x: x0, y: baseline - 32, width: 26, height: 26))
            // Name bis x≈940, Label ab 960 bis ≈1200: bleibt links der Trennlinie bei 1240.
            text(ctx, BoardText.truncate(a.name, max: 16), x: x0 + 50, baseline: baseline, size: 44,
                 color: a.isStale ? grey : white)
            text(ctx, BoardText.agentLabel(a, now: s.now), x: x0 + 440, baseline: baseline, size: 34, color: color)
            baseline += 80
        }
        if more > 0 {
            text(ctx, "+\(more) weitere", x: x0 + 50, baseline: baseline, size: 36, color: muted)
        }
    }

    private static func drawPRs(_ ctx: CGContext, _ s: BoardState) {
        let x0: CGFloat = 1270
        let z = s.prs
        if z.ciFailing > 0 && !z.isStale {
            ctx.setStrokeColor(red.cgColor)
            ctx.setLineWidth(8)
            ctx.stroke(CGRect(x: 1246, y: 6, width: 408, height: 450))
        }
        text(ctx, "PRs", x: x0, baseline: 70, size: 34, color: muted)
        guard z.lastSuccess != nil else {
            text(ctx, "?", x: x0, baseline: 250, size: 110, bold: true, color: grey)
            return
        }
        let c = z.isStale ? grey : white
        text(ctx, "\(z.toReview)", x: x0, baseline: 170, size: 72, bold: true, color: c)
        text(ctx, "zu reviewen", x: x0 + 110, baseline: 165, size: 36, color: c)
        text(ctx, "\(z.mine)", x: x0, baseline: 270, size: 72, bold: true, color: c)
        text(ctx, "eigene offen", x: x0 + 110, baseline: 265, size: 36, color: c)
        if z.ciFailing > 0 {
            let rc = z.isStale ? grey : red
            text(ctx, "\(z.ciFailing)", x: x0, baseline: 370, size: 72, bold: true, color: rc)
            text(ctx, "CI rot", x: x0 + 110, baseline: 365, size: 36, color: rc)
        }
        if z.isStale, let t = z.lastSuccess {
            text(ctx, "Stand \(BoardText.clock(t))", x: x0, baseline: 435, size: 30, color: grey)
        }
    }

    private static func drawClock(_ ctx: CGContext, _ s: BoardState) {
        text(ctx, BoardText.clock(s.now), x: 1685, baseline: 260, size: 72, bold: true, color: white)
    }

    // MARK: Hilfen

    private static func stateColor(_ a: AgentActivity) -> RGBColor {
        if a.isStale { return grey }
        switch a.state {
        case .running: return green
        case .waiting: return amber
        case .error: return red
        case .done: return grey
        }
    }

    private static func fill(_ ctx: CGContext, _ rect: CGRect, _ color: RGBColor) {
        ctx.setFillColor(color.cgColor)
        ctx.fill(rect)
    }

    private static func text(_ ctx: CGContext, _ string: String, x: CGFloat, baseline: CGFloat,
                             size: CGFloat, bold: Bool = false, color: RGBColor) {
        let font = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)!
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1) // Kontext ist gespiegelt
        ctx.textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}
```

- [ ] **Step 6: Tests laufen lassen**

Run: `swift test --filter "BoardTextTests|BoardRendererTests"`
Expected: `Executed 9 tests, with 0 failures`.

- [ ] **Step 7: Unterbefehl `preview`** — in `Sources/StatusDisplay/CLI.swift` ergänzen

```swift
extension CLI {
    /// Schreibt ein Beispiel-Board als PNG (Querformat) zur Sichtprüfung.
    static func preview(_ path: String?) -> Int32 {
        guard let path else { print("Aufruf: StatusDisplay preview <datei.png>"); return 2 }
        let now = Date()
        let agents = [
            AgentActivity(id: "1", source: "claude-code", name: "rundfunk", state: .waiting,
                          since: now.addingTimeInterval(-240), lastSeen: now),
            AgentActivity(id: "2", source: "claude-code", name: "telefon-ai", state: .running,
                          since: now.addingTimeInterval(-900), lastSeen: now),
            AgentActivity(id: "3", source: "codex", name: "heim-agent", state: .done,
                          since: now.addingTimeInterval(-60), lastSeen: now),
        ]
        let state = BoardState(statusName: "Deep Focus", statusColor: RGBColor(hex: "#B3263E")!,
                               statusSince: now.addingTimeInterval(-47 * 60), agents: agents,
                               prs: PRZone(toReview: 3, mine: 2, ciFailing: 1, lastSuccess: now, isStale: false),
                               now: now)
        do {
            try PanelImage.png(BoardRenderer.render(state)).write(to: URL(fileURLWithPath: path))
            print(path)
            return 0
        } catch {
            print("Schreiben fehlgeschlagen: \(error)")
            return 1
        }
    }
}
```

In `main.swift` vor `default:` ergänzen:

```swift
case "preview":
    exit(CLI.preview(arguments.dropFirst().first))
```

- [ ] **Step 8: Sichtprüfung**

Run: `swift build && .build/debug/StatusDisplay preview /tmp/board.png && open /tmp/board.png`
Expected: Board mit roter Statuszone „DEEP FOCUS / seit 47 min“, drei Agentenzeilen (rundfunk gelb hinterlegt „wartet 4 min“), PR-Zone mit rotem Rand und „3 zu reviewen / 2 eigene offen / 1 CI rot“, Uhrzeit rechts. Nichts überlappt, nichts ragt über Zonengrenzen.

- [ ] **Step 9: Commit**

```bash
git add Sources Tests
git commit -m "Renderer: Board 1920×462 mit vier Zonen, Textfunktionen, preview-Befehl"
```

---

### Task 7: HTTP-Server, Token und Ingress-Router

**Files:**
- Create: `Sources/StatusCore/Support/Locked.swift`, `Sources/StatusCore/Support/AppSupport.swift`, `Sources/StatusCore/Server/HTTPMessage.swift`, `Sources/StatusCore/Server/HTTPServer.swift`, `Sources/StatusCore/Server/IngressRouter.swift`
- Test: `Tests/StatusCoreTests/HTTPParserTests.swift`, `Tests/StatusCoreTests/IngressRouterTests.swift`, `Tests/StatusCoreTests/HTTPServerTests.swift`, `Tests/StatusCoreTests/AppSupportTests.swift`

**Interfaces:**
- Consumes: `AgentEvent`, `AgentEventError` (Task 5)
- Produces:
  - `final class Locked<Value> { init(_:); var value: Value { get set }; func mutate(_ body: (inout Value) -> Void) }`
  - `struct Endpoint: Codable, Equatable { var port: UInt16 }`
  - `struct AppSupport { let directory: URL; init(directory: URL = …); var tokenURL: URL; var endpointURL: URL; func loadOrCreateToken() throws -> String; func regenerateToken() throws -> String; func readToken() -> String?; func writeEndpoint(_:) throws; func readEndpoint() -> Endpoint? }`
  - `struct HTTPRequest: Equatable { var method, path: String; var headers: [String: String]; var body: Data }` (Header-Schlüssel klein)
  - `struct HTTPResponse: Equatable { var status: Int; var headers: [String: String]; var body: Data; static func json(_:_:) -> HTTPResponse; func serialized() -> Data }`
  - `enum HTTPParser { enum Result: Equatable { case complete(HTTPRequest), incomplete, invalid }; static func parse(_ data: Data) -> Result }`
  - `final class HTTPServer { enum State: Equatable { case stopped, ready, failed(String) }; var onStateChange: ((State) -> Void)?; init(port: UInt16, handler: @escaping (HTTPRequest) -> HTTPResponse); func start() throws; func stop() }`
  - `final class IngressRouter { init(token: String, knownPresets: Locked<Set<String>>, mcp: ((HTTPRequest) -> HTTPResponse)? = nil, onEvent: @escaping (AgentEvent) -> Void, onStatus: @escaping (String, TimeInterval?) -> Void); func handle(_ request: HTTPRequest) -> HTTPResponse }`

- [ ] **Step 1: Failing tests** — `Tests/StatusCoreTests/HTTPParserTests.swift`

```swift
import XCTest
@testable import StatusCore

final class HTTPParserTests: XCTestCase {
    private func raw(_ s: String) -> Data { Data(s.utf8) }

    func testCompleteRequest() {
        let r = HTTPParser.parse(raw("POST /v1/events?x=1 HTTP/1.1\r\nHost: a\r\nContent-Length: 2\r\nAuthorization: Bearer t\r\n\r\n{}"))
        guard case .complete(let req) = r else { return XCTFail("\(r)") }
        XCTAssertEqual(req.method, "POST")
        XCTAssertEqual(req.path, "/v1/events")
        XCTAssertEqual(req.headers["authorization"], "Bearer t")
        XCTAssertEqual(req.body, raw("{}"))
    }

    func testIncompleteHeaderAndBody() {
        XCTAssertEqual(HTTPParser.parse(raw("POST / HTTP/1.1\r\nContent-Le")), .incomplete)
        XCTAssertEqual(HTTPParser.parse(raw("POST / HTTP/1.1\r\nContent-Length: 5\r\n\r\n{}")), .incomplete)
    }

    func testInvalid() {
        XCTAssertEqual(HTTPParser.parse(raw("GARBAGE\r\n\r\n")), .invalid)
        XCTAssertEqual(HTTPParser.parse(raw("POST / HTTP/1.1\r\nContent-Length: 99999999\r\n\r\n")), .invalid)
        XCTAssertEqual(HTTPParser.parse(Data(repeating: 65, count: 20_000)), .invalid)
    }

    func testResponseSerialization() {
        let s = String(decoding: HTTPResponse.json(202, ["ok": true]).serialized(), as: UTF8.self)
        XCTAssertTrue(s.hasPrefix("HTTP/1.1 202 Accepted\r\n"))
        XCTAssertTrue(s.contains("Content-Length: 11\r\n"))
        XCTAssertTrue(s.contains("Connection: close\r\n"))
        XCTAssertTrue(s.hasSuffix("\r\n\r\n{\"ok\":true}"))
    }
}
```

`Tests/StatusCoreTests/IngressRouterTests.swift`:

```swift
import XCTest
@testable import StatusCore

final class IngressRouterTests: XCTestCase {
    private var events: [AgentEvent] = []
    private var statuses: [(String, TimeInterval?)] = []

    private func router(mcp: ((HTTPRequest) -> HTTPResponse)? = nil) -> IngressRouter {
        IngressRouter(token: "geheim", knownPresets: Locked(["deep-focus", "available"]), mcp: mcp,
                      onEvent: { self.events.append($0) }, onStatus: { self.statuses.append(($0, $1)) })
    }

    private func req(_ method: String, _ path: String, body: String = "", token: String? = "geheim") -> HTTPRequest {
        var h: [String: String] = [:]
        if let token { h["authorization"] = "Bearer \(token)" }
        return HTTPRequest(method: method, path: path, headers: h, body: Data(body.utf8))
    }

    func testHealthNeedsNoToken() {
        XCTAssertEqual(router().handle(req("GET", "/v1/health", token: nil)).status, 200)
    }

    func testMissingOrWrongTokenIs401() {
        XCTAssertEqual(router().handle(req("POST", "/v1/events", body: "{}", token: nil)).status, 401)
        XCTAssertEqual(router().handle(req("POST", "/v1/events", body: "{}", token: "falsch")).status, 401)
        XCTAssertTrue(events.isEmpty)
    }

    func testValidEventIsDelivered() {
        let r = router().handle(req("POST", "/v1/events",
            body: #"{"source":"claude-code","session":"s1","state":"running","project":"telefon-ai"}"#))
        XCTAssertEqual(r.status, 202)
        XCTAssertEqual(events, [AgentEvent(source: "claude-code", session: "s1", state: "running", project: "telefon-ai")])
    }

    func testBrokenJSONAndInvalidStateAre400() {
        XCTAssertEqual(router().handle(req("POST", "/v1/events", body: "{kaputt")).status, 400)
        let r = router().handle(req("POST", "/v1/events", body: #"{"source":"a","session":"b","state":"busy"}"#))
        XCTAssertEqual(r.status, 400)
        XCTAssertTrue(String(decoding: r.body, as: UTF8.self).contains("unbekannter Zustand"))
        XCTAssertTrue(events.isEmpty)
    }

    func testStatusKnownAndUnknown() {
        XCTAssertEqual(router().handle(req("POST", "/v1/status", body: #"{"preset":"deep-focus","minutes":30}"#)).status, 202)
        XCTAssertEqual(statuses.first?.0, "deep-focus")
        XCTAssertEqual(statuses.first?.1, 1800)
        XCTAssertEqual(router().handle(req("POST", "/v1/status", body: #"{"preset":"nix"}"#)).status, 400)
        XCTAssertEqual(statuses.count, 1)
    }

    func testMCPIsForwardedOnlyWithToken() {
        let r = router(mcp: { _ in HTTPResponse(status: 299) })
        XCTAssertEqual(r.handle(req("POST", "/mcp", body: "{}")).status, 299)
        XCTAssertEqual(r.handle(req("POST", "/mcp", body: "{}", token: nil)).status, 401)
        XCTAssertEqual(router().handle(req("POST", "/mcp", body: "{}")).status, 404)
    }

    func testUnknownPathIs404() {
        XCTAssertEqual(router().handle(req("GET", "/etc/passwd")).status, 404)
    }
}
```

`Tests/StatusCoreTests/AppSupportTests.swift`:

```swift
import XCTest
@testable import StatusCore

final class AppSupportTests: XCTestCase {
    private func temp() -> AppSupport {
        AppSupport(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    func testTokenIsCreatedOnceWithPrivatePermissions() throws {
        let s = temp()
        let t1 = try s.loadOrCreateToken()
        XCTAssertEqual(t1.count, 64)
        XCTAssertEqual(try s.loadOrCreateToken(), t1)
        XCTAssertEqual(s.readToken(), t1)
        let perms = try FileManager.default.attributesOfItem(atPath: s.tokenURL.path)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600)
        let dirPerms = try FileManager.default.attributesOfItem(atPath: s.directory.path)[.posixPermissions] as? Int
        XCTAssertEqual(dirPerms, 0o700)
    }

    func testRegenerateChangesToken() throws {
        let s = temp()
        let t1 = try s.loadOrCreateToken()
        XCTAssertNotEqual(try s.regenerateToken(), t1)
    }

    func testEndpointRoundTrip() throws {
        let s = temp()
        XCTAssertNil(s.readEndpoint())
        try s.writeEndpoint(Endpoint(port: 47615))
        XCTAssertEqual(s.readEndpoint(), Endpoint(port: 47615))
    }
}
```

`Tests/StatusCoreTests/HTTPServerTests.swift`:

```swift
import XCTest
@testable import StatusCore

final class HTTPServerTests: XCTestCase {
    func testServesOnLoopback() throws {
        let port = UInt16.random(in: 50_000...59_000)
        let server = HTTPServer(port: port) { req in .json(200, ["path": req.path]) }
        let ready = expectation(description: "bereit")
        server.onStateChange = { if $0 == .ready { ready.fulfill() } }
        try server.start()
        wait(for: [ready], timeout: 3)
        defer { server.stop() }

        let done = expectation(description: "Antwort")
        var body = ""
        URLSession.shared.dataTask(with: URL(string: "http://127.0.0.1:\(port)/v1/health")!) { data, _, _ in
            body = String(decoding: data ?? Data(), as: UTF8.self)
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 3)
        XCTAssertEqual(body, #"{"path":"\/v1\/health"}"#)
    }
}
```

- [ ] **Step 2: Tests laufen lassen, müssen fehlschlagen**

Run: `swift test --filter "HTTPParserTests|IngressRouterTests|AppSupportTests|HTTPServerTests"`
Expected: Build-Fehler „cannot find 'HTTPParser' in scope“.

- [ ] **Step 3: Locked** — `Sources/StatusCore/Support/Locked.swift`

```swift
import Foundation

/// Kleiner threadsicherer Wert für Daten, die Server-Queue und Main-Thread teilen.
public final class Locked<Value> {
    private var stored: Value
    private let lock = NSLock()
    public init(_ value: Value) { stored = value }
    public var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
    public func mutate(_ body: (inout Value) -> Void) { lock.withLock { body(&stored) } }
}
```

- [ ] **Step 4: AppSupport** — `Sources/StatusCore/Support/AppSupport.swift`

```swift
import Foundation
import Security

public struct Endpoint: Codable, Equatable {
    public var port: UInt16
    public init(port: UInt16) { self.port = port }
}

/// Token und Port in ~/Library/Application Support/status-display, gelesen von App und Hook-Befehl.
public struct AppSupport {
    public let directory: URL

    public init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/status-display")) {
        self.directory = directory
    }

    public var tokenURL: URL { directory.appendingPathComponent("token") }
    public var endpointURL: URL { directory.appendingPathComponent("endpoint.json") }

    public func loadOrCreateToken() throws -> String {
        if let t = readToken() { return t }
        return try regenerateToken()
    }

    public func regenerateToken() throws -> String {
        try ensureDirectory()
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw CocoaError(.fileWriteUnknown)
        }
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        try Data(token.utf8).write(to: tokenURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenURL.path)
        return token
    }

    public func readToken() -> String? {
        guard let data = try? Data(contentsOf: tokenURL) else { return nil }
        let t = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    public func writeEndpoint(_ endpoint: Endpoint) throws {
        try ensureDirectory()
        try JSONEncoder().encode(endpoint).write(to: endpointURL, options: .atomic)
    }

    public func readEndpoint() -> Endpoint? {
        (try? Data(contentsOf: endpointURL)).flatMap { try? JSONDecoder().decode(Endpoint.self, from: $0) }
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }
}
```

- [ ] **Step 5: HTTPMessage** — `Sources/StatusCore/Server/HTTPMessage.swift`

```swift
import Foundation

public struct HTTPRequest: Equatable {
    public var method: String
    public var path: String
    /// Schlüssel in Kleinbuchstaben.
    public var headers: [String: String]
    public var body: Data

    public init(method: String, path: String, headers: [String: String] = [:], body: Data = Data()) {
        self.method = method; self.path = path; self.headers = headers; self.body = body
    }
}

public struct HTTPResponse: Equatable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status; self.headers = headers; self.body = body
    }

    public static func json(_ status: Int, _ object: Any) -> HTTPResponse {
        let body = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return HTTPResponse(status: status, headers: ["Content-Type": "application/json"], body: body)
    }

    public func serialized() -> Data {
        var head = "HTTP/1.1 \(status) \(Self.reason(status))\r\n"
        for (k, v) in headers.sorted(by: { $0.key < $1.key }) { head += "\(k): \(v)\r\n" }
        head += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }

    static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 202: return "Accepted"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        default: return "Status"
        }
    }
}

public enum HTTPParser {
    public static let maxHeaderBytes = 16_384
    public static let maxBodyBytes = 1_048_576

    public enum Result: Equatable {
        case complete(HTTPRequest)
        case incomplete
        case invalid
    }

    public static func parse(_ data: Data) -> Result {
        guard let separator = data.range(of: Data("\r\n\r\n".utf8)) else {
            return data.count > maxHeaderBytes ? .invalid : .incomplete
        }
        guard let head = String(data: data[data.startIndex..<separator.lowerBound], encoding: .utf8) else { return .invalid }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/") else { return .invalid }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { return .invalid }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard let length = Int(headers["content-length"] ?? "0"), length >= 0, length <= maxBodyBytes else {
            return .invalid
        }
        let bodyStart = separator.upperBound
        guard data.endIndex - bodyStart >= length else { return .incomplete }
        let path = String(requestLine[1]).components(separatedBy: "?")[0]
        return .complete(HTTPRequest(method: String(requestLine[0]), path: path, headers: headers,
                                     body: Data(data[bodyStart..<bodyStart + length])))
    }
}
```

- [ ] **Step 6: HTTPServer** — `Sources/StatusCore/Server/HTTPServer.swift`

```swift
import Foundation
import Network

/// Minimaler HTTP/1.1-Server nur auf 127.0.0.1, eine Anfrage pro Verbindung.
public final class HTTPServer {
    public enum State: Equatable { case stopped, ready, failed(String) }

    public var onStateChange: ((State) -> Void)?
    private let port: UInt16
    private let handler: (HTTPRequest) -> HTTPResponse
    private let queue = DispatchQueue(label: "status-display.http")
    private var listener: NWListener?

    public init(port: UInt16, handler: @escaping (HTTPRequest) -> HTTPResponse) {
        self.port = port
        self.handler = handler
    }

    public func start() throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!)
        params.allowLocalEndpointReuse = true
        let l = try NWListener(using: params)
        l.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.onStateChange?(.ready)
            case .failed(let error): self?.onStateChange?(.failed("Port \(self?.port ?? 0): \(error)"))
            default: break
            }
        }
        l.newConnectionHandler = { [weak self] c in self?.serve(c) }
        l.start(queue: queue)
        listener = l
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        onStateChange?(.stopped)
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ c: NWConnection, buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { c.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }
            switch HTTPParser.parse(buffer) {
            case .complete(let request): self.respond(c, self.handler(request))
            case .invalid: self.respond(c, .json(400, ["error": "ungültige Anfrage"]))
            case .incomplete:
                if isComplete || error != nil { c.cancel() } else { self.receive(c, buffer: buffer) }
            }
        }
    }

    private func respond(_ c: NWConnection, _ response: HTTPResponse) {
        c.send(content: response.serialized(), completion: .contentProcessed { _ in c.cancel() })
    }
}
```

- [ ] **Step 7: IngressRouter** — `Sources/StatusCore/Server/IngressRouter.swift`

```swift
import Foundation

/// Prüft Token, validiert und reicht weiter. Läuft auf der Server-Queue;
/// `onEvent`/`onStatus` müssen selbst auf den Main-Thread wechseln.
public final class IngressRouter {
    private let token: String
    private let knownPresets: Locked<Set<String>>
    private let mcp: ((HTTPRequest) -> HTTPResponse)?
    private let onEvent: (AgentEvent) -> Void
    private let onStatus: (String, TimeInterval?) -> Void

    public init(token: String, knownPresets: Locked<Set<String>>, mcp: ((HTTPRequest) -> HTTPResponse)? = nil,
                onEvent: @escaping (AgentEvent) -> Void, onStatus: @escaping (String, TimeInterval?) -> Void) {
        self.token = token; self.knownPresets = knownPresets; self.mcp = mcp
        self.onEvent = onEvent; self.onStatus = onStatus
    }

    public func handle(_ request: HTTPRequest) -> HTTPResponse {
        if request.method == "GET" && request.path == "/v1/health" { return .json(200, ["ok": true]) }
        guard authorized(request) else { return .json(401, ["error": "Token fehlt oder falsch"]) }
        switch (request.method, request.path) {
        case ("POST", "/v1/events"):
            do {
                let event = try JSONDecoder().decode(AgentEvent.self, from: request.body)
                try event.validate()
                onEvent(event)
                return .json(202, ["ok": true])
            } catch let error as AgentEventError {
                return .json(400, ["error": error.message])
            } catch {
                return .json(400, ["error": "ungültiges JSON"])
            }
        case ("POST", "/v1/status"):
            struct Body: Decodable { let preset: String; let minutes: Double? }
            guard let body = try? JSONDecoder().decode(Body.self, from: request.body) else {
                return .json(400, ["error": "ungültiges JSON"])
            }
            guard knownPresets.value.contains(body.preset) else {
                return .json(400, ["error": "unbekannter Status: \(body.preset)"])
            }
            onStatus(body.preset, body.minutes.map { $0 * 60 })
            return .json(202, ["ok": true])
        case (_, "/mcp"):
            guard let mcp else { return .json(404, ["error": "nicht gefunden"]) }
            return mcp(request)
        default:
            return .json(404, ["error": "nicht gefunden"])
        }
    }

    private func authorized(_ request: HTTPRequest) -> Bool {
        guard let header = request.headers["authorization"] else { return false }
        return constantTimeEquals(header, "Bearer \(token)")
    }
}

func constantTimeEquals(_ a: String, _ b: String) -> Bool {
    let x = Array(a.utf8), y = Array(b.utf8)
    guard x.count == y.count else { return false }
    var diff: UInt8 = 0
    for i in x.indices { diff |= x[i] ^ y[i] }
    return diff == 0
}
```

- [ ] **Step 8: Tests laufen lassen**

Run: `swift test --filter "HTTPParserTests|IngressRouterTests|AppSupportTests|HTTPServerTests"`
Expected: `Executed 15 tests, with 0 failures`. Die erwartete JSON-Zeichenkette in `testServesOnLoopback` hängt davon ab, ob `JSONSerialization` `/` escaped; weicht sie ab, den Test auf `XCTAssertTrue(body.contains("v1"))` lockern, nicht die Implementierung ändern.

- [ ] **Step 9: Commit**

```bash
git add Sources Tests
git commit -m "Ingress: HTTP-Server auf 127.0.0.1, Token in Application Support, Router für /v1"
```

---

### Task 8: MCP-Endpunkt

**Files:**
- Create: `Sources/StatusCore/Server/MCPHandler.swift`
- Test: `Tests/StatusCoreTests/MCPHandlerTests.swift`

**Interfaces:**
- Consumes: `HTTPRequest`, `HTTPResponse`, `Locked` (Task 7), `AgentEvent` (Task 5)
- Produces: `final class MCPHandler { static let toolName = "report_status"; init(onEvent: @escaping (AgentEvent) -> Void); func handle(_ request: HTTPRequest) -> HTTPResponse }` — wird als `mcp: handler.handle` an `IngressRouter` übergeben.

- [ ] **Step 1: Failing tests** — `Tests/StatusCoreTests/MCPHandlerTests.swift`

```swift
import XCTest
@testable import StatusCore

final class MCPHandlerTests: XCTestCase {
    private var events: [AgentEvent] = []
    private lazy var handler = MCPHandler { self.events.append($0) }

    private func call(_ json: String, session: String? = nil) -> (HTTPResponse, [String: Any]) {
        var headers: [String: String] = [:]
        if let session { headers["mcp-session-id"] = session }
        let r = handler.handle(HTTPRequest(method: "POST", path: "/mcp", headers: headers, body: Data(json.utf8)))
        let obj = (try? JSONSerialization.jsonObject(with: r.body)) as? [String: Any] ?? [:]
        return (r, obj)
    }

    private func initialize() -> String {
        let (r, obj) = call(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","clientInfo":{"name":"copilot"}}}"#)
        XCTAssertEqual(r.status, 200)
        let result = obj["result"] as? [String: Any]
        XCTAssertEqual(result?["protocolVersion"] as? String, "2025-06-18")
        XCTAssertNotNil((result?["capabilities"] as? [String: Any])?["tools"])
        return r.headers["Mcp-Session-Id"]!
    }

    func testInitializeReturnsSessionID() {
        XCTAssertFalse(initialize().isEmpty)
    }

    func testNotificationIs202() {
        XCTAssertEqual(call(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#).0.status, 202)
    }

    func testToolsList() {
        let (_, obj) = call(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        let tools = (obj["result"] as? [String: Any])?["tools"] as? [[String: Any]]
        XCTAssertEqual(tools?.first?["name"] as? String, "report_status")
    }

    func testReportStatusCreatesEventWithClientAndSession() {
        let sid = initialize()
        let (_, obj) = call(#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"report_status","arguments":{"state":"waiting","name":"mise-en-place","detail":"Frage zur Migration"}}}"#, session: sid)
        XCTAssertNil((obj["result"] as? [String: Any])?["isError"])
        XCTAssertEqual(events, [AgentEvent(source: "mcp:copilot", session: sid, state: "waiting",
                                           name: "mise-en-place", detail: "Frage zur Migration")])
    }

    func testInvalidStateIsToolErrorNotCrash() {
        let (r, obj) = call(#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"report_status","arguments":{"state":"busy","name":"x"}}}"#)
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual((obj["result"] as? [String: Any])?["isError"] as? Bool, true)
        XCTAssertTrue(events.isEmpty)
    }

    func testWithoutSessionFallsBackToName() {
        _ = call(#"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"report_status","arguments":{"state":"running","name":"heim-agent"}}}"#)
        XCTAssertEqual(events.first?.session, "heim-agent")
        XCTAssertEqual(events.first?.source, "mcp:mcp")
    }

    func testUnknownMethodAndGarbage() {
        let (_, obj) = call(#"{"jsonrpc":"2.0","id":6,"method":"resources/list"}"#)
        XCTAssertEqual((obj["error"] as? [String: Any])?["code"] as? Int, -32601)
        let (_, bad) = call("{kaputt")
        XCTAssertEqual((bad["error"] as? [String: Any])?["code"] as? Int, -32700)
        let get = handler.handle(HTTPRequest(method: "GET", path: "/mcp"))
        XCTAssertEqual(get.status, 405)
    }
}
```

- [ ] **Step 2: Tests laufen lassen, müssen fehlschlagen**

Run: `swift test --filter MCPHandlerTests`
Expected: Build-Fehler „cannot find 'MCPHandler' in scope“.

- [ ] **Step 3: Implementieren** — `Sources/StatusCore/Server/MCPHandler.swift`

```swift
import Foundation

/// MCP über Streamable HTTP, nur JSON-Antworten (kein SSE). Ein Tool: report_status.
public final class MCPHandler {
    public static let toolName = "report_status"

    static let instructions = """
    Melde deinen Arbeitszustand mit report_status: state=running, wenn du mit einer Aufgabe \
    beginnst; waiting, wenn du auf eine Antwort oder Freigabe des Menschen wartest; done, wenn \
    die Aufgabe fertig ist; error bei Abbruch; ended, wenn die Sitzung endet. name ist ein \
    kurzer Projektname.
    """

    static let toolDefinition: [String: Any] = [
        "name": toolName,
        "description": "Meldet den eigenen Arbeitszustand an das Status-Display auf dem Schreibtisch.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "state": ["type": "string", "enum": AgentEvent.states,
                          "description": "running | waiting (auf den Menschen) | done | error | ended"],
                "name": ["type": "string", "description": "kurzer Projektname"],
                "project": ["type": "string"],
                "detail": ["type": "string", "description": "eine Zeile, z. B. worauf du wartest"],
                "url": ["type": "string", "description": "Link zum PR, Issue oder zur Sitzung"],
            ],
            "required": ["state", "name"],
        ] as [String: Any],
    ]

    private let onEvent: (AgentEvent) -> Void
    private let clients = Locked<[String: String]>([:])

    public init(onEvent: @escaping (AgentEvent) -> Void) { self.onEvent = onEvent }

    public func handle(_ request: HTTPRequest) -> HTTPResponse {
        guard request.method == "POST" else { return .json(405, ["error": "nur POST"]) }
        guard let message = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any],
              let method = message["method"] as? String else {
            return rpcError(id: NSNull(), code: -32700, "parse error")
        }
        guard let id = message["id"] else { return HTTPResponse(status: 202) } // Notification
        let params = message["params"] as? [String: Any] ?? [:]
        let session = request.headers["mcp-session-id"]

        switch method {
        case "initialize":
            let sessionID = UUID().uuidString
            let client = (params["clientInfo"] as? [String: Any])?["name"] as? String ?? "mcp"
            clients.mutate { $0[sessionID] = client }
            var response = rpcResult(id: id, [
                "protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "status-display", "version": "1.0"],
                "instructions": Self.instructions,
            ])
            response.headers["Mcp-Session-Id"] = sessionID
            return response
        case "ping":
            return rpcResult(id: id, [:])
        case "tools/list":
            return rpcResult(id: id, ["tools": [Self.toolDefinition]])
        case "tools/call":
            guard params["name"] as? String == Self.toolName else {
                return rpcError(id: id, code: -32602, "unbekanntes Tool")
            }
            let args = params["arguments"] as? [String: Any] ?? [:]
            let name = args["name"] as? String ?? ""
            let client = session.flatMap { s in clients.value[s] } ?? "mcp"
            let event = AgentEvent(source: "mcp:\(client)", session: session ?? name,
                                   state: args["state"] as? String ?? "",
                                   name: name.isEmpty ? nil : name, project: args["project"] as? String,
                                   detail: args["detail"] as? String, url: args["url"] as? String)
            do {
                try event.validate()
                onEvent(event)
                return rpcResult(id: id, ["content": [["type": "text", "text": "ok"]]])
            } catch {
                let text = (error as? AgentEventError)?.message ?? "\(error)"
                return rpcResult(id: id, ["content": [["type": "text", "text": text]], "isError": true])
            }
        default:
            return rpcError(id: id, code: -32601, "method not found: \(method)")
        }
    }

    private func rpcResult(id: Any, _ result: [String: Any]) -> HTTPResponse {
        .json(200, ["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func rpcError(id: Any, code: Int, _ message: String) -> HTTPResponse {
        .json(200, ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
    }
}
```

- [ ] **Step 4: Tests laufen lassen**

Run: `swift test --filter MCPHandlerTests`
Expected: `Executed 7 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "MCP: Streamable-HTTP-Endpunkt mit Tool report_status"
```

---

### Task 9: Hook-Anbindung für Claude Code und Codex

**Files:**
- Create: `Sources/StatusCore/Agents/HookEventMapper.swift`, `Sources/StatusCore/Agents/EventSender.swift`, `Sources/StatusCore/Agents/HookSnippets.swift`
- Modify: `Sources/StatusDisplay/CLI.swift`, `Sources/StatusDisplay/main.swift`
- Test: `Tests/StatusCoreTests/HookEventMapperTests.swift`, `Tests/StatusCoreTests/EventSenderTests.swift`, `Tests/StatusCoreTests/HookSnippetsTests.swift`

**Interfaces:**
- Consumes: `AgentEvent` (Task 5), `AppSupport`, `Endpoint`, `HTTPServer`, `IngressRouter`, `Locked` (Task 7)
- Produces:
  - `enum HookEventMapper { static func event(source: String, payload: Data) throws -> AgentEvent? }`
  - `enum EventSender { static func send(_ event: AgentEvent, endpoint: Endpoint, token: String, timeout: TimeInterval = 1) -> Bool }`
  - `enum HookSnippets { static let claudeEvents: [String]; static let codexEvents: [String]; static func hooksJSON(executable: String, source: String, events: [String]) -> String; static let codexFeatureFlag: String; static func mcpJSON(port: UInt16, token: String) -> String }`

- [ ] **Step 1: Failing tests** — `Tests/StatusCoreTests/HookEventMapperTests.swift`

```swift
import XCTest
@testable import StatusCore

final class HookEventMapperTests: XCTestCase {
    private func map(_ json: String, source: String = "claude-code") throws -> AgentEvent? {
        try HookEventMapper.event(source: source, payload: Data(json.utf8))
    }

    func testRunningEvents() throws {
        for hook in ["SessionStart", "UserPromptSubmit", "PostToolUse"] {
            let e = try map(#"{"hook_event_name":"\#(hook)","session_id":"abc","cwd":"/Users/f/Development/telefon-ai"}"#)
            XCTAssertEqual(e, AgentEvent(source: "claude-code", session: "abc", state: "running",
                                         name: "telefon-ai", project: "telefon-ai"))
        }
    }

    func testPermissionNotificationIsWaitingWithMessage() throws {
        let e = try map(#"{"hook_event_name":"Notification","session_id":"abc","cwd":"/x/rundfunk","notification_type":"permission_prompt","message":"Claude needs your permission to use Bash"}"#)
        XCTAssertEqual(e?.state, "waiting")
        XCTAssertEqual(e?.detail, "Claude needs your permission to use Bash")
    }

    func testIdleNotificationIsIgnored() throws {
        XCTAssertNil(try map(#"{"hook_event_name":"Notification","session_id":"a","cwd":"/x","notification_type":"idle_prompt","message":"Claude is waiting for your input"}"#))
        XCTAssertNil(try map(#"{"hook_event_name":"Notification","session_id":"a","cwd":"/x","message":"Claude is waiting for your input"}"#))
    }

    func testCodexPermissionRequest() throws {
        let e = try map(#"{"hook_event_name":"PermissionRequest","session_id":"c1","cwd":"/x/heim-agent","tool_name":"exec_command"}"#, source: "codex")
        XCTAssertEqual(e?.source, "codex")
        XCTAssertEqual(e?.state, "waiting")
        XCTAssertEqual(e?.detail, "wartet auf Freigabe: exec_command")
    }

    func testStopAndSessionEnd() throws {
        XCTAssertEqual(try map(#"{"hook_event_name":"Stop","session_id":"a","cwd":"/x"}"#)?.state, "done")
        XCTAssertEqual(try map(#"{"hook_event_name":"SessionEnd","session_id":"a","cwd":"/x"}"#)?.state, "ended")
    }

    func testUnknownOrIncompleteIsIgnored() throws {
        XCTAssertNil(try map(#"{"hook_event_name":"PreCompact","session_id":"a"}"#))
        XCTAssertNil(try map(#"{"session_id":"a"}"#))
        XCTAssertThrowsError(try map("kein json"))
    }
}
```

`Tests/StatusCoreTests/EventSenderTests.swift`:

```swift
import XCTest
@testable import StatusCore

final class EventSenderTests: XCTestCase {
    func testSendsToRunningServer() throws {
        let port = UInt16.random(in: 50_000...59_000)
        var received: [AgentEvent] = []
        let router = IngressRouter(token: "t", knownPresets: Locked([]), onEvent: { received.append($0) }, onStatus: { _, _ in })
        let server = HTTPServer(port: port, handler: router.handle)
        let ready = expectation(description: "bereit")
        server.onStateChange = { if $0 == .ready { ready.fulfill() } }
        try server.start()
        wait(for: [ready], timeout: 3)
        defer { server.stop() }

        let event = AgentEvent(source: "claude-code", session: "s", state: "running")
        XCTAssertTrue(EventSender.send(event, endpoint: Endpoint(port: port), token: "t"))
        XCTAssertEqual(received, [event])
    }

    func testClosedPortFailsFast() {
        let start = Date()
        let ok = EventSender.send(AgentEvent(source: "a", session: "b", state: "running"),
                                  endpoint: Endpoint(port: 1), token: "t")
        XCTAssertFalse(ok)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }
}
```

`Tests/StatusCoreTests/HookSnippetsTests.swift`:

```swift
import XCTest
@testable import StatusCore

final class HookSnippetsTests: XCTestCase {
    func testClaudeHooksJSONShape() throws {
        let json = HookSnippets.hooksJSON(executable: "/Applications/StatusDisplay.app/Contents/MacOS/StatusDisplay",
                                          source: "claude-code", events: HookSnippets.claudeEvents)
        let obj = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        let hooks = obj["hooks"] as! [String: Any]
        XCTAssertEqual(Set(hooks.keys), Set(HookSnippets.claudeEvents))
        let entry = ((hooks["Stop"] as! [[String: Any]])[0]["hooks"] as! [[String: Any]])[0]
        XCTAssertEqual(entry["type"] as? String, "command")
        XCTAssertEqual(entry["command"] as? String, "'/Applications/StatusDisplay.app/Contents/MacOS/StatusDisplay' hook claude-code")
        XCTAssertEqual(entry["timeout"] as? Int, 2)
    }

    func testMCPJSONContainsTokenHeader() throws {
        let obj = try JSONSerialization.jsonObject(with: Data(HookSnippets.mcpJSON(port: 47615, token: "abc").utf8)) as! [String: Any]
        let server = obj["status-display"] as! [String: Any]
        XCTAssertEqual(server["url"] as? String, "http://127.0.0.1:47615/mcp")
        XCTAssertEqual((server["headers"] as? [String: String])?["Authorization"], "Bearer abc")
    }
}
```

- [ ] **Step 2: Tests laufen lassen, müssen fehlschlagen**

Run: `swift test --filter "HookEventMapperTests|EventSenderTests|HookSnippetsTests"`
Expected: Build-Fehler „cannot find 'HookEventMapper' in scope“.

- [ ] **Step 3: HookEventMapper** — `Sources/StatusCore/Agents/HookEventMapper.swift`

```swift
import Foundation

/// Übersetzt die stdin-Nutzlast von Claude-Code- und Codex-Hooks (gleiches Format) in ein Ereignis.
public enum HookEventMapper {
    public static func event(source: String, payload: Data) throws -> AgentEvent? {
        guard let obj = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            throw AgentEventError.missingField("payload")
        }
        guard let hook = obj["hook_event_name"] as? String, let session = obj["session_id"] as? String else {
            return nil
        }
        let project = (obj["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
        let state: String
        var detail: String?
        switch hook {
        case "SessionStart", "UserPromptSubmit", "PostToolUse":
            state = "running"
        case "Notification":
            let message = obj["message"] as? String
            let idle = obj["notification_type"] as? String == "idle_prompt"
                || (message?.contains("waiting for your input") ?? false)
            if idle { return nil } // nach Stop gilt „fertig“
            state = "waiting"
            detail = message
        case "PermissionRequest":
            state = "waiting"
            detail = (obj["tool_name"] as? String).map { "wartet auf Freigabe: \($0)" }
        case "Stop":
            state = "done"
        case "SessionEnd":
            state = "ended"
        default:
            return nil
        }
        return AgentEvent(source: source, session: session, state: state, name: project,
                          project: project, detail: detail)
    }
}
```

- [ ] **Step 4: EventSender** — `Sources/StatusCore/Agents/EventSender.swift`

```swift
import Foundation

/// Schickt ein Ereignis synchron an die laufende App. Gibt `false` zurück, statt zu warten oder zu werfen.
public enum EventSender {
    public static func send(_ event: AgentEvent, endpoint: Endpoint, token: String, timeout: TimeInterval = 1) -> Bool {
        guard let body = try? JSONEncoder().encode(event),
              let url = URL(string: "http://127.0.0.1:\(endpoint.port)/v1/events") else { return false }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        let done = DispatchSemaphore(value: 0)
        let ok = Locked(false)
        URLSession(configuration: .ephemeral).dataTask(with: request) { _, response, _ in
            ok.value = (response as? HTTPURLResponse)?.statusCode == 202
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + timeout + 0.5)
        return ok.value
    }
}
```

- [ ] **Step 5: HookSnippets** — `Sources/StatusCore/Agents/HookSnippets.swift`

```swift
import Foundation

/// Konfigurationsblöcke, die die Einstellungen zum Kopieren anzeigen. Die App schreibt keine fremden Dateien.
public enum HookSnippets {
    /// Für ~/.claude/settings.json
    public static let claudeEvents = ["SessionStart", "UserPromptSubmit", "PostToolUse", "Notification", "Stop", "SessionEnd"]
    /// Für ~/.codex/hooks.json
    public static let codexEvents = ["SessionStart", "UserPromptSubmit", "PostToolUse", "PermissionRequest", "Stop", "SessionEnd"]

    /// Für ~/.codex/config.toml, falls die Codex-Version Hooks hinter einem Schalter hat.
    public static let codexFeatureFlag = "[features]\nhooks = true"

    public static func hooksJSON(executable: String, source: String, events: [String]) -> String {
        let command = "'\(executable)' hook \(source)"
        var hooks: [String: Any] = [:]
        for event in events {
            hooks[event] = [["hooks": [["type": "command", "command": command, "timeout": 2]]]]
        }
        return pretty(["hooks": hooks])
    }

    /// Eintrag für MCP-Konfigurationen (VS Code/Copilot u. a.); das Format der Hülle variiert je Client.
    public static func mcpJSON(port: UInt16, token: String) -> String {
        pretty(["status-display": [
            "type": "http",
            "url": "http://127.0.0.1:\(port)/mcp",
            "headers": ["Authorization": "Bearer \(token)"],
        ] as [String: Any]])
    }

    private static func pretty(_ object: Any) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object,
                                               options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }
}
```

- [ ] **Step 6: Tests laufen lassen**

Run: `swift test --filter "HookEventMapperTests|EventSenderTests|HookSnippetsTests"`
Expected: `Executed 10 tests, with 0 failures`.

- [ ] **Step 7: Unterbefehl `hook`** — in `Sources/StatusDisplay/CLI.swift` ergänzen

```swift
extension CLI {
    /// Von Claude Code/Codex als Hook aufgerufen. Schreibt nie auf stdout, endet immer mit 0.
    static func hook(_ source: String?) -> Int32 {
        let payload = FileHandle.standardInput.readDataToEndOfFile()
        guard let event = (try? HookEventMapper.event(source: source ?? "claude-code", payload: payload)) ?? nil else { return 0 }
        let support = AppSupport()
        guard let token = support.readToken(), let endpoint = support.readEndpoint() else { return 0 }
        _ = EventSender.send(event, endpoint: endpoint, token: token)
        return 0
    }
}
```

In `main.swift` vor `default:` ergänzen:

```swift
case "hook":
    exit(CLI.hook(arguments.dropFirst().first))
```

- [ ] **Step 8: Hook-Befehl ohne laufende App prüfen**

Run: `swift build && echo '{"hook_event_name":"Stop","session_id":"x","cwd":"/tmp"}' | .build/debug/StatusDisplay hook claude-code; echo "exit=$?"`
Expected: keine Ausgabe außer `exit=0`, Dauer unter 2 s.

- [ ] **Step 9: Codex-Schalter am installierten Codex prüfen**

Run: `codex --version 2>/dev/null || echo "codex nicht installiert"`
Dann in https://developers.openai.com/codex/hooks nachsehen, ob für diese Version `[features] hooks = true` nötig ist und ob `PermissionRequest` und `SessionEnd` unterstützt sind. Weicht es ab, `HookSnippets.codexEvents` bzw. `codexFeatureFlag` anpassen und den Befund im Commit festhalten.

- [ ] **Step 10: Commit**

```bash
git add Sources Tests
git commit -m "Hooks: Claude/Codex-Ereignisse → Agentenzustand, hook-Befehl, Konfigurationsblöcke"
```

---

### Task 10: PRs über gh und GraphQL

**Files:**
- Create: `Sources/StatusCore/PRs/PullRequest.swift`, `Sources/StatusCore/PRs/GitHubAPI.swift`, `Sources/StatusCore/PRs/GHCLITokenProvider.swift`, `Sources/StatusCore/PRs/PRService.swift`, `Sources/StatusCore/PRs/PRAggregator.swift`
- Test: `Tests/StatusCoreTests/GitHubAPITests.swift`, `Tests/StatusCoreTests/GHCLITokenProviderTests.swift`, `Tests/StatusCoreTests/PRServiceTests.swift`, `Tests/StatusCoreTests/PRAggregatorTests.swift`

**Interfaces:**
- Consumes: `PRZone` (Task 6)
- Produces:
  - `struct PullRequest: Equatable, Identifiable { let number: Int; let title, repository: String; let url: URL; let ciFailing: Bool; var id: String }`
  - `struct PRSnapshot: Equatable { let host: String; let toReview, mine: [PullRequest]; let fetchedAt: Date; var ciFailingCount: Int }`
  - `enum GitHubError: Error, Equatable { case ghNotFound, notLoggedIn(String), http(Int), graphql(String), decoding; var message: String }`
  - `enum GitHubAPI { static func graphqlURL(host:) -> URL; static let query: String; static func requestBody() -> Data; static func parse(_:host:at:) throws -> PRSnapshot }`
  - `protocol TokenProviding { func token(for host: String) throws -> String }`
  - `struct GHCLITokenProvider: TokenProviding { init(customPath: String? = nil); init(candidates: [String]); func executable() -> String? }`
  - `final class PRService { init(tokens: TokenProviding, session: URLSession = .shared); func fetch(host: String, now: Date = Date()) async throws -> PRSnapshot }`
  - `struct PRAggregator { static let refreshInterval: TimeInterval = 120; private(set) var snapshots: [String: PRSnapshot]; private(set) var errors: [String: GitHubError]; mutating func record(_ snapshot: PRSnapshot); mutating func record(_ error: GitHubError, host: String); mutating func retain(hosts: [String]); func zone(now: Date) -> PRZone }`

- [ ] **Step 1: Failing tests** — `Tests/StatusCoreTests/GitHubAPITests.swift`

```swift
import XCTest
@testable import StatusCore

final class GitHubAPITests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    func testURLs() {
        XCTAssertEqual(GitHubAPI.graphqlURL(host: "github.com").absoluteString, "https://api.github.com/graphql")
        XCTAssertEqual(GitHubAPI.graphqlURL(host: "ghe.firma.de").absoluteString, "https://ghe.firma.de/api/graphql")
    }

    func testParse() throws {
        let json = #"""
        {"data":{
          "review":{"nodes":[
            {"number":12,"title":"Fix","url":"https://github.com/a/b/pull/12","repository":{"nameWithOwner":"a/b"},"commits":{"nodes":[]}},
            {}
          ]},
          "mine":{"nodes":[
            {"number":3,"title":"Rot","url":"https://github.com/a/c/pull/3","repository":{"nameWithOwner":"a/c"},"commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"FAILURE"}}}]}},
            {"number":4,"title":"Grün","url":"https://github.com/a/c/pull/4","repository":{"nameWithOwner":"a/c"},"commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"SUCCESS"}}}]}},
            {"number":5,"title":"Ohne CI","url":"https://github.com/a/c/pull/5","repository":{"nameWithOwner":"a/c"},"commits":{"nodes":[{"commit":{"statusCheckRollup":null}}]}}
          ]}
        }}
        """#
        let s = try GitHubAPI.parse(Data(json.utf8), host: "github.com", at: now)
        XCTAssertEqual(s.toReview.map(\.number), [12])
        XCTAssertEqual(s.mine.map(\.number), [3, 4, 5])
        XCTAssertEqual(s.ciFailingCount, 1)
        XCTAssertEqual(s.toReview[0].repository, "a/b")
        XCTAssertEqual(s.fetchedAt, now)
    }

    func testGraphQLErrorWithoutData() {
        let json = #"{"data":null,"errors":[{"message":"Bad credentials"}]}"#
        XCTAssertThrowsError(try GitHubAPI.parse(Data(json.utf8), host: "x", at: now)) {
            XCTAssertEqual($0 as? GitHubError, .graphql("Bad credentials"))
        }
        XCTAssertThrowsError(try GitHubAPI.parse(Data("<html>".utf8), host: "x", at: now)) {
            XCTAssertEqual($0 as? GitHubError, .decoding)
        }
    }
}
```

`Tests/StatusCoreTests/GHCLITokenProviderTests.swift`:

```swift
import XCTest
@testable import StatusCore

final class GHCLITokenProviderTests: XCTestCase {
    private func script(_ body: String) throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gh-\(UUID().uuidString)")
        try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }

    func testMissingBinary() {
        let p = GHCLITokenProvider(candidates: ["/nicht/vorhanden/gh"])
        XCTAssertThrowsError(try p.token(for: "github.com")) { XCTAssertEqual($0 as? GitHubError, .ghNotFound) }
    }

    func testReturnsTokenAndPassesHost() throws {
        let path = try script(#"[ "$1 $2 $3 $4" = "auth token --hostname ghe.firma.de" ] && echo gho_abc || exit 1"#)
        XCTAssertEqual(try GHCLITokenProvider(candidates: [path]).token(for: "ghe.firma.de"), "gho_abc")
    }

    func testNotLoggedIn() throws {
        let path = try script("echo 'no oauth token' >&2; exit 1")
        XCTAssertThrowsError(try GHCLITokenProvider(candidates: [path]).token(for: "ghe.firma.de")) {
            XCTAssertEqual($0 as? GitHubError, .notLoggedIn("ghe.firma.de"))
        }
    }

    func testCustomPathComesFirst() {
        XCTAssertEqual(GHCLITokenProvider(customPath: "/x/gh").candidates.first, "/x/gh")
        XCTAssertEqual(GHCLITokenProvider(customPath: "").candidates.first, "/opt/homebrew/bin/gh")
    }
}
```

`Tests/StatusCoreTests/PRServiceTests.swift`:

```swift
import XCTest
@testable import StatusCore

final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data) = Self.handler!(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

struct FixedTokens: TokenProviding {
    var result: Result<String, GitHubError>
    func token(for host: String) throws -> String { try result.get() }
}

final class PRServiceTests: XCTestCase {
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: config)
    }

    func testSendsBearerTokenToGHE() async throws {
        var seen: URLRequest?
        StubProtocol.handler = { req in
            seen = req
            return (200, Data(#"{"data":{"review":{"nodes":[]},"mine":{"nodes":[]}}}"#.utf8))
        }
        let s = try await PRService(tokens: FixedTokens(result: .success("tok")), session: session())
            .fetch(host: "ghe.firma.de")
        XCTAssertEqual(seen?.url?.absoluteString, "https://ghe.firma.de/api/graphql")
        XCTAssertEqual(seen?.value(forHTTPHeaderField: "Authorization"), "bearer tok")
        XCTAssertEqual(s.host, "ghe.firma.de")
    }

    func testHTTPErrorAndTokenError() async {
        StubProtocol.handler = { _ in (401, Data()) }
        do {
            _ = try await PRService(tokens: FixedTokens(result: .success("t")), session: session()).fetch(host: "github.com")
            XCTFail()
        } catch { XCTAssertEqual(error as? GitHubError, .http(401)) }
        do {
            _ = try await PRService(tokens: FixedTokens(result: .failure(.notLoggedIn("h"))), session: session()).fetch(host: "h")
            XCTFail()
        } catch { XCTAssertEqual(error as? GitHubError, .notLoggedIn("h")) }
    }
}
```

`Tests/StatusCoreTests/PRAggregatorTests.swift`:

```swift
import XCTest
@testable import StatusCore

final class PRAggregatorTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func pr(_ n: Int, failing: Bool = false) -> PullRequest {
        PullRequest(number: n, title: "t", repository: "a/b", url: URL(string: "https://x/\(n)")!, ciFailing: failing)
    }

    func testEmptyIsUnknownAndStale() {
        XCTAssertEqual(PRAggregator().zone(now: t0), .unknown)
    }

    func testSumsHostsAndBecomesStale() {
        var a = PRAggregator()
        a.record(PRSnapshot(host: "github.com", toReview: [pr(1)], mine: [pr(2, failing: true)], fetchedAt: t0))
        a.record(PRSnapshot(host: "ghe", toReview: [pr(3), pr(4)], mine: [], fetchedAt: t0.addingTimeInterval(60)))
        let z = a.zone(now: t0.addingTimeInterval(100))
        XCTAssertEqual(z, PRZone(toReview: 3, mine: 1, ciFailing: 1, lastSuccess: t0, isStale: false))
        XCTAssertTrue(a.zone(now: t0.addingTimeInterval(361)).isStale)
    }

    func testErrorKeepsLastSnapshotAndRecoveryClearsError() {
        var a = PRAggregator()
        a.record(PRSnapshot(host: "ghe", toReview: [], mine: [], fetchedAt: t0))
        a.record(.http(502), host: "ghe")
        XCTAssertEqual(a.errors["ghe"], .http(502))
        XCTAssertNotNil(a.snapshots["ghe"])
        a.record(PRSnapshot(host: "ghe", toReview: [], mine: [], fetchedAt: t0))
        XCTAssertNil(a.errors["ghe"])
    }

    func testRetainDropsRemovedHosts() {
        var a = PRAggregator()
        a.record(PRSnapshot(host: "alt", toReview: [pr(1)], mine: [], fetchedAt: t0))
        a.record(.ghNotFound, host: "alt")
        a.retain(hosts: ["github.com"])
        XCTAssertTrue(a.snapshots.isEmpty)
        XCTAssertTrue(a.errors.isEmpty)
    }
}
```

- [ ] **Step 2: Tests laufen lassen, müssen fehlschlagen**

Run: `swift test --filter "GitHubAPITests|GHCLITokenProviderTests|PRServiceTests|PRAggregatorTests"`
Expected: Build-Fehler „cannot find 'GitHubAPI' in scope“.

- [ ] **Step 3: Modelle** — `Sources/StatusCore/PRs/PullRequest.swift`

```swift
import Foundation

public struct PullRequest: Equatable, Identifiable {
    public let number: Int
    public let title: String
    public let repository: String
    public let url: URL
    public let ciFailing: Bool
    public var id: String { url.absoluteString }

    public init(number: Int, title: String, repository: String, url: URL, ciFailing: Bool) {
        self.number = number; self.title = title; self.repository = repository; self.url = url; self.ciFailing = ciFailing
    }
}

public struct PRSnapshot: Equatable {
    public let host: String
    public let toReview: [PullRequest]
    public let mine: [PullRequest]
    public let fetchedAt: Date
    public var ciFailingCount: Int { mine.filter(\.ciFailing).count }

    public init(host: String, toReview: [PullRequest], mine: [PullRequest], fetchedAt: Date) {
        self.host = host; self.toReview = toReview; self.mine = mine; self.fetchedAt = fetchedAt
    }
}

public enum GitHubError: Error, Equatable {
    case ghNotFound
    case notLoggedIn(String)
    case http(Int)
    case graphql(String)
    case decoding

    public var message: String {
        switch self {
        case .ghNotFound: return "gh nicht gefunden – Pfad in den Einstellungen setzen"
        case .notLoggedIn(let host): return "gh nicht angemeldet: gh auth login --hostname \(host)"
        case .http(let code): return code == 0 ? "keine Verbindung" : "HTTP \(code)"
        case .graphql(let m): return "GitHub: \(m)"
        case .decoding: return "unerwartete Antwort"
        }
    }
}
```

- [ ] **Step 4: GitHubAPI** — `Sources/StatusCore/PRs/GitHubAPI.swift`

```swift
import Foundation

public enum GitHubAPI {
    public static func graphqlURL(host: String) -> URL {
        host == "github.com"
            ? URL(string: "https://api.github.com/graphql")!
            : URL(string: "https://\(host)/api/graphql")!
    }

    public static let query = """
    query {
      review: search(query: "is:open is:pr archived:false review-requested:@me", type: ISSUE, first: 50) { nodes { ...pr } }
      mine: search(query: "is:open is:pr archived:false author:@me", type: ISSUE, first: 50) { nodes { ...pr } }
    }
    fragment pr on PullRequest {
      number title url repository { nameWithOwner }
      commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
    }
    """

    public static func requestBody() -> Data {
        try! JSONSerialization.data(withJSONObject: ["query": query])
    }

    public static func parse(_ data: Data, host: String, at date: Date) throws -> PRSnapshot {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { throw GitHubError.decoding }
        guard let d = response.data else {
            throw GitHubError.graphql(response.errors?.first?.message ?? "keine Daten")
        }
        return PRSnapshot(host: host, toReview: d.review.nodes.compactMap(pull), mine: d.mine.nodes.compactMap(pull),
                          fetchedAt: date)
    }

    private static func pull(_ node: Node?) -> PullRequest? {
        guard let n = node, let number = n.number, let title = n.title,
              let urlString = n.url, let url = URL(string: urlString) else { return nil }
        let state = n.commits?.nodes.last??.commit.statusCheckRollup?.state
        return PullRequest(number: number, title: title, repository: n.repository?.nameWithOwner ?? "",
                           url: url, ciFailing: state == "FAILURE" || state == "ERROR")
    }

    private struct Response: Decodable { let data: DataField?; let errors: [GQLError]? }
    private struct GQLError: Decodable { let message: String }
    private struct DataField: Decodable { let review: Search; let mine: Search }
    private struct Search: Decodable { let nodes: [Node?] }
    private struct Node: Decodable {
        let number: Int?; let title: String?; let url: String?
        let repository: Repo?; let commits: Commits?
    }
    private struct Repo: Decodable { let nameWithOwner: String }
    private struct Commits: Decodable { let nodes: [CommitNode?] }
    private struct CommitNode: Decodable { let commit: Commit }
    private struct Commit: Decodable { let statusCheckRollup: Rollup? }
    private struct Rollup: Decodable { let state: String }
}
```

- [ ] **Step 5: GHCLITokenProvider** — `Sources/StatusCore/PRs/GHCLITokenProvider.swift`

```swift
import Foundation

public protocol TokenProviding {
    func token(for host: String) throws -> String
}

/// Holt das Token von `gh`. Menüleisten-Apps haben keinen Shell-PATH, daher feste Suchpfade.
public struct GHCLITokenProvider: TokenProviding {
    public let candidates: [String]

    public init(customPath: String? = nil) {
        let custom = [customPath].compactMap { $0 }.filter { !$0.isEmpty }
        self.init(candidates: custom + ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"])
    }

    public init(candidates: [String]) { self.candidates = candidates }

    public func executable() -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public func token(for host: String) throws -> String {
        guard let exe = executable() else { throw GitHubError.ghNotFound }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exe)
        process.arguments = ["auth", "token", "--hostname", host]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let token = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0, !token.isEmpty else { throw GitHubError.notLoggedIn(host) }
        return token
    }
}
```

- [ ] **Step 6: PRService und PRAggregator**

`Sources/StatusCore/PRs/PRService.swift`:

```swift
import Foundation

public final class PRService {
    private let tokens: TokenProviding
    private let session: URLSession

    public init(tokens: TokenProviding, session: URLSession = .shared) {
        self.tokens = tokens
        self.session = session
    }

    public func fetch(host: String, now: Date = Date()) async throws -> PRSnapshot {
        let token = try tokens.token(for: host)
        var request = URLRequest(url: GitHubAPI.graphqlURL(host: host), timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = GitHubAPI.requestBody()
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GitHubError.http(0)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw GitHubError.http(status) }
        return try GitHubAPI.parse(data, host: host, at: now)
    }
}
```

`Sources/StatusCore/PRs/PRAggregator.swift`:

```swift
import Foundation

/// Führt die Hosts zusammen und entscheidet, wann die PR-Zone veraltet ist.
public struct PRAggregator {
    public static let refreshInterval: TimeInterval = 120

    public private(set) var snapshots: [String: PRSnapshot] = [:]
    public private(set) var errors: [String: GitHubError] = [:]

    public init() {}

    public mutating func record(_ snapshot: PRSnapshot) {
        snapshots[snapshot.host] = snapshot
        errors[snapshot.host] = nil
    }

    public mutating func record(_ error: GitHubError, host: String) { errors[host] = error }

    public mutating func retain(hosts: [String]) {
        let keep = Set(hosts)
        snapshots = snapshots.filter { keep.contains($0.key) }
        errors = errors.filter { keep.contains($0.key) }
    }

    public func zone(now: Date) -> PRZone {
        let all = Array(snapshots.values)
        guard let oldest = all.map(\.fetchedAt).min() else { return .unknown }
        return PRZone(toReview: all.map(\.toReview.count).reduce(0, +),
                      mine: all.map(\.mine.count).reduce(0, +),
                      ciFailing: all.map(\.ciFailingCount).reduce(0, +),
                      lastSuccess: oldest,
                      isStale: now.timeIntervalSince(oldest) > 3 * Self.refreshInterval)
    }
}
```

- [ ] **Step 7: Tests laufen lassen**

Run: `swift test --filter "GitHubAPITests|GHCLITokenProviderTests|PRServiceTests|PRAggregatorTests"`
Expected: `Executed 13 tests, with 0 failures`.

- [ ] **Step 8: Suchabfragen gegen github.com prüfen (nur lesend)**

Run:
```bash
gh api graphql -f query='query { review: search(query: "is:open is:pr archived:false review-requested:@me", type: ISSUE, first: 50) { issueCount } mine: search(query: "is:open is:pr archived:false author:@me", type: ISSUE, first: 50) { issueCount } }' --jq '.data | "zu reviewen: \(.review.issueCount), eigene: \(.mine.issueCount)"'
```
Expected: zwei Zahlen ohne Fehler. Sie müssen in Task 11 mit der Menüleiste übereinstimmen (Checkliste Punkt 1).

- [ ] **Step 9: Commit**

```bash
git add Sources Tests
git commit -m "PRs: Token über gh, GraphQL für github.com und GHE, Zusammenführung mit Veraltung"
```

---

### Task 11: App-Verdrahtung, Menüleiste und Einstellungen

**Files:**
- Create: `Sources/StatusCore/Settings/AppSettings.swift`, `Sources/StatusDisplay/AppModel.swift`, `Sources/StatusDisplay/MenuContent.swift`, `Sources/StatusDisplay/SettingsView.swift`, `Sources/StatusDisplay/StatusIcon.swift`
- Modify: `Sources/StatusDisplay/StatusDisplayApp.swift`
- Test: `Tests/StatusCoreTests/AppSettingsTests.swift`

**Interfaces:**
- Consumes: alles aus Task 3–10
- Produces: `struct AppSettings: Codable, Equatable { var hosts: [String] = ["github.com"]; var brightness = 60; var port: UInt16 = 47615; var ghPath = ""; static func load(from:) -> AppSettings; func save(to:) }` und die lauffähige App.

- [ ] **Step 1: Failing test** — `Tests/StatusCoreTests/AppSettingsTests.swift`

```swift
import XCTest
@testable import StatusCore

final class AppSettingsTests: XCTestCase {
    func testDefaultsAndRoundTrip() {
        let d = UserDefaults(suiteName: "AppSettingsTests-\(UUID().uuidString)")!
        XCTAssertEqual(AppSettings.load(from: d), AppSettings())
        var s = AppSettings()
        s.hosts = ["ghe.firma.de"]
        s.brightness = 30
        s.save(to: d)
        XCTAssertEqual(AppSettings.load(from: d), s)
    }
}
```

- [ ] **Step 2: Test laufen lassen, muss fehlschlagen**

Run: `swift test --filter AppSettingsTests`
Expected: Build-Fehler „cannot find 'AppSettings' in scope“.

- [ ] **Step 3: AppSettings** — `Sources/StatusCore/Settings/AppSettings.swift`

```swift
import Foundation

/// Einstellungen pro Mac. Nichts wird zwischen Macs synchronisiert.
public struct AppSettings: Codable, Equatable {
    public var hosts: [String] = ["github.com"]
    public var brightness = 60
    public var port: UInt16 = 47615
    public var ghPath = ""

    public init() {}

    private static let key = "settings"

    public static func load(from defaults: UserDefaults = .standard) -> AppSettings {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(AppSettings.self, from: $0) } ?? AppSettings()
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.key)
    }
}
```

- [ ] **Step 4: Test laufen lassen**

Run: `swift test --filter AppSettingsTests`
Expected: `Executed 1 test, with 0 failures`.

- [ ] **Step 5: AppModel** — `Sources/StatusDisplay/AppModel.swift`

```swift
import AppKit
import StatusCore
import SwiftUI

/// Verdrahtet alle Einheiten. Alles hier läuft auf dem Main-Thread.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var status: (preset: StatusPreset, since: Date)
    @Published private(set) var presets: [StatusPreset]
    @Published private(set) var agents: [AgentActivity] = []
    @Published private(set) var prs = PRAggregator()
    @Published private(set) var displayState: DisplayController.State = .disconnected
    @Published private(set) var serverState: HTTPServer.State = .stopped
    @Published private(set) var token = ""
    @Published var settings: AppSettings {
        didSet { if settings != oldValue { settings.save(); apply(oldValue) } }
    }

    let statusStore = StatusStore()
    private let registry = AgentRegistry(time: SystemTime())
    private let display: DisplayController
    private let transport = AKP02Transport()
    private let support = AppSupport()
    private let knownPresets = Locked<Set<String>>([])
    private var prService: PRService
    private var server: HTTPServer?
    private var timers: [Timer] = []
    private var renderScheduled = false

    init() {
        let settings = AppSettings.load()
        self.settings = settings
        display = DisplayController(brightness: settings.brightness)
        prService = PRService(tokens: GHCLITokenProvider(customPath: settings.ghPath))
        status = statusStore.effective()
        presets = statusStore.presets
        knownPresets.value = Set(presets.map(\.id))

        // Callbacks kommen auf dem Main-Thread an; Task @MainActor macht das für den Compiler explizit.
        display.onStateChange = { [weak self] state in Task { @MainActor in self?.displayState = state } }
        transport.onConnect = { [weak self] writer in Task { @MainActor in self?.display.attach(writer) } }
        transport.onDisconnect = { [weak self] in Task { @MainActor in self?.display.detach() } }
        transport.start()
        startServer()

        timers.append(Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshLocal() }
        })
        timers.append(Timer.scheduledTimer(withTimeInterval: PRAggregator.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshPRs() }
        })
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                                          queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.display.reinitialize()
                self?.scheduleRender()
            }
        }
        refreshLocal()
        Task { await refreshPRs() }
    }

    var hasWaitingAgent: Bool { agents.contains { $0.state == .waiting } }
    var executablePath: String { Bundle.main.executablePath ?? "StatusDisplay" }

    // MARK: Aktionen

    func setStatus(_ id: String, duration: TimeInterval?) {
        statusStore.set(id, for: duration)
        refreshLocal()
    }

    func setStatusUntilEndOfDay(_ id: String) {
        statusStore.setUntilEndOfDay(id)
        refreshLocal()
    }

    func updatePresets(_ newPresets: [StatusPreset]) {
        statusStore.setPresets(newPresets)
        presets = statusStore.presets
        knownPresets.value = Set(presets.map(\.id))
        refreshLocal()
    }

    func dismissAgent(_ id: String) {
        registry.dismiss(id: id)
        refreshLocal()
    }

    func regenerateToken() {
        server?.stop()
        _ = try? support.regenerateToken()
        startServer()
    }

    func refreshPRs() async {
        let hosts = settings.hosts
        for host in hosts {
            do {
                prs.record(try await prService.fetch(host: host))
            } catch let error as GitHubError {
                prs.record(error, host: host)
            } catch {
                prs.record(.http(0), host: host)
            }
        }
        prs.retain(hosts: hosts)
        scheduleRender()
    }

    // MARK: Intern

    private func handle(_ event: AgentEvent) {
        try? registry.apply(event)
        refreshLocal()
    }

    private func refreshLocal() {
        status = statusStore.effective()
        agents = registry.snapshot()
        scheduleRender()
    }

    /// Höchstens zwei Renderläufe pro Sekunde.
    private func scheduleRender() {
        guard !renderScheduled else { return }
        renderScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self else { return }
            self.renderScheduled = false
            let now = Date()
            let state = BoardState(statusName: status.preset.name, statusColor: status.preset.color,
                                   statusSince: status.since, agents: agents, prs: prs.zone(now: now), now: now)
            display.show(jpeg: PanelImage.encode(landscape: BoardRenderer.render(state)))
        }
    }

    private func startServer() {
        do {
            token = try support.loadOrCreateToken()
        } catch {
            serverState = .failed("Token: \(error.localizedDescription)")
            return
        }
        let deliver: (AgentEvent) -> Void = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        let mcp = MCPHandler(onEvent: deliver)
        let router = IngressRouter(token: token, knownPresets: knownPresets, mcp: mcp.handle, onEvent: deliver,
                                   onStatus: { [weak self] id, duration in
                                       Task { @MainActor in self?.setStatus(id, duration: duration) }
                                   })
        let port = settings.port
        let s = HTTPServer(port: port, handler: router.handle)
        s.onStateChange = { [weak self] state in
            Task { @MainActor in
                self?.serverState = state
                if state == .ready { try? self?.support.writeEndpoint(Endpoint(port: port)) }
            }
        }
        do {
            try s.start()
            server = s
        } catch {
            serverState = .failed(error.localizedDescription)
        }
    }

    private func apply(_ old: AppSettings) {
        if old.port != settings.port {
            server?.stop()
            startServer()
        }
        if old.brightness != settings.brightness { display.setBrightness(settings.brightness) }
        if old.hosts != settings.hosts || old.ghPath != settings.ghPath {
            prService = PRService(tokens: GHCLITokenProvider(customPath: settings.ghPath))
            Task { await refreshPRs() }
        }
    }
}
```

- [ ] **Step 6: StatusIcon** — `Sources/StatusDisplay/StatusIcon.swift`

```swift
import AppKit
import StatusCore

enum StatusIcon {
    /// Farbiger Kreis in Statusfarbe; gelber Punkt oben rechts, wenn ein Agent wartet.
    static func image(color: RGBColor, waiting: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor(cgColor: color.cgColor)?.setFill()
            NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 13, height: 13)).fill()
            if waiting {
                NSColor.systemYellow.setFill()
                NSBezierPath(ovalIn: NSRect(x: 11, y: 11, width: 7, height: 7)).fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
```

- [ ] **Step 7: Menü** — `Sources/StatusDisplay/MenuContent.swift`

```swift
import AppKit
import StatusCore
import SwiftUI

struct MenuContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Text("\(model.status.preset.name) · \(BoardText.since(model.status.since, now: Date()))")
        ForEach(model.presets) { preset in
            Menu(preset.name) {
                Button("Ohne Ende") { model.setStatus(preset.id, duration: nil) }
                Button("30 Minuten") { model.setStatus(preset.id, duration: 1800) }
                Button("1 Stunde") { model.setStatus(preset.id, duration: 3600) }
                Button("2 Stunden") { model.setStatus(preset.id, duration: 7200) }
                Button("Bis Tagesende") { model.setStatusUntilEndOfDay(preset.id) }
            } primaryAction: {
                model.setStatus(preset.id, duration: nil)
            }
        }

        Divider()
        Section("Agenten") {
            if model.agents.isEmpty { Text("keine") }
            ForEach(model.agents) { agent in
                Menu("\(agent.name) – \(BoardText.agentLabel(agent, now: Date()))") {
                    if let detail = agent.detail { Text(detail) }
                    Text("Quelle: \(agent.source)")
                    if let url = agent.url { Button("Öffnen") { NSWorkspace.shared.open(url) } }
                    Button("Entfernen") { model.dismissAgent(agent.id) }
                }
            }
        }

        Divider()
        Section("PRs") {
            ForEach(model.settings.hosts, id: \.self) { host in
                if let snap = model.prs.snapshots[host] {
                    prMenu("\(host): \(snap.toReview.count) zu reviewen", snap.toReview)
                    prMenu("\(host): \(snap.mine.count) eigene (\(snap.ciFailingCount) CI rot)", snap.mine)
                }
                if let error = model.prs.errors[host] { Text("\(host): \(error.message)") }
            }
            Button("Aktualisieren") { Task { await model.refreshPRs() } }
        }

        Divider()
        Text(model.displayState == .connected ? "Display verbunden" : "Display nicht gefunden")
        if case .failed(let message) = model.serverState { Text("Server: \(message)") }
        SettingsLink { Text("Einstellungen …") }
        Button("Beenden") { NSApp.terminate(nil) }
    }

    @ViewBuilder
    private func prMenu(_ title: String, _ pulls: [PullRequest]) -> some View {
        Menu(title) {
            if pulls.isEmpty { Text("keine") }
            ForEach(pulls) { pr in
                Button((pr.ciFailing ? "● " : "") + "\(pr.repository)#\(pr.number) \(pr.title)") {
                    NSWorkspace.shared.open(pr.url)
                }
            }
        }
    }
}
```

- [ ] **Step 8: Einstellungen** — `Sources/StatusDisplay/SettingsView.swift`

```swift
import AppKit
import ServiceManagement
import StatusCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var newHost = ""
    @State private var presets: [StatusPreset] = []
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        TabView {
            general.tabItem { Text("Allgemein") }
            statusTab.tabItem { Text("Status") }
            agentsTab.tabItem { Text("Agenten") }
        }
        .frame(width: 620, height: 520)
        .padding()
        .onAppear {
            presets = model.presets
            NSApp.activate()
        }
    }

    private var general: some View {
        Form {
            Section("GitHub-Hosts") {
                ForEach(model.settings.hosts, id: \.self) { host in
                    HStack {
                        Text(host)
                        Spacer()
                        Button("Entfernen") { model.settings.hosts.removeAll { $0 == host } }
                    }
                }
                HStack {
                    TextField("z. B. ghe.firma.de", text: $newHost)
                    Button("Hinzufügen") {
                        let h = newHost.trimmingCharacters(in: .whitespaces)
                        if !h.isEmpty && !model.settings.hosts.contains(h) { model.settings.hosts.append(h) }
                        newHost = ""
                    }
                }
                TextField("Pfad zu gh (leer = automatisch)", text: $model.settings.ghPath)
            }
            Section("Display") {
                Slider(value: Binding(get: { Double(model.settings.brightness) },
                                      set: { model.settings.brightness = Int($0) }), in: 0...100, step: 5) {
                    Text("Helligkeit \(model.settings.brightness) %")
                }
            }
            Section("Start") {
                Toggle("Bei Anmeldung starten", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
    }

    private var statusTab: some View {
        Form {
            ForEach($presets) { $preset in
                HStack {
                    TextField("Name", text: $preset.name)
                    TextField("#RRGGBB", text: $preset.colorHex).frame(width: 100)
                    Circle().fill(Color(cgColor: preset.color.cgColor)).frame(width: 16, height: 16)
                    Button("Löschen") { presets.removeAll { $0.id == preset.id } }
                        .disabled(presets.count <= 1)
                }
            }
            HStack {
                Button("Neuer Status") {
                    presets.append(StatusPreset(id: UUID().uuidString, name: "Neu", colorHex: "#5A5F66"))
                }
                Spacer()
                Button("Übernehmen") { model.updatePresets(presets) }
            }
        }
    }

    private var agentsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Port").frame(width: 60, alignment: .leading)
                    TextField("47615", value: $model.settings.port, format: .number.grouping(.never)).frame(width: 90)
                    if case .failed(let m) = model.serverState { Text(m).foregroundStyle(.red) }
                }
                HStack {
                    Text("Token: \(String(model.token.prefix(8)))…")
                    Button("Neu erzeugen") { model.regenerateToken() }
                }
                snippet("Claude Code – in ~/.claude/settings.json einfügen",
                        HookSnippets.hooksJSON(executable: model.executablePath, source: "claude-code",
                                               events: HookSnippets.claudeEvents))
                snippet("Codex – ~/.codex/hooks.json",
                        HookSnippets.hooksJSON(executable: model.executablePath, source: "codex",
                                               events: HookSnippets.codexEvents))
                snippet("Codex – ~/.codex/config.toml (falls nötig)", HookSnippets.codexFeatureFlag)
                snippet("MCP (Copilot u. a.) – Eintrag in der MCP-Konfiguration",
                        HookSnippets.mcpJSON(port: model.settings.port, token: model.token))
            }
        }
    }

    private func snippet(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title).bold()
                Spacer()
                Button("Kopieren") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }
            Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                .padding(6).background(Color.secondary.opacity(0.1))
        }
    }
}
```

- [ ] **Step 9: App** — `Sources/StatusDisplay/StatusDisplayApp.swift` ersetzen

```swift
import StatusCore
import SwiftUI

struct StatusDisplayApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(nsImage: StatusIcon.image(color: model.status.preset.color, waiting: model.hasWaitingAgent))
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(model: model)
        }
    }
}
```

- [ ] **Step 10: Bauen und alle Tests**

Run: `swift test && scripts/build.sh`
Expected: alle Tests grün, `build/StatusDisplay.app`.

- [ ] **Step 11: Manuelle Prüfung am Gerät** (AKP02 angesteckt; `open build/StatusDisplay.app`)

Checkliste, jeden Punkt mit Ergebnis im Commit-Text oder Abschlussbericht festhalten:
1. Menüleiste zeigt einen grauen Kreis, das Display zeigt „VERFÜGBAR“, Uhrzeit, PR-Zahlen von github.com.
2. Status „Deep Focus“ → Kreis und Statuszone werden rot, „seit 0 min“.
3. `curl -s http://127.0.0.1:47615/v1/health` → `{"ok":true}`.
4. `curl -s -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:47615/v1/events -d '{}'` → `401`.
5. `curl -s -X POST -H "Authorization: Bearer $(cat ~/Library/Application\ Support/status-display/token)" http://127.0.0.1:47615/v1/events -d '{"source":"test","session":"1","state":"waiting","name":"probe"}'` → Display zeigt „probe“ gelb hinterlegt, Menüleistensymbol bekommt den gelben Punkt.
6. Im Menü „probe → Entfernen“ → Zeile verschwindet.
7. Display abziehen → Menü „Display nicht gefunden“; wieder anstecken → Board erscheint innerhalb weniger Sekunden mit richtiger Helligkeit.
8. App beenden → Display fällt auf das AJAZZ-Logo zurück.
9. Kam beim ersten Start eine Abfrage (Eingabeüberwachung, Schlüsselbund für `gh`)? Ja/nein vermerken.

- [ ] **Step 12: Commit**

```bash
git add Sources Tests
git commit -m "App: Menüleiste, Einstellungen, Verdrahtung aller Eingänge mit Display"
```

---

### Task 12: Hooks einrichten, End-to-End prüfen, Doku

**Files:**
- Modify: `README.md`

- [ ] **Step 1: App dauerhaft ablegen**

```bash
scripts/build.sh
rm -rf /Applications/StatusDisplay.app && cp -R build/StatusDisplay.app /Applications/
open /Applications/StatusDisplay.app
```

- [ ] **Step 2: Claude-Hooks einrichten** — Florian fügt den Block aus Einstellungen → Agenten → „Claude Code“ in `~/.claude/settings.json` ein (bestehende `hooks` zusammenführen, nicht ersetzen). Die App schreibt die Datei nicht selbst; ein Agent ändert sie nur mit ausdrücklicher Zustimmung.

- [ ] **Step 3: End-to-End mit Claude Code**

In einem beliebigen Repo `claude` starten, eine kurze Aufgabe geben.
Expected: Display zeigt das Repo als „läuft“; bei einer Freigabeabfrage „wartet“ mit gelbem Band; nach Ende „fertig“, nach 10 min verschwunden; nach `/exit` sofort verschwunden.

- [ ] **Step 4: README ergänzen** — Abschnitt nach „Bauen“

```markdown
## Einrichten

1. `StatusDisplay.app` nach `/Applications` kopieren, einmal per Rechtsklick → Öffnen starten.
2. Einstellungen → Allgemein: GitHub-Hosts eintragen (`github.com` und/oder GHE-Host).
   Voraussetzung: `gh auth login --hostname <host>`.
3. Einstellungen → Agenten: Blöcke für Claude Code (`~/.claude/settings.json`),
   Codex (`~/.codex/hooks.json`) und MCP-Clients kopieren und einfügen.
4. Optional: „Bei Anmeldung starten“.

## Schnittstelle

Alle Anfragen gehen an `http://127.0.0.1:47615` mit
`Authorization: Bearer <~/Library/Application Support/status-display/token>`.

| Methode | Pfad | Inhalt |
|---|---|---|
| GET | `/v1/health` | ohne Token |
| POST | `/v1/events` | `{"source","session","state","name","project","detail","url"}`, state ∈ running, waiting, done, error, ended |
| POST | `/v1/status` | `{"preset":"deep-focus","minutes":60}` |
| POST | `/mcp` | MCP (Streamable HTTP), Tool `report_status` |

## Unterbefehle

    StatusDisplay hook claude-code|codex   # von Hooks aufgerufen, liest stdin
    StatusDisplay preview board.png        # Beispielbild rendern
    StatusDisplay display-test             # 15 s Farbfelder aufs Panel
    StatusDisplay version
```

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "README: Einrichtung, Schnittstelle, Unterbefehle"
```

- [ ] **Step 6: Abschluss** — superpowers:finishing-a-development-branch anwenden. Das Repo hat noch kein GitHub-Remote; ob eines angelegt wird (und damit CI läuft), entscheidet Florian.
