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
            ghPathText = model.settings.ghPath
            portText = String(model.settings.port)
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
                        if let h = AppSettings.normalizedHost(newHost), !model.settings.hosts.contains(h) {
                            model.settings.hosts.append(h)
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
