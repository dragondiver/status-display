import AppKit
import Combine
import StatusCore
import SwiftUI

/// Dashboard-Fenster nach Entwurf B (Mail-artig, status-display#24): links Bereiche und Repos mit
/// Zählern, Mitte die Liste, rechts die Details. Die ganze Logik (welche Einträge wohin, Zähler,
/// Sortierung, Texte) steckt in `Dashboard`/`DashboardText` in StatusCore; hier wird nur gezeigt.
///
/// Farben: Orange heißt „wartet auf dich / Extra“, Rot heißt „CI rot“ – jeweils mit Text-Etikett
/// daneben, nie als einziges Signal. Systemfarben, damit Hell/Dunkel macOS folgt.
struct DashboardView: View {
    @ObservedObject var model: AppModel

    enum SidebarSelection: Hashable {
        case section(DashboardSection)
        case repo(String)
        case hidden
    }

    @State private var sidebar: SidebarSelection? = .section(.waiting)
    @State private var selectedItemID: String?
    @State private var now = Date()
    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        let dashboard = model.dashboard(now: now)
        let items = listItems(dashboard)
        NavigationSplitView {
            DashboardSidebar(dashboard: dashboard, selection: $sidebar)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 280)
        } content: {
            DashboardList(dashboard: dashboard, selection: sidebar, items: items, now: now,
                          selectedItemID: $selectedItemID, open: open)
                .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 520)
                .safeAreaInset(edge: .bottom) { footer(dashboard) }
        } detail: {
            if let item = items.first(where: { $0.id == selectedItemID }) {
                DashboardDetail(item: item, now: now, open: open, dismissAgent: model.dismissAgent)
            } else {
                Text("Nichts ausgewählt")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if model.prsRefreshRunning {
                    ProgressView().controlSize(.small)
                }
                Button {
                    Task { await model.refreshPRs() }
                } label: {
                    Label("Aktualisieren", systemImage: "arrow.clockwise")
                }
                .help("PRs aktualisieren (⌘R)")
                .keyboardShortcut("r", modifiers: .command)
                Menu {
                    StatusMenuItems(model: model)
                } label: {
                    StatusChip(name: model.status.preset.name, color: model.status.preset.color)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .onHover { inside in
                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }
        }
        .background { sectionShortcuts }
        .onReceive(clock) { now = $0 }
        .onChange(of: sidebar) { selectedItemID = nil }
        .frame(minWidth: 760, minHeight: 420)
    }

    private func listItems(_ dashboard: Dashboard) -> [DashboardItem] {
        switch sidebar {
        case .section(let section)?: return dashboard.items(in: section)
        case .repo(let key)?: return dashboard.items(inRepo: key)
        case .hidden?: return dashboard.hiddenReviews
        case nil: return []
        }
    }

    /// ⌘1–⌘5 wählt einen Bereich. Unsichtbare Knöpfe, weil `keyboardShortcut` einen Knopf braucht.
    private var sectionShortcuts: some View {
        ZStack {
            ForEach(DashboardSection.allCases) { section in
                Button(section.title) { sidebar = .section(section) }
                    .keyboardShortcut(KeyEquivalent(Character(String(section.rawValue))), modifiers: .command)
            }
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func footer(_ dashboard: Dashboard) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(standText(dashboard))
                .foregroundStyle(dashboard.isStale ? Color.orange : Color.secondary)
            ForEach(model.settings.hosts, id: \.self) { host in
                if let error = model.prs.errors[host] {
                    Text("\(host): \(error.message)").foregroundStyle(.secondary)
                } else if let warning = model.prs.snapshots[host]?.warning {
                    Text("\(host): Hinweis: \(warning)").foregroundStyle(.secondary)
                }
            }
        }
        .font(.caption)
        .lineLimit(2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func standText(_ dashboard: Dashboard) -> String {
        let hosts = model.settings.hosts.joined(separator: ", ")
        guard let last = dashboard.lastSuccess else { return "Noch kein Abruf · \(hosts)" }
        let time = last.formatted(date: .omitted, time: .shortened)
        return (dashboard.isStale ? "Veraltet, Stand \(time)" : "Stand \(time)") + " · \(hosts)"
    }

    private func open(_ item: DashboardItem) {
        guard let url = item.url else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Sidebar

private struct DashboardSidebar: View {
    let dashboard: Dashboard
    @Binding var selection: DashboardView.SidebarSelection?

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(DashboardSection.allCases) { section in
                    let count = dashboard.count(section)
                    SidebarRow(title: section.title, count: count, waiting: section == .waiting && count > 0)
                        .tag(DashboardView.SidebarSelection.section(section))
                }
            }
            if !dashboard.repos.isEmpty {
                Section("Repos") {
                    ForEach(dashboard.repos) { repo in
                        SidebarRow(title: repo.name, count: repo.count, waiting: repo.hasWaiting)
                            .help(repo.repoKey)
                            .tag(DashboardView.SidebarSelection.repo(repo.repoKey))
                    }
                }
            }
            if !dashboard.hiddenReviews.isEmpty {
                Section {
                    SidebarRow(title: "Ausgeblendete Repos", count: dashboard.hiddenReviews.count, waiting: false)
                        .foregroundStyle(.secondary)
                        .help("Review-Anfragen in ausgeblendeten Repos – zählen nicht unter „Wartet auf dich“")
                        .tag(DashboardView.SidebarSelection.hidden)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct SidebarRow: View {
    let title: String
    let count: Int
    /// Etwas davon wartet auf dich: Zähler orange, fett und mit Sanduhr – nicht nur Farbe.
    let waiting: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(title).lineLimit(1)
            Spacer()
            if waiting {
                Image(systemName: "hourglass")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("wartet auf dich")
            }
            Text("\(count)")
                .monospacedDigit()
                .fontWeight(waiting ? .semibold : .regular)
                .foregroundStyle(waiting ? Color.orange : Color.secondary)
        }
    }
}

// MARK: - Liste

private struct DashboardList: View {
    let dashboard: Dashboard
    let selection: DashboardView.SidebarSelection?
    let items: [DashboardItem]
    let now: Date
    @Binding var selectedItemID: String?
    let open: (DashboardItem) -> Void

    var body: some View {
        if items.isEmpty {
            emptyState
        } else {
            List(items, selection: $selectedItemID) { item in
                DashboardRow(item: item, now: now).tag(item.id)
            }
            .contextMenu(forSelectionType: String.self) { _ in
                EmptyView()
            } primaryAction: { ids in
                // Doppelklick oder Enter in der Liste öffnet den PR bzw. den Agenten-Link.
                for id in ids {
                    if let item = items.first(where: { $0.id == id }) { open(item) }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if selection == .section(.waiting) {
            ContentUnavailableView {
                Label(dashboard.emptyTitle, systemImage: "checkmark.circle")
            } description: {
                Text(dashboard.summary)
            }
        } else {
            Text("Keine Einträge.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct DashboardRow: View {
    let item: DashboardItem
    let now: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(markColor)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    ForEach(item.tags, id: \.self) { TagLabel(tag: $0) }
                    Text(headline).lineLimit(1)
                }
                Text(subline)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let date = item.date {
                Text(DashboardText.shortAge(from: date, now: now))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var markColor: Color {
        if item.isWaitingForMe { return .orange }
        if item.tags.contains(.ciFailing) || item.tags.contains(.agentError) { return .red }
        if item.urgency == .ownActionNeeded { return .orange }
        return Color.secondary.opacity(0.5)
    }

    private var headline: String {
        switch item.subject {
        case .pullRequest(let pr, _, _): return "\(shortRepo(pr.repository)) #\(pr.number)"
        case .agent(let agent): return "Agent \(agent.name)"
        }
    }

    private var subline: String {
        switch item.subject {
        case .pullRequest(let pr, _, let isMine): return isMine ? "Dein PR: \(pr.title)" : pr.title
        case .agent(let agent):
            let label = BoardText.agentLabel(agent, now: now)
            guard let detail = agent.detail, !detail.isEmpty else { return label }
            return "\(label): \(detail)"
        }
    }
}

private func shortRepo(_ nameWithOwner: String) -> String {
    nameWithOwner.split(separator: "/").last.map(String.init) ?? nameWithOwner
}

/// Kleines Text-Etikett. Die Schrift bleibt in Primärfarbe (Kontrast in Hell und Dunkel), die
/// Bedeutungsfarbe liegt nur im Hintergrund – der Text trägt die Aussage.
private struct TagLabel: View {
    let tag: DashboardTag

    var body: some View {
        Text(tag.label)
            .font(.caption)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(tint.opacity(0.22), in: RoundedRectangle(cornerRadius: 4))
    }

    private var tint: Color {
        switch tag {
        case .extra, .agentWaiting, .changesRequested: return .orange
        case .ciFailing, .agentError: return .red
        case .codeOwner, .conflict, .draft, .agentStale: return .secondary
        }
    }
}

// MARK: - Details

private struct DashboardDetail: View {
    let item: DashboardItem
    let now: Date
    let open: (DashboardItem) -> Void
    let dismissAgent: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch item.subject {
                case .pullRequest(let pr, _, let isMine):
                    pullRequestDetail(pr, isMine: isMine)
                case .agent(let agent):
                    agentDetail(agent)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func pullRequestDetail(_ pr: PullRequest, isMine: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(pr.repository) · #\(pr.number)")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(pr.title)
                .font(.title3.weight(.semibold))
                .textSelection(.enabled)
        }
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                label("Warum bei dir")
                HStack(spacing: 4) {
                    ForEach(item.tags.filter { $0 == .extra || $0 == .codeOwner }, id: \.self) { TagLabel(tag: $0) }
                    Text(DashboardText.reason(pr, isMine: isMine))
                }
            }
            GridRow {
                label("Autor")
                Text(DashboardText.author(pr, now: now))
            }
            GridRow {
                label("Reviews")
                Text(DashboardText.reviews(pr))
            }
            GridRow {
                label("CI")
                HStack(spacing: 4) {
                    ciSymbol(pr)
                    Text(DashboardText.checks(pr))
                }
            }
            GridRow {
                label("Änderungen")
                Text(changesText(pr))
            }
            if pr.isDraft || pr.reviewDecision == .changesRequested {
                GridRow {
                    label("Status")
                    HStack(spacing: 4) {
                        ForEach(item.tags.filter { $0 == .draft || $0 == .changesRequested }, id: \.self) {
                            TagLabel(tag: $0)
                        }
                    }
                }
            }
        }
        .font(.callout)
        Button("Auf GitHub öffnen") { open(item) }
            .keyboardShortcut(.defaultAction)
            .padding(.top, 6)
    }

    private func changesText(_ pr: PullRequest) -> String {
        guard let merge = DashboardText.merge(pr) else { return DashboardText.size(pr) }
        return "\(DashboardText.size(pr)) · \(merge)"
    }

    @ViewBuilder
    private func ciSymbol(_ pr: PullRequest) -> some View {
        if let checks = pr.checks, checks.failed > 0 {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red).accessibilityHidden(true)
        } else if pr.ciFailing {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red).accessibilityHidden(true)
        } else if let checks = pr.checks, checks.total > 0, checks.other == 0 {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func agentDetail(_ agent: AgentActivity) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Agent · \(agent.source)")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(agent.name)
                .font(.title3.weight(.semibold))
        }
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                label("Projekt")
                Text(agent.project ?? "–")
            }
            GridRow {
                label("Zustand")
                HStack(spacing: 4) {
                    ForEach(item.tags, id: \.self) { TagLabel(tag: $0) }
                    Text(BoardText.agentLabel(agent, now: now))
                }
            }
            GridRow {
                label("Seit")
                Text("\(agent.since.formatted(date: .omitted, time: .shortened)) (\(DashboardText.longAge(from: agent.since, now: now)))")
            }
            if let detail = agent.detail, !detail.isEmpty {
                GridRow {
                    label("Detail")
                    Text(detail).textSelection(.enabled)
                }
            }
        }
        .font(.callout)
        HStack(spacing: 8) {
            if agent.url != nil {
                Button("Öffnen") { open(item) }
                    .keyboardShortcut(.defaultAction)
            }
            Button("Entfernen") { dismissAgent(agent.id) }
        }
        .padding(.top, 6)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.leading)
    }
}

// MARK: - Status-Etikett

/// Eigener Status als kleines Etikett in der Titelleiste – bewusst Nebensache (PRODUCT.md).
private struct StatusChip: View {
    let name: String
    let color: StatusCore.RGBColor

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(cgColor: color.cgColor))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(name).font(.callout)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.15), in: Capsule())
        .help("Dein Status")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(name)")
    }
}
