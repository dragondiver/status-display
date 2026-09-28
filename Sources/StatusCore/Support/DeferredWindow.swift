import Foundation

/// Hält ein Fenster, das erst beim ersten Anzeigen entsteht – nie früher (status-display#36).
///
/// Hintergrund: Auf macOS 26 stürzte die App beim Start ab, weil `AppModel.init` (ein `@StateObject`,
/// also mitten in SwiftUIs Scene-Instanziierung) über ein `lazy var window` das Board-Fenster erzeugt
/// hat. Beim Erzeugen stellt `setFrameAutosaveName` die gemerkte Größe her und layoutet den
/// `NSHostingView` synchron – eine Änderung am SwiftUI-Graph mitten in dessen Update
/// (`AG::precondition_failure`).
///
/// Die Regel steckt deshalb hier, ohne AppKit und damit testbar: Nur `materialize()` erzeugt das
/// Fenster, und das rufen die Fenster-Controller ausschließlich aus `show` auf. Alles andere
/// (Verstecken, Einstellungen anwenden) geht über `ifExists` und lässt ein noch nicht erzeugtes
/// Fenster in Ruhe; die Controller merken sich solche Werte und wenden sie beim Erzeugen an.
public final class DeferredWindow<Window: AnyObject> {
    private let make: () -> Window
    /// Das Fenster, falls es schon erzeugt wurde – sonst `nil`. Der Zugriff erzeugt nichts.
    public private(set) var existing: Window?

    public init(make: @escaping () -> Window) {
        self.make = make
    }

    /// Liefert das Fenster und erzeugt es beim ersten Aufruf. Nur aus dem Anzeigen heraus aufrufen.
    public func materialize() -> Window {
        if let existing { return existing }
        let window = make()
        existing = window
        return window
    }

    /// Führt `body` nur aus, wenn das Fenster schon existiert; erzeugt es nie.
    public func ifExists(_ body: (Window) -> Void) {
        if let existing { body(existing) }
    }
}
