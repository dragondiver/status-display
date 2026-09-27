import AppKit
import SwiftUI

/// Öffnet die Einstellungen und holt das Fenster sichtbar nach vorne.
/// Eine Menüleisten-App (LSUIElement) wird von `SettingsLink` nicht aktiviert: Das Fenster
/// öffnet dann auf irgendeinem Bildschirm, und ein zweiter Klick holt ein offenes Fenster nicht zurück.
struct SettingsOpener: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Einstellungen …") {
            openSettings()
            // Das Fenster existiert erst nach dem nächsten Runloop-Durchgang.
            DispatchQueue.main.async { Self.bringToFront() }
        }
    }

    @MainActor
    static func bringToFront() {
        NSApp.activate()
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("Settings") == true }) else {
            return
        }
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
           window.screen != screen {
            let visible = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: visible.midX - window.frame.width / 2,
                                          y: visible.midY - window.frame.height / 2))
        }
        window.makeKeyAndOrderFront(nil)
    }
}
