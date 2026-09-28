import CoreGraphics
import Foundation

/// Trefferprüfung „Klick im Board-Fenster → liegt in der Statuszone?“ (Entscheidung Florian,
/// 28.09.2026, status-display#33): das Bild wird per `aspectRatio(contentMode: .fit)` mittig ins
/// Fenster skaliert, die Statuszone ist der linke Bereich 0–480 von 1920 px Bildbreite. Reine
/// Geometrie, ohne AppKit, damit sie ohne Fenster testbar ist.
public enum BoardWindowStatusZone {
    /// Bildmaße wie `BoardRenderer.width`/`.height` – hier als eigene Konstanten, damit diese Datei
    /// ohne Abhängigkeit auf den Renderer testbar bleibt.
    public static let imageWidth: CGFloat = 1920
    public static let imageHeight: CGFloat = 462
    /// Breite der Statuszone im Bild (deckt sich mit dem Status-Rechteck in `BoardRenderer`).
    public static let zoneWidth: CGFloat = 480

    /// Ob `clickPoint` (in den Koordinaten der Fensteransicht, Ursprung oben links) innerhalb der
    /// Statuszone des – gemäß `viewSize` mittig skalierten und einpassten – Board-Bilds liegt.
    /// Punkte in den Rand-„Balken“ neben/über dem Bild (falls `viewSize` nicht im Seitenverhältnis
    /// des Bilds ist) zählen nicht als Treffer.
    public static func isStatusZone(clickPoint: CGPoint, viewSize: CGSize) -> Bool {
        guard viewSize.width > 0, viewSize.height > 0 else { return false }
        let scale = min(viewSize.width / imageWidth, viewSize.height / imageHeight)
        guard scale > 0 else { return false }
        let renderedWidth = imageWidth * scale
        let renderedHeight = imageHeight * scale
        let originX = (viewSize.width - renderedWidth) / 2
        let originY = (viewSize.height - renderedHeight) / 2
        let localX = clickPoint.x - originX
        let localY = clickPoint.y - originY
        guard localX >= 0, localX <= renderedWidth, localY >= 0, localY <= renderedHeight else { return false }
        return localX <= zoneWidth * scale
    }
}
