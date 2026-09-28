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
            let zone = model.prs.zone(now: Date(), hosts: model.settings.hosts,
                                      pinned: model.settings.pinnedRepos, hidden: model.settings.hiddenRepos,
                                      shown: model.settings.shownRepos, hostDefaults: model.settings.hostDefaults)
            if zone.rows.isEmpty && zone.hiddenReviews.isEmpty { Text("keine") }
            ForEach(zone.rows) { row in
                repoMenu(row)
            }
            if !zone.hiddenReviews.isEmpty {
                hiddenReviewsMenu(zone.hiddenReviews)
            }
            ForEach(model.settings.hosts, id: \.self) { host in
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
        Button("Board-Fenster anzeigen") { model.showBoardWindow() }
        SettingsOpener()
        Button("Beenden") { NSApp.terminate(nil) }
    }

    @ViewBuilder
    private func repoMenu(_ row: PRRow) -> some View {
        Menu("\(row.ciFailing ? "● " : "")\(row.repository) – \(row.toReview) zu reviewen · \(row.mine) offen") {
            let pulls = pullRequests(forRepoKey: row.repoKey)
            if pulls.isEmpty && row.approvedReviews.isEmpty { Text("keine") }
            ForEach(pulls) { pr in
                Button(prLabel(pr)) {
                    NSWorkspace.shared.open(pr.url)
                }
            }
            if !row.approvedReviews.isEmpty {
                approvedReviewsMenu(row.approvedReviews)
            }
        }
    }

    /// Zeilenbeschriftung für einen PR im Menü: roter Punkt bei roter CI, „Extra · “ bei einer
    /// ausdrücklichen Zusatzanfrage an mich (Entscheidung Florian, 28.09.2026, status-display#21),
    /// „Draft · “ bei einem Entwurf, dann `#Nummer Titel`.
    private func prLabel(_ pr: PullRequest) -> String {
        (pr.ciFailing ? "● " : "") + (pr.hasExtraRequestForMe ? "Extra · " : "")
            + (pr.isDraft ? "Draft · " : "") + "#\(pr.number) \(pr.title)"
    }

    /// Review-Requests, für die `needsMyReview == false` ist (Code-Owner-Anfrage, die schon durch
    /// einen fremden Review erledigt ist): zählen nicht mehr als „zu reviewen“, bleiben aber
    /// sichtbar (Entscheidung Florian, 28.09.2026, status-display#21).
    @ViewBuilder
    private func approvedReviewsMenu(_ reviews: [PullRequest]) -> some View {
        Menu("Schon freigegeben · \(reviews.count)") {
            ForEach(reviews) { pr in
                Button("#\(pr.number) \(pr.title)") {
                    NSWorkspace.shared.open(pr.url)
                }
            }
        }
        .foregroundStyle(.secondary)
    }

    /// Unauffällige, aufklappbare Hinweiszeile für Review-Requests in ausgeblendeten Repos
    /// (Entscheidung Florian, 28.09.2026, status-display#19). Eigene offene PRs zählen hier nicht,
    /// `PRAggregator.zone` liefert sie deshalb gar nicht erst in `hiddenReviews`.
    @ViewBuilder
    private func hiddenReviewsMenu(_ reviews: [PullRequest]) -> some View {
        Menu("Ausgeblendet · \(reviews.count) zu reviewen") {
            ForEach(reviews) { pr in
                Button((pr.ciFailing ? "● " : "") + (pr.hasExtraRequestForMe ? "Extra · " : "")
                       + "\(pr.repository) #\(pr.number) \(pr.title)") {
                    NSWorkspace.shared.open(pr.url)
                }
            }
        }
        .foregroundStyle(.secondary)
    }

    /// Alle eigenen PRs und noch offenen Review-Requests (kein `APPROVED`) für ein Repo
    /// (`host/owner/name`), über alle Hosts, ohne Duplikate (falls dieselbe PR in beiden Suchen
    /// auftaucht). Freigegebene Review-Requests fehlen hier bewusst – die liefert `PRRow.approvedReviews`.
    private func pullRequests(forRepoKey repoKey: String) -> [PullRequest] {
        var seen = Set<String>()
        return model.prs.snapshots.values
            .flatMap { snap in
                (snap.toReview.filter(\.needsMyReview) + snap.mine)
                    .filter { "\(snap.host)/\($0.repository)" == repoKey }
            }
            .filter { seen.insert($0.id).inserted }
    }
}
