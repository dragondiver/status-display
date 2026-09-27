import CoreGraphics
import CoreText
import Foundation

/// Zeichnet das Board als 1920×462-Querformat. Koordinaten von oben links.
public enum BoardRenderer {
    public static let width = 1920
    public static let height = 462

    static let background = RGBColor(hex: "#121216")!
    static let separator = RGBColor(hex: "#2A2A30")!
    static let muted = RGBColor(hex: "#8C8C96")!
    static let white = RGBColor(hex: "#FFFFFF")!
    static let green = RGBColor(hex: "#5AC878")!
    static let amber = RGBColor(hex: "#F0B43C")!
    static let red = RGBColor(hex: "#E52424")!
    static let grey = RGBColor(hex: "#6B6F76")!

    public static func render(_ s: BoardState) -> CGImage {
        let ctx = PanelImage.makeContext(width: width, height: height)
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        fill(ctx, CGRect(x: 0, y: 0, width: width, height: height), background)
        drawStatus(ctx, s)
        drawAgents(ctx, s)
        drawPRs(ctx, s)
        drawClock(ctx, s)
        for x in [1240, 1660] { fill(ctx, CGRect(x: x - 1, y: 40, width: 2, height: 382), separator) }
        return ctx.makeImage()!
    }

    // MARK: Zonen

    private static func drawStatus(_ ctx: CGContext, _ s: BoardState) {
        fill(ctx, CGRect(x: 0, y: 0, width: 480, height: height), s.statusColor)
        let words = s.statusName.uppercased().split(separator: " ").map(String.init).prefix(2)
        let size = words.map { BoardText.statusFontSize(for: $0, width: 420, maxSize: 92) }.min() ?? 92
        var baseline: CGFloat = words.count > 1 ? 170 : 230
        for w in words {
            text(ctx, w, x: 40, baseline: baseline, size: size, bold: true, color: white)
            baseline += size + 8
        }
        text(ctx, BoardText.since(s.statusSince, now: s.now), x: 40, baseline: 420, size: 38,
             color: white.withAlpha(0.8))
    }

    private static func drawAgents(_ ctx: CGContext, _ s: BoardState) {
        let x0: CGFloat = 520
        text(ctx, "AGENTEN", x: x0, baseline: 70, size: 34, color: muted)
        let (rows, more) = BoardText.visibleAgents(s.agents)
        if rows.isEmpty {
            text(ctx, "keine aktiven Agenten", x: x0, baseline: 170, size: 40, color: muted)
        }
        var baseline: CGFloat = 150
        for a in rows {
            let color = stateColor(a)
            if a.state == .waiting {
                fill(ctx, CGRect(x: 500, y: baseline - 54, width: 730, height: 74), amber.withAlpha(0.22))
            }
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: CGRect(x: x0, y: baseline - 32, width: 26, height: 26))
            // Name bis x≈940, Label ab 960 bis ≈1200: bleibt links der Trennlinie bei 1240.
            text(ctx, BoardText.truncate(a.name, max: 16), x: x0 + 50, baseline: baseline, size: 44,
                 color: a.isStale ? grey : white)
            text(ctx, BoardText.agentLabel(a, now: s.now), x: x0 + 440, baseline: baseline, size: 34, color: color)
            baseline += 80
        }
        if more > 0 {
            text(ctx, "+\(more) weitere", x: x0 + 50, baseline: baseline, size: 36, color: muted)
        }
    }

    private static func drawPRs(_ ctx: CGContext, _ s: BoardState) {
        let x0: CGFloat = 1270
        let z = s.prs
        if z.ciFailing > 0 && !z.isStale {
            ctx.setStrokeColor(red.cgColor)
            ctx.setLineWidth(8)
            ctx.stroke(CGRect(x: 1246, y: 6, width: 408, height: 450))
        }
        text(ctx, "PRs", x: x0, baseline: 70, size: 34, color: muted)
        guard z.lastSuccess != nil else {
            text(ctx, "?", x: x0, baseline: 250, size: 110, bold: true, color: grey)
            return
        }
        let c = z.isStale ? grey : white
        text(ctx, "\(z.toReview)", x: x0, baseline: 170, size: 72, bold: true, color: c)
        text(ctx, "zu reviewen", x: x0 + 110, baseline: 165, size: 36, color: c)
        text(ctx, "\(z.mine)", x: x0, baseline: 270, size: 72, bold: true, color: c)
        text(ctx, "eigene offen", x: x0 + 110, baseline: 265, size: 36, color: c)
        if z.ciFailing > 0 {
            let rc = z.isStale ? grey : red
            text(ctx, "\(z.ciFailing)", x: x0, baseline: 370, size: 72, bold: true, color: rc)
            text(ctx, "CI rot", x: x0 + 110, baseline: 365, size: 36, color: rc)
        }
        if z.isStale, let t = z.lastSuccess {
            text(ctx, "Stand \(BoardText.clock(t))", x: x0, baseline: 435, size: 30, color: grey)
        }
    }

    private static func drawClock(_ ctx: CGContext, _ s: BoardState) {
        text(ctx, BoardText.clock(s.now), x: 1685, baseline: 260, size: 72, bold: true, color: white)
    }

    // MARK: Hilfen

    private static func stateColor(_ a: AgentActivity) -> RGBColor {
        if a.isStale { return grey }
        switch a.state {
        case .running: return green
        case .waiting: return amber
        case .error: return red
        case .done: return grey
        }
    }

    private static func fill(_ ctx: CGContext, _ rect: CGRect, _ color: RGBColor) {
        ctx.setFillColor(color.cgColor)
        ctx.fill(rect)
    }

    private static func text(_ ctx: CGContext, _ string: String, x: CGFloat, baseline: CGFloat,
                             size: CGFloat, bold: Bool = false, color: RGBColor) {
        let font = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)!
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1) // Kontext ist gespiegelt
        ctx.textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}
