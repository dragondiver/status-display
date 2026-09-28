import Foundation

/// Einstellung „Board-Fenster“ (status-display#23): steuert, ob ein zusätzliches Fenster mit dem
/// exakt gleichen Board-Bild angezeigt wird, das sonst nur ans AKP02 geht – für Kollegen ohne eigenes
/// Display.
public enum BoardWindowMode: String, Codable, Equatable, CaseIterable {
    /// Sichtbar, solange kein AKP02 verbunden ist (Standard).
    case automatic
    case always
    case never
}

/// Reine Entscheidungslogik „Board-Fenster zeigen?“ aus Einstellung × Display-Zustand ×
/// Nutzer-Aktion – ohne AppKit, damit sie ohne Fenster testbar ist (Entscheidung Florian,
/// 28.09.2026, status-display#23).
public enum BoardWindowVisibility {
    /// Karenzzeit nach App-Start, bevor `.automatic` das Fenster öffnen darf: Der Display-Zustand
    /// ist beim Start zunächst „nicht verbunden“, bis IOKit sich meldet (siehe `AppModel.init`).
    /// Ohne Karenz würde das Fenster bei jedem Start kurz aufblitzen, auch wenn ein AKP02 verbunden
    /// ist. 2 s sind deutlich mehr, als IOKit für die erste Rückmeldung braucht, aber kurz genug,
    /// dass ein tatsächlich fehlendes Display das Fenster ohne spürbare Verzögerung bekommt.
    public static let startupGrace: TimeInterval = 2

    /// Ob das Board-Fenster sichtbar sein soll.
    ///
    /// - `.always`/`.never` sind absolut und ignorieren alles andere.
    /// - Unter `.automatic` gilt: ein vom Nutzer über den Menüpunkt geöffnetes Fenster
    ///   (`manuallyOpened`) bleibt offen, auch wenn das Display danach verbindet – „Automatisch“
    ///   schließt es nicht selbstständig weg, solange der Nutzer es offen hat. Ohne manuelles Öffnen
    ///   ist das Fenster genau dann sichtbar, wenn das Display nicht verbunden ist und die
    ///   Start-Karenz (`startupGrace`) vorbei ist.
    public static func shouldShow(mode: BoardWindowMode, displayConnected: Bool, inStartupGrace: Bool,
                                   manuallyOpened: Bool) -> Bool {
        switch mode {
        case .always: return true
        case .never: return false
        case .automatic:
            if manuallyOpened { return true }
            if inStartupGrace { return false }
            return !displayConnected
        }
    }
}
