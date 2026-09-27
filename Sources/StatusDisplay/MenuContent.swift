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
                if let warning = model.prs.snapshots[host]?.warning { Text("\(host): Hinweis: \(warning)") }
                if let error = model.prs.errors[host] { Text("\(host): \(error.message)") }
            }
            Button("Aktualisieren") { Task { await model.refreshPRs() } }
        }

        Divider()
        if let code = model.hidOpenError {
            Text("HID-Zugriff fehlgeschlagen (IOReturn \(String(format: "0x%08X", UInt32(bitPattern: code))))")
        } else {
            Text(model.displayState == .connected ? "Display verbunden" : "Display nicht gefunden")
        }
        if case .failed(let message) = model.serverState { Text("Server: \(message)") }
        SettingsOpener()
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
