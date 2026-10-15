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
    /// Ob das Board-Fenster aktuell sichtbar sein soll (siehe `updateBoardWindowVisibility`).
    @Published private(set) var boardWindowVisible = false {
        didSet { updateActivationPolicy() }
    }
    /// Ob das Dashboard-Fenster (status-display#24) offen ist.
    @Published private(set) var dashboardVisible = false {
        didSet { updateActivationPolicy() }
    }
    /// Rückgabe von IOHIDManagerOpen, falls der HID-Zugriff scheiterte (sonst nil).
    @Published private(set) var hidOpenError: IOReturn?
    /// Fehlermeldung, falls der feste Hook-Einstieg (status-display#42) nicht geschrieben werden
    /// konnte. Der App-Start läuft trotzdem weiter; die Einstellungen zeigen einen Hinweis.
    @Published private(set) var hookEntryError: String?
    @Published var settings: AppSettings {
        didSet { if settings != oldValue { settings.save(); apply(oldValue) } }
    }

    @Published private(set) var nextMeeting: MeetingInfo?
    let statusStore = StatusStore()
    private let calendarService: MeetingProvider
    private let registry = AgentRegistry(time: SystemTime())
    private let display: DisplayController
    private let transport = AKP02Transport()
    private let support = AppSupport()
    private let knownPresets = Locked<Set<String>>([])
    private var server: HTTPServer?
    private var timers: [Timer] = []
    private var renderScheduled = false
    /// Läuft gerade ein PR-Abruf? Fürs Dashboard (Fortschrittsanzeige neben „Aktualisieren“).
    @Published private(set) var prsRefreshRunning = false
    private var prsRefreshPending = false
    @Published private(set) var jira = JiraAggregator.unknown
    @Published private(set) var jiraRefreshRunning = false
    private var jiraRefreshPending = false
    private let jiraService: JiraFetcher
    private var reconnectScheduled = false
    private var lastReconnect: Date?
    /// Für `EndpointOwnership`: nur eine `endpoint.json` entfernen, die diese Instanz selbst
    /// geschrieben hat (status-display#27).
    private let ownPid = ProcessInfo.processInfo.processIdentifier
    static let reconnectMinInterval: TimeInterval = 5
    private lazy var boardWindowController: BoardWindowController = {
        let c = BoardWindowController(model: self)
        // Hier statt in `init` (status-display#36): `init` läuft mitten in SwiftUIs
        // Scene-Instanziierung und soll den Controller gar nicht erst anfassen.
        c.setAlwaysOnTop(settings.boardWindowAlwaysOnTop)
        c.onUserClosed = { [weak self] in Task { @MainActor in self?.boardWindowClosedByUser() } }
        return c
    }()
    private lazy var dashboardWindowController: DashboardWindowController = {
        let c = DashboardWindowController(model: self)
        c.onClosed = { [weak self] in Task { @MainActor in self?.dashboardVisible = false } }
        return c
    }()
    /// Vom Menüpunkt „Board-Fenster anzeigen“ gesetzt; hält das Fenster unter „Automatisch“ offen,
    /// auch wenn das Display danach verbindet (siehe `BoardWindowVisibility`).
    private var boardWindowManuallyOpened = false
    /// Zeitpunkt des App-Starts, für die Start-Karenz in `BoardWindowVisibility.shouldShow`: das
    /// Display gilt beim Start zunächst als „nicht verbunden“, bis IOKit sich meldet.
    private let startupTime = Date()

    init(calendarService: MeetingProvider = CalendarService(),
         jiraService: JiraFetcher = JiraService()) {
        self.calendarService = calendarService
        self.jiraService = jiraService
        let settings = AppSettings.load()
        self.settings = settings
        display = DisplayController(brightness: settings.brightness)
        status = statusStore.effective()
        presets = statusStore.presets
        knownPresets.value = Set(presets.map(\.id))

        // Callbacks kommen auf dem Main-Thread an; Task @MainActor macht das für den Compiler explizit.
        display.onStateChange = { [weak self] state in
            Task { @MainActor in
                self?.displayState = state
                self?.updateBoardWindowVisibility()
            }
        }
        transport.onConnect = { [weak self] writer in Task { @MainActor in self?.display.attach(writer) } }
        transport.onDisconnect = { [weak self] in Task { @MainActor in self?.display.detach() } }
        display.onWriteFailure = { [weak self] in Task { @MainActor in self?.scheduleReconnect() } }
        let hidResult = transport.start()
        if hidResult != kIOReturnSuccess { hidOpenError = hidResult }
        writeHookEntry()
        startServer()

        timers.append(Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshLocal() }
        })
        timers.append(Timer.scheduledTimer(withTimeInterval: PRAggregator.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshPRs() }
        })
        timers.append(Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshJira() }
        })
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                                          queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.display.reinitialize()
                self?.scheduleRender()
                await self?.refreshPRs()
                await self?.refreshJira()
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                               queue: .main) { [weak self, ownPid] _ in
            // Synchron: nach dieser Benachrichtigung endet der Prozess, ein Task käme nicht mehr dran.
            MainActor.assumeIsolated { self?.support.removeEndpointIfOwn(ownPid: ownPid) }
        }
        refreshLocal()
        Task { await refreshPRs() }
        Task { await refreshJira() }

        // Kein Fenster-Controller hier (status-display#36): `AppModel` ist ein `@StateObject` und wird
        // mitten in SwiftUIs Scene-Instanziierung erzeugt; ein dabei angelegtes Fenster brachte auf
        // macOS 26 den SwiftUI-Graph zum Absturz. Always-on-top setzt der Controller selbst, sobald
        // er gebraucht wird.
        // Neu auswerten, sobald die Start-Karenz vorbei ist: erst dann darf „Automatisch“ das
        // Fenster wegen eines fehlenden Displays öffnen (siehe `BoardWindowVisibility.startupGrace`).
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(BoardWindowVisibility.startupGrace))
            self?.updateBoardWindowVisibility()
        }
    }

    var hasWaitingAgent: Bool { agents.contains { $0.state == .waiting } }
    /// Fester Einstieg für die Hook-Befehle, unabhängig vom Ort der App (status-display#42).
    var hookEntryPath: String { support.hookEntryURL.path }

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

    /// Menüpunkt „Board-Fenster anzeigen“ – öffnet das Fenster sofort und hält es unter
    /// „Automatisch“ offen, bis der Nutzer es selbst schließt (siehe `BoardWindowVisibility`).
    func showBoardWindow() {
        boardWindowManuallyOpened = true
        updateBoardWindowVisibility(activate: true)
    }

    /// Menüpunkt „Dashboard öffnen“ (status-display#24). Erst das Dock-Symbol einschalten (über
    /// `dashboardVisible`), dann aktivieren – so kommt das Fenster zuverlässig nach vorne.
    func showDashboard() {
        dashboardVisible = true
        dashboardWindowController.show()
    }

    /// Die Listen des Dashboard-Fensters, aus demselben Zustand und denselben Repo-Einstellungen
    /// wie Board und Menü.
    func dashboard(now: Date) -> Dashboard {
        Dashboard.build(prs: prs, agents: agents, now: now, hosts: settings.hosts, pinned: settings.pinnedRepos,
                        hidden: settings.hiddenRepos, shown: settings.shownRepos,
                        hostDefaults: settings.hostDefaults)
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

    func refreshJira() async {
        guard settings.jiraConfigured else { return }
        guard !jiraRefreshRunning else {
            jiraRefreshPending = true
            return
        }
        jiraRefreshRunning = true
        defer { jiraRefreshRunning = false }
        repeat {
            jiraRefreshPending = false
            for server in settings.jiraServers {
                let snap = try? await jiraService.fetch(
                    domain: server.domain,
                    email: server.email,
                    token: server.token
                )
                if let snap {
                    if let error = snap.error {
                        jira.recordError(error, for: server.domain)
                    } else {
                        jira.record(snap, for: server.domain)
                    }
                }
            }
            scheduleRender()
        } while jiraRefreshPending
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

    /// Dock-Symbol, solange Dashboard- oder Board-Fenster offen ist (`DockIconPolicy`), sonst
    /// reine Menüleisten-App wie in `Info.plist` (`LSUIElement`).
    private func updateActivationPolicy() {
        let policy: NSApplication.ActivationPolicy =
            DockIconPolicy.showsDockIcon(dashboardOpen: dashboardVisible, boardWindowOpen: boardWindowVisible)
                ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }

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
        nextMeeting = calendarService.nextMeeting(now: Date())
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
                                   now: now,
                                   nextMeeting: nextMeeting)
            // Das Board-Fenster zeichnet denselben Zustand selbst in Fenstergröße (status-display#38);
            // das 1920×462-Bild geht nur noch ans AKP02.
            self.boardWindowController.update(state: state)
            let image = BoardRenderer.render(state)
            self.display.show(jpeg: PanelImage.encode(landscape: image))
        }
    }

    /// Wertet die Einstellung „Board-Fenster“ (Automatisch/Immer/Nie) gegen den aktuellen
    /// Display-Zustand aus und zeigt/versteckt das Fenster entsprechend. Wird bei jedem Ereignis
    /// aufgerufen, das das Ergebnis ändern kann (Display verbunden/getrennt, Einstellung geändert,
    /// Ablauf der Start-Karenz) – nicht als Dauer-Poller, damit ein vom Nutzer geschlossenes
    /// Fenster nicht sofort wieder aufspringt (siehe `boardWindowClosedByUser`).
    private func updateBoardWindowVisibility(activate: Bool = false) {
        let inGrace = Date().timeIntervalSince(startupTime) < BoardWindowVisibility.startupGrace
        let shouldShow = BoardWindowVisibility.shouldShow(mode: settings.boardWindowMode,
                                                           displayConnected: displayState == .connected,
                                                           inStartupGrace: inGrace,
                                                           manuallyOpened: boardWindowManuallyOpened)
        guard shouldShow else {
            if boardWindowVisible {
                boardWindowVisible = false
                boardWindowController.hide()
            }
            return
        }
        boardWindowVisible = true
        // `activate` auch aufrufen, wenn das Fenster schon sichtbar ist: ein erneuter Klick auf
        // „Board-Fenster anzeigen“ soll es dann trotzdem nach vorne holen.
        boardWindowController.show(activate: activate)
    }

    /// Der Nutzer hat das Fenster selbst geschlossen (Titelleiste/⌘W). Absichtlich ohne erneuten
    /// Aufruf von `updateBoardWindowVisibility()`: unter „Automatisch“ bei getrenntem Display wäre
    /// die Bedingung sofort wieder erfüllt, und das Fenster würde dem Nutzer vor der Nase wieder
    /// aufspringen. Es bleibt zu, bis das nächste echte Ereignis eintritt (Display verbindet/trennt
    /// erneut, Einstellung ändert sich, oder der Nutzer öffnet es wieder über den Menüpunkt).
    private func boardWindowClosedByUser() {
        boardWindowManuallyOpened = false
        boardWindowVisible = false
    }

    /// Trennt `onStateChange` der alten Instanz, bevor sie gestoppt wird: sonst kann ihr
    /// (asynchron nachlaufender) `.stopped`-Callback `serverState` überschreiben, nachdem der
    /// neue Server längst läuft oder ein Fehler dazu gesetzt wurde.
    private func stopServer() {
        server?.onStateChange = nil
        server?.stop()
        server = nil
        support.removeEndpointIfOwn(ownPid: ownPid) // bis der nächste Server `.ready` meldet, gehört der Port nicht mehr uns
    }

    /// Bei jedem Start: Der Einstieg zeigt danach auf die gerade laufende Binary, auch wenn die
    /// App seit dem letzten Start verschoben wurde. Ein Fehler hält den Start nicht auf.
    private func writeHookEntry() {
        guard let executable = Bundle.main.executablePath else {
            hookEntryError = "Pfad der App unbekannt"
            return
        }
        do {
            try support.writeHookEntry(executable: executable)
            hookEntryError = nil
        } catch {
            hookEntryError = error.localizedDescription
        }
    }

    private func startServer() {
        do {
            token = try support.loadOrCreateToken()
        } catch {
            support.removeEndpointIfOwn(ownPid: ownPid)
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
                if case .failed = state { self.support.removeEndpointIfOwn(ownPid: self.ownPid) }
                if state == .ready {
                    do {
                        try self.support.writeEndpoint(Endpoint(port: port, pid: self.ownPid))
                    } catch {
                        self.support.removeEndpointIfOwn(ownPid: self.ownPid)
                        self.serverState = .failed("endpoint.json konnte nicht geschrieben werden: \(error.localizedDescription)")
                    }
                }
            }
        }
        do {
            try s.start()
            server = s
        } catch {
            support.removeEndpointIfOwn(ownPid: ownPid)
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
        if old.jiraServers != settings.jiraServers {
            let current = Set(settings.jiraServers.map(\.domain))
            for domain in old.jiraServers.map(\.domain) where !current.contains(domain) {
                jira.remove(domain: domain)
            }
            scheduleRender()
            Task { await refreshJira() }
        }
        // Angeheftet/ausgeblendet/normal und der Host-Standard wirken nur auf die Zeilenbildung
        // aus bereits vorhandenen Snapshots (PRAggregator.zone) – dafür reicht ein Neu-Rendern,
        // kein neuer GitHub-Abruf.
        if old.pinnedRepos != settings.pinnedRepos || old.hiddenRepos != settings.hiddenRepos
            || old.shownRepos != settings.shownRepos || old.hostDefaults != settings.hostDefaults {
            scheduleRender()
        }
        if old.boardWindowMode != settings.boardWindowMode {
            // Die Einstellung kommt über ein SwiftUI-Binding (Picker in `SettingsView`). Das Fenster
            // dabei ggf. erst erzeugen und layouten, aber nicht synchron im Setter, sondern im
            // nächsten Main-Loop-Durchlauf – außerhalb jedes SwiftUI-Updates (status-display#36).
            DispatchQueue.main.async { [weak self] in self?.updateBoardWindowVisibility() }
        }
        if old.boardWindowAlwaysOnTop != settings.boardWindowAlwaysOnTop {
            boardWindowController.setAlwaysOnTop(settings.boardWindowAlwaysOnTop)
        }
    }
}
