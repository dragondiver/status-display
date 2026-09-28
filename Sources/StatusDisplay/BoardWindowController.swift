import AppKit
import CoreGraphics
import StatusCore

/// Eigenständiges Fenster mit dem Board (status-display#23) – für Kollegen ohne eigenes Display.
/// Bewusst ein reines `NSWindow` statt einer SwiftUI-`Window`-Scene: nur so lassen sich
/// „immer im Vordergrund“ (`window.level`) und eine gemerkte Position/Größe (`setFrameAutosaveName`)
/// direkt steuern, ohne die LSUIElement-App zu einer Dock-Präsenz zu zwingen – das hängt an der
/// Activation Policy aus `Info.plist`, nicht daran, ob ein `NSWindow` offen ist.
///
/// Seit status-display#38 zeigt das Fenster nicht mehr das herunterskalierte 1920×462-Bild des AKP02,
/// sondern zeichnet selbst in Fenstergröße (`BoardWindowView` → `BoardWindowRenderer`, feste
/// Punktgrößen, kein festes Seitenverhältnis). Das AKP02 behält seinen eigenen Renderpfad.
///
/// Klick auf die Statuszone öffnet dasselbe Status-Menü wie die Menüleiste und das Dashboard-Etikett
/// (Entscheidung Florian, 28.09.2026, status-display#33) – über `StatusMenuFactory`, damit keine
/// dritte Kopie der Einträge entsteht.
@MainActor
final class BoardWindowController: NSObject, NSWindowDelegate {
    /// Aufgerufen, wenn der Nutzer das Fenster selbst schließt (Fenster-Schließknopf/⌘W) – nicht,
    /// wenn `hide()` es programmatisch wegräumt.
    var onUserClosed: (() -> Void)?

    private let model: AppModel
    /// Letzter Board-Zustand; auch ohne Fenster gemerkt, damit ein später erzeugtes Fenster gleich
    /// den aktuellen Stand zeigt.
    private var state: BoardState?
    /// Das Fenster entsteht erst in `show` (status-display#36): `AppModel` lebt als `@StateObject`
    /// und wird mitten in SwiftUIs Scene-Instanziierung erzeugt – ein dabei angelegtes Fenster
    /// layoutet seinen `NSHostingView` synchron und bringt auf macOS 26 den SwiftUI-Graph zum Absturz.
    private lazy var window = DeferredWindow { [unowned self] in self.makeWindow() }
    /// Gemerkt, damit `setAlwaysOnTop` vor dem ersten `show` kein Fenster erzeugen muss.
    private var alwaysOnTop = false
    private var isSettingUpClose = false

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    /// Zeigt das Fenster. `activate` holt zusätzlich die App nach vorne (für den bewussten
    /// Menüpunkt-Klick); beim automatischen Erscheinen (Display getrennt) soll die App dem Nutzer
    /// nicht den Fokus wegnehmen, deshalb dort `false`.
    func show(activate: Bool) {
        let window = window.materialize()
        if activate {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFront(nil)
        }
    }

    /// Wirkt nur auf ein bereits erzeugtes Fenster; ein nie gezeigtes bleibt ungeboren.
    func hide() {
        window.ifExists { window in
            guard window.isVisible else { return }
            isSettingUpClose = true
            window.orderOut(nil)
            isSettingUpClose = false
        }
    }

    /// Merkt den Zustand und zeichnet ein vorhandenes Fenster neu; erzeugt nie eins. Aufgerufen aus
    /// `AppModel.scheduleRender`, also höchstens zweimal pro Sekunde.
    func update(state: BoardState) {
        self.state = state
        window.ifExists { ($0.contentView as? BoardWindowView)?.state = state }
    }

    /// Merkt den Wert und wendet ihn auf ein vorhandenes Fenster an; sonst erst beim Erzeugen.
    func setAlwaysOnTop(_ on: Bool) {
        alwaysOnTop = on
        window.ifExists { $0.level = Self.level(alwaysOnTop: on) }
    }

    private static func level(alwaysOnTop: Bool) -> NSWindow.Level { alwaysOnTop ? .floating : .normal }

    private func makeWindow() -> NSWindow {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 130),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        win.title = "Board"
        // Kein festes Seitenverhältnis mehr (status-display#38); die Mindestgröße hält Statusname und
        // Uhr auseinander und lässt Platz für vier Tabellenzeilen.
        win.contentMinSize = BoardWindowLayout.minimumSize
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.level = Self.level(alwaysOnTop: alwaysOnTop)
        // Merkt Position/Größe zwischen Starts (AppKit-eigener Mechanismus, keine eigene Ablage nötig).
        // Bewusst vor `contentView` (status-display#36): das Wiederherstellen der gemerkten Größe
        // passiert so, bevor die Ansicht im Fenster hängt.
        win.setFrameAutosaveName("BoardWindow")
        let view = BoardWindowView()
        view.state = state
        view.onStatusZoneClick = { [weak self] point, view in self?.openStatusMenu(at: point, in: view) }
        win.contentView = view
        return win
    }

    private func openStatusMenu(at point: CGPoint, in view: NSView) {
        let menu = StatusMenuFactory.makeStatusMenu(model: model)
        menu.popUp(positioning: nil, at: point, in: view)
    }

    func windowWillClose(_ notification: Notification) {
        guard !isSettingUpClose else { return }
        onUserClosed?()
    }
}

/// Zeichnet das Board in der Größe der Ansicht (status-display#38) – direkt per CoreGraphics in
/// den Kontext von `draw(_:)`, der auf Retina schon in Backing-Pixeln auflöst, also scharf und ohne
/// Zwischenbild. Erkennt außerdem per `BoardWindowStatusZone` (StatusCore, reine Geometrie), ob
/// Mausposition/Klick in der Statuszone liegen, zeigt dort den Zeigehand-Cursor und öffnet bei Klick
/// das Status-Menü (status-display#33). Gespiegelt, damit Ursprung oben links liegt wie im Layout.
final class BoardWindowView: NSView {
    var state: BoardState? {
        didSet { if state != oldValue { needsDisplay = true } }
    }
    var onStatusZoneClick: ((CGPoint, NSView) -> Void)?
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layerContentsRedrawPolicy = .duringViewResize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) wird nicht benutzt") }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        guard let state else {
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fill(bounds)
            return
        }
        BoardWindowRenderer.draw(state, size: bounds.size, in: ctx)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseMoved, .cursorUpdate, .inVisibleRect],
                                  owner: self, userInfo: nil)
        trackingArea = area
        addTrackingArea(area)
    }

    override func cursorUpdate(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if BoardWindowStatusZone.isStatusZone(clickPoint: point, viewSize: bounds.size) {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func mouseMoved(with event: NSEvent) {
        cursorUpdate(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard BoardWindowStatusZone.isStatusZone(clickPoint: point, viewSize: bounds.size) else {
            super.mouseDown(with: event)
            return
        }
        onStatusZoneClick?(point, self)
    }
}
