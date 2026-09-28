import AppKit
import IOKit
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
    /// Rückgabe von IOHIDManagerOpen, falls der HID-Zugriff scheiterte (sonst nil).
    @Published private(set) var hidOpenError: IOReturn?
    @Published var settings: AppSettings {
        didSet { if settings != oldValue { settings.save(); apply(oldValue) } }
    }

    let statusStore = StatusStore()
    private let registry = AgentRegistry(time: SystemTime())
    private let display: DisplayController
    private let transport = AKP02Transport()
    private let support = AppSupport()
    private let knownPresets = Locked<Set<String>>([])
    private var server: HTTPServer?
    private var timers: [Timer] = []
    private var renderScheduled = false
    private var prsRefreshRunning = false
    private var prsRefreshPending = false
    private var reconnectScheduled = false
    private var lastReconnect: Date?
    static let reconnectMinInterval: TimeInterval = 5

    init() {
        let settings = AppSettings.load()
        self.settings = settings
        display = DisplayController(brightness: settings.brightness)
        status = statusStore.effective()
        presets = statusStore.presets
        knownPresets.value = Set(presets.map(\.id))

        // Callbacks kommen auf dem Main-Thread an; Task @MainActor macht das für den Compiler explizit.
        display.onStateChange = { [weak self] state in Task { @MainActor in self?.displayState = state } }
        transport.onConnect = { [weak self] writer in Task { @MainActor in self?.display.attach(writer) } }
        transport.onDisconnect = { [weak self] in Task { @MainActor in self?.display.detach() } }
        display.onWriteFailure = { [weak self] in Task { @MainActor in self?.scheduleReconnect() } }
        let hidResult = transport.start()
        if hidResult != kIOReturnSuccess { hidOpenError = hidResult }
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
                await self?.refreshPRs()
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            // Synchron: nach dieser Benachrichtigung endet der Prozess, ein Task käme nicht mehr dran.
            MainActor.assumeIsolated { self?.support.removeEndpoint() }
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

    /// Zwischengespeicherte Repo-Liste eines Hosts (ohne Netzwerkzugriff), für den Reiter „Repos“.
    func cachedRepoCatalog(host: String) -> RepoCache? {
        support.readRepoCache(host: host)
    }

    /// Lädt die Repo-Liste eines Hosts frisch von GitHub (seitenweise, siehe `RepoCatalogService`)
    /// und schreibt sie in den Cache. Wird nur auf Knopfdruck („Repos neu laden“) aufgerufen, nicht
    /// bei jedem Öffnen der Einstellungen.
    func reloadRepoCatalog(host: String) async -> Result<RepoCache, GitHubError> {
        let service = RepoCatalogService(tokens: GHCLITokenProvider(customPath: settings.ghPath))
        do {
            let repos = try await service.fetch(host: host)
            let cache = RepoCache(repos: repos, fetchedAt: Date())
            try? support.writeRepoCache(cache, host: host)
            return .success(cache)
        } catch let error as GitHubError {
            return .failure(error)
        } catch {
            return .failure(.http(0))
        }
    }

    func regenerateToken() {
        // Erst das neue Token erzeugen; der alte Server (der mit dem alten Token noch funktioniert)
        // wird nur bei Erfolg gestoppt. Sonst würde ein Fehlschlag den Server tot zurücklassen.
        do {
            _ = try support.regenerateToken()
        } catch {
            serverState = .failed("Token konnte nicht erzeugt werden: \(error.localizedDescription)")
            return
        }
        stopServer()
        startServer()
    }

    /// Single-flight: läuft bereits ein Refresh, wird nur vorgemerkt statt eines zweiten,
    /// parallelen Laufs (der sonst ältere Ergebnisse über neuere schreiben könnte).
    func refreshPRs() async {
        guard !prsRefreshRunning else {
            prsRefreshPending = true
            return
        }
        prsRefreshRunning = true
        defer { prsRefreshRunning = false }
        repeat {
            prsRefreshPending = false
            await runPRRefresh()
        } while prsRefreshPending
    }

    private func runPRRefresh() async {
        // Hosts und PRService werden hier, zu Laufbeginn, aus den aktuellen Einstellungen gebaut,
        // damit ein während des Laufs geänderter gh-Pfad/Host-Satz nicht mit veralteten Werten arbeitet.
        let hosts = settings.hosts
        let service = PRService(tokens: GHCLITokenProvider(customPath: settings.ghPath))
        for host in hosts {
            do {
                let snapshot = try await service.fetch(host: host)
                guard settings.hosts.contains(host) else { continue }
                prs.record(snapshot)
            } catch let error as GitHubError {
                guard settings.hosts.contains(host) else { continue }
                prs.record(error, host: host)
            } catch {
                guard settings.hosts.contains(host) else { continue }
                prs.record(.http(0), host: host)
            }
        }
        prs.retain(hosts: settings.hosts)
        scheduleRender()
    }

    // MARK: Intern

    /// Nach einem Schreibfehler neu anbinden, aber höchstens alle 5 s: scheitert das wieder
    /// angebundene Gerät sofort erneut, entsteht so keine enge Schleife.
    private func scheduleReconnect() {
        guard !reconnectScheduled else { return }
        reconnectScheduled = true
        let wait = lastReconnect.map { max(0, Self.reconnectMinInterval - Date().timeIntervalSince($0)) } ?? 0
        Task { @MainActor [weak self] in
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard let self else { return }
            self.reconnectScheduled = false
            self.lastReconnect = Date()
            self.transport.reconnect()
        }
    }

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
                                   statusSince: status.since, agents: agents,
                                   prs: prs.zone(now: now, hosts: settings.hosts,
                                                pinned: settings.pinnedRepos, hidden: settings.hiddenRepos,
                                                shown: settings.shownRepos, hostDefaults: settings.hostDefaults),
                                   now: now)
            display.show(jpeg: PanelImage.encode(landscape: BoardRenderer.render(state)))
        }
    }

    /// Trennt `onStateChange` der alten Instanz, bevor sie gestoppt wird: sonst kann ihr
    /// (asynchron nachlaufender) `.stopped`-Callback `serverState` überschreiben, nachdem der
    /// neue Server längst läuft oder ein Fehler dazu gesetzt wurde.
    private func stopServer() {
        server?.onStateChange = nil
        server?.stop()
        server = nil
        support.removeEndpoint() // bis der nächste Server `.ready` meldet, gehört der Port nicht mehr uns
    }

    private func startServer() {
        do {
            token = try support.loadOrCreateToken()
        } catch {
            support.removeEndpoint()
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
        s.onStateChange = { [weak self, weak s] state in
            Task { @MainActor in
                // War der Task schon eingereiht, als `stopServer()` diesen Server ersetzt hat,
                // meldet er sich hier trotzdem noch: `self.server` zeigt dann nicht mehr auf `s`,
                // und die veraltete Meldung darf `serverState`/`endpoint.json` nicht mehr anfassen.
                guard let self, let s, self.server === s else { return }
                self.serverState = state
                if case .failed = state { self.support.removeEndpoint() }
                if state == .ready {
                    do {
                        try self.support.writeEndpoint(Endpoint(port: port))
                    } catch {
                        self.support.removeEndpoint()
                        self.serverState = .failed("endpoint.json konnte nicht geschrieben werden: \(error.localizedDescription)")
                    }
                }
            }
        }
        do {
            try s.start()
            server = s
        } catch {
            support.removeEndpoint()
            serverState = .failed(error.localizedDescription)
        }
    }

    private func apply(_ old: AppSettings) {
        if old.port != settings.port {
            stopServer()
            startServer()
        }
        if old.brightness != settings.brightness { display.setBrightness(settings.brightness) }
        if old.hosts != settings.hosts || old.ghPath != settings.ghPath {
            Task { await refreshPRs() }
        }
        // Angeheftet/ausgeblendet/normal und der Host-Standard wirken nur auf die Zeilenbildung
        // aus bereits vorhandenen Snapshots (PRAggregator.zone) – dafür reicht ein Neu-Rendern,
        // kein neuer GitHub-Abruf.
        if old.pinnedRepos != settings.pinnedRepos || old.hiddenRepos != settings.hiddenRepos
            || old.shownRepos != settings.shownRepos || old.hostDefaults != settings.hostDefaults {
            scheduleRender()
        }
    }
}
