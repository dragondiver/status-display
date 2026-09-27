import AppKit
import StatusCore

enum StatusIcon {
    /// Farbiger Kreis in Statusfarbe; gelber Punkt oben rechts, wenn ein Agent wartet.
    static func image(color: StatusCore.RGBColor, waiting: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor(cgColor: color.cgColor)?.setFill()
            NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 13, height: 13)).fill()
            if waiting {
                NSColor.systemYellow.setFill()
                NSBezierPath(ovalIn: NSRect(x: 11, y: 11, width: 7, height: 7)).fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
