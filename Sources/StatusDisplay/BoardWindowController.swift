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
@MainActor
final class BoardWindowController: NSObject, NSWindowDelegate {
    /// Aufgerufen, wenn der Nutzer das Fenster selbst schließt (Fenster-Schließknopf/⌘W) – nicht,
    /// wenn `hide()` es programmatisch wegräumt.
    var onUserClosed: (() -> Void)?

    private let content = BoardWindowContent.Model()
    private lazy var window: NSWindow = makeWindow()
    private var isSettingUpClose = false

    /// Zeigt das Fenster. `activate` holt zusätzlich die App nach vorne (für den bewussten
    /// Menüpunkt-Klick); beim automatischen Erscheinen (Display getrennt) soll die App dem Nutzer
    /// nicht den Fokus wegnehmen, deshalb dort `false`.
    func show(activate: Bool) {
        if activate {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFront(nil)
        }
    }

    func hide() {
        guard window.isVisible else { return }
        isSettingUpClose = true
        window.orderOut(nil)
        isSettingUpClose = false
    }

    func update(image: CGImage?) { content.image = image }

    func setAlwaysOnTop(_ on: Bool) { window.level = on ? .floating : .normal }

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
        win.contentView = NSHostingView(rootView: BoardWindowContent(model: content))
        // Merkt Position/Größe zwischen Starts (AppKit-eigener Mechanismus, keine eigene Ablage nötig).
        win.setFrameAutosaveName("BoardWindow")
        return win
    }

    func windowWillClose(_ notification: Notification) {
        guard !isSettingUpClose else { return }
        onUserClosed?()
    }
}

/// Reine Anzeige des zuletzt gerenderten Board-Bilds – exakt das `CGImage`, das `AppModel` auch als
/// JPEG ans AKP02 schickt (kein zweites Rendern).
struct BoardWindowContent: View {
    @MainActor
    final class Model: ObservableObject {
        @Published var image: CGImage?
    }

    @ObservedObject var model: Model

    var body: some View {
        GeometryReader { _ in
            if let image = model.image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.black
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
    }
}
