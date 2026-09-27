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
        var everConnected = false
        controller.onStateChange = { state in
            if state == .connected { everConnected = true }
            print(state == .connected ? "Display verbunden" : "Display getrennt")
        }
        transport.onConnect = { controller.attach($0); controller.show(jpeg: jpeg) }
        transport.onDisconnect = { controller.detach() }
        let openResult = transport.start()
        guard openResult == kIOReturnSuccess else {
            print(String(format: "HID-Manager konnte nicht geöffnet werden (IOReturn %#x)", openResult))
            return 1
        }
        withExtendedLifetime(transport) {
            RunLoop.main.run(until: Date().addingTimeInterval(15))
        }
        if !everConnected { print("Kein AKP02 gefunden (0300:3017)") }
        return everConnected ? 0 : 1
    }
}

extension CLI {
    /// Schreibt ein Beispiel-Board als PNG (Querformat) zur Sichtprüfung.
    static func preview(_ path: String?) -> Int32 {
        guard let path else { print("Aufruf: StatusDisplay preview <datei.png>"); return 2 }
        let now = Date()
        let agents = [
            AgentActivity(id: "1", source: "claude-code", name: "rundfunk", state: .waiting,
                          since: now.addingTimeInterval(-65 * 60), lastSeen: now),
            AgentActivity(id: "2", source: "claude-code", name: "telefon-ai", state: .running,
                          since: now.addingTimeInterval(-900), lastSeen: now),
            AgentActivity(id: "3", source: "codex", name: "heim-agent", state: .done,
                          since: now.addingTimeInterval(-60), lastSeen: now),
            AgentActivity(id: "4", source: "codex", name: "sprachkurs", state: .running,
                          since: now.addingTimeInterval(-3 * 3600), lastSeen: now.addingTimeInterval(-65 * 60),
                          isStale: true),
        ]
        let rows = [
            PRRow(repoKey: "github.com/florianhuber/telefon-ai", repository: "telefon-ai",
                  toReview: 2, mine: 1, ciFailing: true),
            PRRow(repoKey: "github.com/florianhuber/rundfunk", repository: "rundfunk",
                  toReview: 1, mine: 0, ciFailing: false),
            PRRow(repoKey: "github.com/florianhuber/heim-agent", repository: "heim-agent",
                  toReview: 0, mine: 0, ciFailing: false),
            PRRow(repoKey: "github.com/florianhuber/mise-en-place", repository: "mise-en-place",
                  toReview: 0, mine: 2, ciFailing: false),
            PRRow(repoKey: "github.com/florianhuber/sprachkurs", repository: "sprachkurs",
                  toReview: 0, mine: 1, ciFailing: false),
            PRRow(repoKey: "github.com/florianhuber/status-display", repository: "status-display",
                  toReview: 0, mine: 1, ciFailing: false),
            PRRow(repoKey: "github.com/florianhuber/claude-konventionen", repository: "claude-konventionen",
                  toReview: 0, mine: 1, ciFailing: false),
        ]
        let state = BoardState(statusName: "Deep Focus", statusColor: RGBColor(hex: "#B3263E")!,
                               statusSince: now.addingTimeInterval(-47 * 60), agents: agents,
                               prs: PRZone(rows: rows, ciFailingCount: 1, lastSuccess: now, isStale: false),
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
