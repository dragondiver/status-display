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
        case agent(String)
        case jiraProject(String)   // projectKey
    }

    @State private var sidebar: SidebarSelection? = .section(.waiting)
    @State private var selectedItemID: String?
    @State private var now = Date()
    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        let dashboard = model.dashboard(now: now)
        let items = listItems(dashboard)
        NavigationSplitView {
            DashboardSidebar(dashboard: dashboard, jira: model.jira,
                             jiraConfigured: model.settings.jiraConfigured,
                             selection: $sidebar, now: now)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 280)
        } content: {
            if case .jiraProject(let key)? = sidebar {
                JiraDashboardList(jira: model.jira, projectKey: key,
                                  selectedIssueID: $selectedItemID)
                    .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 520)
            } else {
                DashboardList(dashboard: dashboard, selection: sidebar, items: items, now: now,
                              selectedItemID: $selectedItemID, open: open)
                    .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 520)
                    .safeAreaInset(edge: .bottom) { footer(dashboard) }
            }
        } detail: {
            if case .jiraProject? = sidebar,
               let issueID = selectedItemID,
               let issue = model.jira.allIssues.first(where: { $0.id == issueID }) {
                JiraDashboardDetail(issue: issue)
            } else if let item = items.first(where: { $0.id == selectedItemID }) {
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
                if model.settings.jiraConfigured {
                    if model.jiraRefreshRunning {
                        ProgressView().controlSize(.small)
                    }
                    Button {
                        Task { await model.refreshJira() }
                    } label: {
                        Label("Jira aktualisieren", systemImage: "arrow.clockwise.circle")
                    }
                    .help("Jira-Tickets aktualisieren")
                }
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
        case .agent(let id)?: return dashboard.agentItem(id: id).map { [$0] } ?? []
        case .jiraProject?: return []   // Jira-Inhalt direkt in content-Spalte gerendert
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
    let jira: JiraAggregator
    let jiraConfigured: Bool
    @Binding var selection: DashboardView.SidebarSelection?
    let now: Date

    var body: some View {
        List(selection: $selection) {
            // „Wartet auf dich“ bleibt oben, ohne eigene Überschrift (Entscheidung Florian,
            // 28.09.2026, status-display#39).
            Section {
                SidebarRow(title: DashboardSection.waiting.title, count: dashboard.count(.waiting),
                          waiting: dashboard.count(.waiting) > 0)
                    .tag(DashboardView.SidebarSelection.section(.waiting))
            }
            Section("Pull Requests") {
                ForEach([DashboardSection.codeOwner, .mine, .approved]) { section in
                    SidebarRow(title: section.title, count: dashboard.count(section), waiting: false)
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
            Section("Agenten") {
                if dashboard.agents.isEmpty {
                    Text(DashboardText.noActiveAgents)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(dashboard.agents) { item in
                        AgentSidebarRow(item: item, now: now)
                            .tag(DashboardView.SidebarSelection.agent(item.id))
                    }
                }
            }
            let jiraGroups = jira.grouped()
            let jiraErrors = jira.errorLines
            if jiraConfigured, !jiraGroups.isEmpty || !jiraErrors.isEmpty {
                Section("Jira") {
                    ForEach(jiraGroups, id: \.project) { group in
                        SidebarRow(title: group.projectName,
                                   count: group.sprints.flatMap(\.issues).count,
                                   waiting: false)
                            .tag(DashboardView.SidebarSelection.jiraProject(group.project))
                    }
                    ForEach(jiraErrors, id: \.self) { error in
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

/// Eine Zeile je Agent im Abschnitt „Agenten“ der Seitenleiste (status-display#39): Zustandspunkt
/// und Zustandstext statt eines Sammel-Eintrags mit Zähler.
private struct AgentSidebarRow: View {
    let item: DashboardItem
    let now: Date

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(markColor)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(name).lineLimit(1)
            Spacer(minLength: 4)
            Text(stateText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var markColor: Color {
        switch item.markKind {
        case .waiting: return .orange
        case .error: return .red
        case .neutral: return Color.secondary.opacity(0.5)
        }
    }

    private var name: String {
        if case .agent(let agent) = item.subject { return agent.name }
        return ""
    }

    private var stateText: String {
        guard case .agent(let agent) = item.subject else { return "" }
        return BoardText.agentLabel(agent, now: now)
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
        switch item.markKind {
        case .waiting: return .orange
        case .error: return .red
        case .neutral: return Color.secondary.opacity(0.5)
        }
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
        switch DashboardText.ciSymbol(pr) {
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red).accessibilityHidden(true)
        case .passed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityHidden(true)
        case .none:
            EmptyView()
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

// MARK: - Jira

private struct JiraDashboardList: View {
    let jira: JiraAggregator
    let projectKey: String
    @Binding var selectedIssueID: String?

    var body: some View {
        let group = jira.grouped().first { $0.project == projectKey }
        let errors = jira.snapshots.values.compactMap(\.error)
        if let error = errors.first, group == nil {
            Text("Fehler: \(error)")
                .foregroundStyle(.secondary)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let group {
            List(selection: $selectedIssueID) {
                ForEach(group.sprints, id: \.sprint) { sprintGroup in
                    Section(sprintGroup.sprint ?? "Kein Sprint") {
                        ForEach(sprintGroup.issues) { issue in
                            JiraIssueRow(issue: issue).tag(issue.id)
                        }
                    }
                }
            }
        } else {
            Text("Keine Tickets.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct JiraIssueRow: View {
    let issue: JiraIssue

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(priorityColor(issue.priorityName))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.summary)
                    .lineLimit(1)
                Text("\(issue.key) · \(issue.statusName)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct JiraDashboardDetail: View {
    let issue: JiraIssue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(issue.projectName) · \(issue.key)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(issue.summary)
                        .font(.title3.weight(.semibold))
                        .textSelection(.enabled)
                }
                HStack(spacing: 6) {
                    JiraStatusBadge(name: issue.statusName)
                    if let p = issue.priorityName {
                        JiraStatusBadge(name: p, color: priorityColor(p))
                    }
                }
                if issue.sprintName != nil {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                        if let sprint = issue.sprintName {
                            GridRow {
                                jiraLabel("Sprint")
                                Text(sprint)
                            }
                        }
                    }
                    .font(.callout)
                }
                Button("In Jira öffnen") { NSWorkspace.shared.open(issue.url) }
                    .keyboardShortcut(.defaultAction)
                    .padding(.top, 4)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func jiraLabel(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.leading)
    }
}

private struct JiraStatusBadge: View {
    let name: String
    var color: Color = .secondary

    var body: some View {
        Text(name)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(color == .secondary ? .secondary : color)
    }
}

private func priorityColor(_ priority: String?) -> Color {
    switch priority?.lowercased() {
    case "blocker", "critical": return .red
    case "high":                return .orange
    case "medium":              return .accentColor
    default:                    return Color.secondary.opacity(0.5)
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
