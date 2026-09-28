import AppKit
import StatusCore
import SwiftUI

/// Das Dashboard-Fenster (status-display#24). Wie das Board-Fenster (#23) ein eigenes `NSWindow`
/// statt einer SwiftUI-`Window`-Scene: Eine Scene könnte die LSUIElement-App beim Start ungefragt
/// öffnen, und das Schließen ist über `NSWindowDelegate` eindeutig zu erkennen – das braucht die
/// Dock-Symbol-Regel (`DockIconPolicy`). Die SwiftUI-Toolbar gelangt über
/// `NSHostingController.sceneBridgingOptions` in die Titelleiste.
@MainActor
final class DashboardWindowController: NSObject, NSWindowDelegate {
    /// Aufgerufen, wenn der Nutzer das Fenster schließt.
    var onClosed: (() -> Void)?

    private let model: AppModel
    /// Wie beim Board-Fenster erst in `show` erzeugt (status-display#36), nie als Nebenwirkung.
    private lazy var window = DeferredWindow { [unowned self] in self.makeWindow() }

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    /// Öffnet das Fenster (oder holt ein offenes nach vorne) und aktiviert die App.
    func show() {
        let window = window.materialize()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let host = NSHostingController(rootView: DashboardView(model: model))
        host.sceneBridgingOptions = [.toolbars]
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 620),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                           backing: .buffered, defer: false)
        win.contentViewController = host
        win.title = "Dashboard"
        win.toolbarStyle = .unified
        win.minSize = NSSize(width: 760, height: 420)
        win.setContentSize(NSSize(width: 1000, height: 620))
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.center()
        // Merkt Position/Größe zwischen Starts, wie beim Board-Fenster.
        win.setFrameAutosaveName("DashboardWindow")
        return win
    }

    func windowWillClose(_ notification: Notification) {
        onClosed?()
    }
}
