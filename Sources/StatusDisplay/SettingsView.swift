import AppKit
import ServiceManagement
import StatusCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var newHost = ""
    @State private var presets: [StatusPreset] = []
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var ghPathText = ""
    @State private var portText = ""
    @State private var repoHost = ""
    @State private var repoSearch = ""
    @State private var repoCatalog: [String] = []
    @State private var repoCatalogFetchedAt: Date?
    @State private var repoLoading = false
    @State private var repoError: String?
    /// Sammelaktion im Reiter „Repos“, zwischen Klick und Bestätigung im `confirmationDialog`.
    @State private var pendingBulkAction: (state: RepoState, names: [String])?

    var body: some View {
        TabView {
            general.tabItem { Text("Allgemein") }
            statusTab.tabItem { Text("Status") }
            agentsTab.tabItem { Text("Agenten") }
            reposTab.tabItem { Text("Repos") }
            jiraTab.tabItem { Text("Jira") }
        }
        .frame(width: 620, height: 520)
        .padding()
        .onAppear {
            presets = model.presets
            ghPathText = model.settings.ghPath
            portText = String(model.settings.port)
            if repoHost.isEmpty { repoHost = model.settings.hosts.first ?? "" }
            loadCachedRepos()
            NSApp.activate()
        }
    }

    /// Nur gültige Ports (1024…65535) werden übernommen; sonst bleibt der bisherige Wert bestehen
    /// und das Feld wird auf ihn zurückgesetzt.
    private func applyPort() {
        guard let value = UInt16(portText), (1024...65535).contains(value) else {
            portText = String(model.settings.port)
            return
        }
        model.settings.port = value
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
                        if let h = AppSettings.normalizedHost(newHost) {
                            model.settings.addHost(h)
                        }
                        newHost = ""
                    }
                }
                TextField("Pfad zu gh (leer = automatisch)", text: $ghPathText)
                    .onSubmit { model.settings.ghPath = ghPathText }
                    .onDisappear { model.settings.ghPath = ghPathText }
            }
            Section("Display") {
                Slider(value: Binding(get: { Double(model.settings.brightness) },
                                      set: { model.settings.brightness = Int($0) }), in: 0...100, step: 5) {
                    Text("Helligkeit \(model.settings.brightness) %")
                }
            }
            Section("Board-Fenster") {
                Picker("Anzeigen", selection: Binding(get: { model.settings.boardWindowMode },
                                                       set: { model.settings.boardWindowMode = $0 })) {
                    Text("Automatisch").tag(BoardWindowMode.automatic)
                    Text("Immer").tag(BoardWindowMode.always)
                    Text("Nie").tag(BoardWindowMode.never)
                }
                Text("Automatisch: sichtbar, solange kein AKP02 verbunden ist.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Immer im Vordergrund", isOn: Binding(get: { model.settings.boardWindowAlwaysOnTop },
                                                              set: { model.settings.boardWindowAlwaysOnTop = $0 }))
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
                        .disabled(presets.count <= 1 || preset.id == StatusPreset.availableID)
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
                    TextField("47615", text: $portText)
                        .frame(width: 90)
                        .onSubmit { applyPort() }
                        .onDisappear { applyPort() }
                    if case .failed(let m) = model.serverState { Text(m).foregroundStyle(.red) }
                }
                HStack {
                    Text("Token: \(String(model.token.prefix(8)))…")
                    Button("Neu erzeugen") { model.regenerateToken() }
                }
                if let hookEntryError = model.hookEntryError {
                    Text("Hook-Einstieg konnte nicht geschrieben werden: \(hookEntryError)")
                        .foregroundStyle(.red)
                }
                snippet("Claude Code – in ~/.claude/settings.json einfügen",
                        HookSnippets.hooksJSON(entry: model.hookEntryPath, source: "claude-code",
                                               events: HookSnippets.claudeEvents))
                snippet("Codex – ~/.codex/hooks.json",
                        HookSnippets.hooksJSON(entry: model.hookEntryPath, source: "codex",
                                               events: HookSnippets.codexEvents))
                snippet("Codex – ~/.codex/config.toml (falls nötig)", HookSnippets.codexFeatureFlag)
                snippet("MCP (Copilot u. a.) – Eintrag in der MCP-Konfiguration",
                        HookSnippets.mcpJSON(port: model.settings.port, token: model.token))
            }
        }
    }

    // MARK: Repos

    private var reposTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Host")
                Picker("", selection: $repoHost) {
                    ForEach(model.settings.hosts, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 220)
                .onChange(of: repoHost) { _, _ in loadCachedRepos() }
                Spacer()
                if let repoCatalogFetchedAt {
                    Text("Stand \(repoCatalogFetchedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button(repoLoading ? "Lädt …" : "Repos neu laden") { Task { await reloadRepos() } }
                    .disabled(repoLoading || repoHost.isEmpty)
            }

            if let repoError {
                Text(repoError).foregroundStyle(.red).font(.caption)
            }

            // Standard für Repos ohne eigenen Eintrag in pinnedRepos/hiddenRepos/shownRepos
            // (Entscheidung Florian, 28.09.2026, status-display#19): github.com normal, andere
            // Hosts ausgeblendet – hier pro Host umschaltbar.
            HStack {
                Text("Nicht eingestellte Repos:").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: Binding(
                    get: { hostDefault },
                    set: { model.settings.setHostDefault($0, for: repoHost) }
                )) {
                    Text("normal").tag(RepoDefault.normal)
                    Text("ausgeblendet").tag(RepoDefault.hidden)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220)
                .disabled(repoHost.isEmpty)
            }

            if !pinnedForHost.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Angeheftet").font(.headline)
                    ForEach(pinnedForHost, id: \.self) { name in
                        repoRow(name: name)
                    }
                }
                Divider()
            }

            TextField("Suche (owner/repo)", text: $repoSearch)

            let filtered = RepoSelection.filter(repoCatalog, query: repoSearch)
            if filtered.count > RepoSelection.displayLimit {
                Text("Zeige die ersten \(RepoSelection.displayLimit) von \(filtered.count) Treffern – Suche eingrenzen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text("Alle \(filtered.count) Treffer:").font(.caption).foregroundStyle(.secondary)
                ForEach([RepoState.normal, .pinned, .hidden], id: \.self) { state in
                    Button(label(for: state)) { pendingBulkAction = (state, filtered) }
                }
            }
            .disabled(filtered.isEmpty)

            List(filtered.prefix(RepoSelection.displayLimit), id: \.self) { name in
                repoRow(name: name)
            }
        }
        .padding()
        .confirmationDialog(bulkConfirmationTitle, isPresented: bulkConfirmationPresented, titleVisibility: .visible) {
            Button(bulkConfirmationTitle) {
                guard let pendingBulkAction else { return }
                applyBulk(pendingBulkAction.state, to: pendingBulkAction.names)
                self.pendingBulkAction = nil
            }
            Button("Abbrechen", role: .cancel) { pendingBulkAction = nil }
        }
    }

    /// Angeheftete Repos des gewählten Hosts, unabhängig von der Suche, damit man sie ohne
    /// Suchen findet.
    private var pinnedForHost: [String] {
        model.settings.pinnedRepos.compactMap { RepoSelection.repository(forKey: $0, host: repoHost) }.sorted()
    }

    private var hostDefault: RepoDefault {
        RepoSelection.hostDefault(for: repoHost, hostDefaults: model.settings.hostDefaults)
    }

    private func label(for state: RepoState) -> String {
        switch state {
        case .normal: return "normal"
        case .pinned: return "anheften"
        case .hidden: return "ausblenden"
        }
    }

    private var bulkConfirmationTitle: String {
        guard let pendingBulkAction else { return "" }
        return "\(pendingBulkAction.names.count) Repos auf „\(label(for: pendingBulkAction.state))“ setzen?"
    }

    private var bulkConfirmationPresented: Binding<Bool> {
        Binding(get: { pendingBulkAction != nil }, set: { if !$0 { pendingBulkAction = nil } })
    }

    private func applyBulk(_ state: RepoState, to names: [String]) {
        let updated = RepoSelection.setStateForAll(state, names: names, host: repoHost,
                                                    pinned: model.settings.pinnedRepos,
                                                    hidden: model.settings.hiddenRepos,
                                                    shown: model.settings.shownRepos,
                                                    hostDefaults: model.settings.hostDefaults)
        model.settings.pinnedRepos = updated.pinned
        model.settings.hiddenRepos = updated.hidden
        model.settings.shownRepos = updated.shown
    }

    private func repoRow(name: String) -> some View {
        let key = "\(repoHost)/\(name)"
        return HStack {
            Text(name)
            Spacer()
            Picker("", selection: Binding(
                get: { RepoSelection.state(for: key, host: repoHost, pinned: model.settings.pinnedRepos,
                                           hidden: model.settings.hiddenRepos, shown: model.settings.shownRepos,
                                           hostDefaults: model.settings.hostDefaults) },
                set: { newState in
                    let updated = RepoSelection.setState(newState, for: key, host: repoHost,
                                                         pinned: model.settings.pinnedRepos,
                                                         hidden: model.settings.hiddenRepos,
                                                         shown: model.settings.shownRepos,
                                                         hostDefaults: model.settings.hostDefaults)
                    model.settings.pinnedRepos = updated.pinned
                    model.settings.hiddenRepos = updated.hidden
                    model.settings.shownRepos = updated.shown
                }
            )) {
                Text("normal").tag(RepoState.normal)
                Text("angeheftet").tag(RepoState.pinned)
                Text("ausgeblendet").tag(RepoState.hidden)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 260)
        }
    }

    private func loadCachedRepos() {
        repoError = nil
        guard !repoHost.isEmpty, let cache = model.cachedRepoCatalog(host: repoHost) else {
            repoCatalog = []
            repoCatalogFetchedAt = nil
            return
        }
        repoCatalog = cache.repos
        repoCatalogFetchedAt = cache.fetchedAt
    }

    private func reloadRepos() async {
        guard !repoHost.isEmpty else { return }
        repoLoading = true
        repoError = nil
        let result = await model.reloadRepoCatalog(host: repoHost)
        repoLoading = false
        switch result {
        case .success(let cache):
            repoCatalog = cache.repos
            repoCatalogFetchedAt = cache.fetchedAt
        case .failure(let error):
            repoError = error.message
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

    // MARK: Jira

    @State private var newJiraDomain = ""
    @State private var newJiraEmail  = ""
    @State private var newJiraToken  = ""

    private var jiraTab: some View {
        Form {
            Section("Jira Cloud Server") {
                if model.settings.jiraServers.isEmpty {
                    Text("Kein Server konfiguriert.").foregroundStyle(.secondary)
                } else {
                    ForEach(model.settings.jiraServers) { server in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(server.domain)
                                Text(server.email).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Entfernen") {
                                model.settings.jiraServers.removeAll { $0.id == server.id }
                            }
                        }
                    }
                }
            }
            Section("Server hinzufügen") {
                TextField("domain.atlassian.net", text: $newJiraDomain).autocorrectionDisabled()
                TextField("vorname.nachname@firma.de", text: $newJiraEmail).autocorrectionDisabled()
                SecureField("API-Token", text: $newJiraToken)
                Button("Hinzufügen") {
                    let domain = JiraService.normalizedDomain(newJiraDomain)
                    // Eingefügte Token bringen oft einen Zeilenumbruch mit – das gäbe ein stilles HTTP 401.
                    let email = newJiraEmail.trimmingCharacters(in: .whitespacesAndNewlines)
                    let token = newJiraToken.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !domain.isEmpty, !email.isEmpty, !token.isEmpty else { return }
                    guard !model.settings.jiraServers.contains(where: { $0.domain == domain }) else { return }
                    model.settings.jiraServers.append(
                        JiraServer(domain: domain, email: email, token: token))
                    newJiraDomain = ""; newJiraEmail = ""; newJiraToken = ""
                }
                .disabled(newJiraDomain.isEmpty || newJiraEmail.isEmpty || newJiraToken.isEmpty)
            }
            Section {
                Link("API-Token erstellen",
                     destination: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!)
            }
        }
    }
}
