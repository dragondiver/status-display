import AppKit
import CoreGraphics
import StatusCore
import SwiftUI

/// Eigenständiges Fenster mit exakt dem Bild, das ans AKP02 geht (status-display#23) – für Kollegen
/// ohne eigenes Display. Bewusst ein reines `NSWindow` statt einer SwiftUI-`Window`-Scene: nur so
/// lassen sich Seitenverhältnis (`contentAspectRatio`), „immer im Vordergrund“ (`window.level`) und
/// eine gemerkte Position/Größe (`setFrameAutosaveName`) direkt steuern, ohne die LSUIElement-App zu
/// einer Dock-Präsenz zu zwingen – das hängt an der Activation Policy aus `Info.plist`, nicht daran,
/// ob ein `NSWindow` offen ist.
///
/// Klick auf die Statuszone (linke 480 von 1920 px des Bilds) öffnet dasselbe Status-Menü wie die
/// Menüleiste und das Dashboard-Etikett (Entscheidung Florian, 28.09.2026, status-display#33) –
/// über `StatusMenuFactory`, damit keine dritte Kopie der Einträge entsteht.
@MainActor
final class BoardWindowController: NSObject, NSWindowDelegate {
    /// Aufgerufen, wenn der Nutzer das Fenster selbst schließt (Fenster-Schließknopf/⌘W) – nicht,
    /// wenn `hide()` es programmatisch wegräumt.
    var onUserClosed: (() -> Void)?

    private let model: AppModel
    private let content = BoardWindowContent.Model()
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

    /// Legt das Bild nur im Anzeige-Modell ab, das es auch ohne Fenster gibt; ein später erzeugtes
    /// Fenster zeigt so gleich das letzte Bild.
    func update(image: CGImage?) { content.image = image }

    /// Merkt den Wert und wendet ihn auf ein vorhandenes Fenster an; sonst erst beim Erzeugen.
    func setAlwaysOnTop(_ on: Bool) {
        alwaysOnTop = on
        window.ifExists { $0.level = Self.level(alwaysOnTop: on) }
    }

    private static func level(alwaysOnTop: Bool) -> NSWindow.Level { alwaysOnTop ? .floating : .normal }

    private func makeWindow() -> NSWindow {
        let aspectWidth: CGFloat = 1920
        let aspectHeight: CGFloat = 462
        let initialWidth: CGFloat = 960
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: initialWidth * aspectHeight / aspectWidth),
                            styleMask: [.titled, .closable, .miniaturizable, .resizable],
                            backing: .buffered, defer: false)
        win.title = "Board"
        win.contentAspectRatio = NSSize(width: aspectWidth, height: aspectHeight)
        win.minSize = NSSize(width: 320, height: 320 * aspectHeight / aspectWidth)
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.level = Self.level(alwaysOnTop: alwaysOnTop)
        // Merkt Position/Größe zwischen Starts (AppKit-eigener Mechanismus, keine eigene Ablage nötig).
        // Bewusst vor `contentView` (status-display#36): das Wiederherstellen der gemerkten Größe
        // passiert so, bevor ein `NSHostingView` im Fenster hängt, und löst kein SwiftUI-Layout aus.
        win.setFrameAutosaveName("BoardWindow")
        win.contentView = NSHostingView(rootView: BoardWindowContent(model: content, onStatusZoneClick: { [weak self] point, view in
            self?.openStatusMenu(at: point, in: view)
        }))
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

/// Reine Anzeige des zuletzt gerenderten Board-Bilds – exakt das `CGImage`, das `AppModel` auch als
/// JPEG ans AKP02 schickt (kein zweites Rendern). Ein transparenter Overlay (`BoardStatusZoneOverlay`)
/// darüber erkennt Klicks/Mausposition in der Statuszone (status-display#33).
struct BoardWindowContent: View {
    @MainActor
    final class Model: ObservableObject {
        @Published var image: CGImage?
    }

    @ObservedObject var model: Model
    let onStatusZoneClick: (CGPoint, NSView) -> Void

    var body: some View {
        GeometryReader { _ in
            ZStack {
                if let image = model.image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Color.black
                }
                BoardStatusZoneOverlayView(onClick: onStatusZoneClick)
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
    }
}

/// SwiftUI-Brücke zum AppKit-Overlay, das die eigentliche Hit-Test-/Cursor-Logik trägt.
private struct BoardStatusZoneOverlayView: NSViewRepresentable {
    let onClick: (CGPoint, NSView) -> Void

    func makeNSView(context: Context) -> BoardStatusZoneOverlay {
        let view = BoardStatusZoneOverlay()
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: BoardStatusZoneOverlay, context: Context) {
        nsView.onClick = onClick
    }
}

/// Transparente `NSView`, die über dem Board-Bild liegt: erkennt per `BoardWindowStatusZone`
/// (StatusCore, reine Geometrie), ob Mausposition/Klick in der Statuszone liegen, zeigt dort den
/// Zeigehand-Cursor und öffnet bei Klick das Status-Menü an der Klickposition. Punkte werden dafür
/// in Ursprung-oben-links umgerechnet, wie `BoardWindowStatusZone` es erwartet.
final class BoardStatusZoneOverlay: NSView {
    var onClick: ((CGPoint, NSView) -> Void)?
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseMoved, .cursorUpdate], owner: self, userInfo: nil)
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

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard BoardWindowStatusZone.isStatusZone(clickPoint: point, viewSize: bounds.size) else {
            super.mouseDown(with: event)
            return
        }
        onClick?(point, self)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Nur innerhalb der Statuszone Ereignisse abfangen – außerhalb soll das Fenster (Verschieben,
        // Größenänderung am Rand etc.) unbeeinflusst bleiben.
        let local = convert(point, from: superview)
        guard bounds.contains(local), BoardWindowStatusZone.isStatusZone(clickPoint: local, viewSize: bounds.size) else {
            return nil
        }
        return super.hitTest(point)
    }
}
