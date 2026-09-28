import CoreGraphics
import Foundation

/// Trefferprüfung „Klick im Board-Fenster → liegt in der Statuszone?“ (Entscheidung Florian,
/// 28.09.2026, status-display#33). Seit status-display#38 zeichnet das Fenster sein eigenes Layout in
/// Fenstergröße (`BoardWindowLayout`), ohne Rand-„Balken“: die Statuszone ist der linke Streifen in
/// voller Fensterhöhe, so breit wie `BoardWindowLayout.statusWidth(forWindowWidth:)`. Reine
/// Geometrie, ohne AppKit, damit sie ohne Fenster testbar ist.
public enum BoardWindowStatusZone {
    /// Das Status-Rechteck für eine Fensteransicht der Größe `viewSize` (Ursprung oben links) –
    /// dasselbe, das `BoardWindowLayout.statusRect` zeichnet.
    public static func rect(viewSize: CGSize) -> CGRect {
        guard viewSize.width > 0, viewSize.height > 0 else { return .zero }
        let width = min(BoardWindowLayout.statusWidth(forWindowWidth: viewSize.width), viewSize.width)
        return CGRect(x: 0, y: 0, width: width, height: viewSize.height)
    }

    /// Ob `clickPoint` (in den Koordinaten der Fensteransicht, Ursprung oben links) innerhalb der
    /// Statuszone liegt. Ränder zählen mit; Punkte außerhalb der Ansicht nie.
    public static func isStatusZone(clickPoint: CGPoint, viewSize: CGSize) -> Bool {
        let r = rect(viewSize: viewSize)
        guard r.width > 0, r.height > 0 else { return false }
        return clickPoint.x >= r.minX && clickPoint.x <= r.maxX && clickPoint.y >= r.minY && clickPoint.y <= r.maxY
    }
}
