import CoreGraphics
import CoreText
import Foundation

/// Zeichnet das Board-Fenster nach `BoardWindowLayout` (status-display#38): eigenes Layout in
/// Fenstergröße mit festen Punktgrößen statt des herunterskalierten 1920×462-Displaybilds. Farben
/// und Regeln wie auf dem Display (`BoardRenderer`): Statusfarbe, orange für wartende Agenten und
/// Extra-Review-Anfragen, rot für rote CI, grau bei veralteten Daten.
///
/// `draw` erwartet einen Kontext in Punkten mit Ursprung oben links (y nach unten) – so, wie ihn eine
/// gespiegelte `NSView` in `draw(_:)` liefert; die Backing-Skalierung (Retina) steckt dort schon in
/// der CTM, der Text wird also in voller Auflösung gesetzt.
public enum BoardWindowRenderer {
    private typealias R = BoardRenderer
    private typealias L = BoardWindowLayout
    private typealias F = BoardWindowLayout.FontSize

    /// Rendert in ein eigenes Bild mit `scale` Pixeln je Punkt (Vorschau, Tests).
    public static func render(_ s: BoardState, size: CGSize, scale: CGFloat = 2) -> CGImage {
        let ctx = PanelImage.makeContext(width: Int((size.width * scale).rounded()),
                                         height: Int((size.height * scale).rounded()))
        ctx.translateBy(x: 0, y: size.height * scale)
        ctx.scaleBy(x: scale, y: -scale)
        draw(s, size: size, in: ctx)
        return ctx.makeImage()!
    }

    public static func draw(_ s: BoardState, size: CGSize, in ctx: CGContext) {
        let layout = BoardWindowLayout(state: s, size: size)
        fill(ctx, CGRect(origin: .zero, size: size), R.background)
        drawStatus(ctx, s, layout)
        if let agentsRect = layout.agentsRect {
            drawAgents(ctx, s, layout, agentsRect)
            fill(ctx, CGRect(x: agentsRect.maxX - 0.5, y: L.padding, width: 1, height: size.height - 2 * L.padding),
                 R.separator)
        }
        drawPRs(ctx, s, layout)
    }

    // MARK: Zonen

    private static func drawStatus(_ ctx: CGContext, _ s: BoardState, _ l: BoardWindowLayout) {
        fill(ctx, l.statusRect, s.statusColor)
        let x = l.statusRect.minX + L.padding
        let maxWidth = l.statusRect.width - 2 * L.padding
        for (word, baseline) in zip(l.statusWords, l.statusBaselines) {
            text(ctx, word, x: x, baseline: baseline, size: l.statusFontSize, bold: true, color: R.white,
                 maxWidth: maxWidth)
        }
        text(ctx, BoardText.clock(s.now), x: x, baseline: l.clockBaseline, size: F.clock, bold: true,
             color: R.white, maxWidth: maxWidth)
        text(ctx, BoardText.since(s.statusSince, now: s.now), x: x, baseline: l.sinceBaseline, size: F.since,
             color: R.white.withAlpha(0.8), maxWidth: maxWidth)
    }

    private static func drawAgents(_ ctx: CGContext, _ s: BoardState, _ l: BoardWindowLayout, _ zone: CGRect) {
        let x0 = zone.minX + L.padding
        let right = zone.maxX - L.padding
        text(ctx, "AGENTEN", x: x0, baseline: L.headerBaseline, size: F.header, color: R.muted)
        for (i, a) in l.agentRows.enumerated() {
            let baseline = L.rowBaseline(i)
            let color = R.stateColor(a)
            if a.state == .waiting {
                fill(ctx, CGRect(x: zone.minX + 2, y: baseline - F.row - 1, width: zone.width - 4, height: L.rowHeight),
                     R.amber.withAlpha(0.22))
            }
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: CGRect(x: x0, y: baseline - 8, width: 7, height: 7))
            // Name links, Zustand rechtsbündig. Wird es eng, behält der Name mindestens gut ein Drittel
            // der Zeile, und auch der Zustand wird mit „…“ gekürzt.
            let label = BoardText.agentLabel(a, now: s.now)
            let nameX = x0 + 12
            let available = right - nameX - 6
            let nameReserve = min(textWidth(a.name, size: F.row), available * 0.4)
            let labelWidth = min(textWidth(label, size: F.row), available - nameReserve)
            text(ctx, label, x: right - labelWidth, baseline: baseline, size: F.row, color: color, maxWidth: labelWidth)
            text(ctx, a.name, x: nameX, baseline: baseline, size: F.row, color: a.isStale ? R.grey : R.white,
                 maxWidth: available - labelWidth)
        }
        if l.agentMore > 0 {
            text(ctx, "+\(l.agentMore) weitere", x: x0 + 12, baseline: L.rowBaseline(l.agentRows.count),
                 size: F.note, color: R.muted)
        }
    }

    private static func drawPRs(_ ctx: CGContext, _ s: BoardState, _ l: BoardWindowLayout) {
        let zone = l.prsRect
        let x0 = zone.minX + L.padding
        let z = s.prs
        if z.ciFailingCount > 0 && !z.isStale {
            ctx.setStrokeColor(R.red.cgColor)
            ctx.setLineWidth(2)
            ctx.stroke(zone.insetBy(dx: 2, dy: 2))
        }
        let headerWidth = text(ctx, "PRs", x: x0, baseline: L.headerBaseline, size: F.header, color: R.muted)
        if z.isStale, let t = z.lastSuccess {
            text(ctx, "Stand \(BoardText.clock(t))", x: x0 + headerWidth + 6, baseline: L.headerBaseline,
                 size: F.header, color: R.grey)
        }
        guard z.lastSuccess != nil else {
            text(ctx, "?", x: x0, baseline: L.rowBaseline(1), size: F.unknown, bold: true, color: R.grey)
            return
        }
        guard !z.rows.isEmpty || !z.hiddenReviews.isEmpty else {
            text(ctx, "keine PRs", x: x0, baseline: L.rowBaseline(0), size: F.row, color: R.muted)
            return
        }
        rightAligned(ctx, "Review", right: l.prReviewRight, baseline: L.headerBaseline, size: F.header, color: R.muted)
        rightAligned(ctx, "Offen", right: l.prMineRight, baseline: L.headerBaseline, size: F.header, color: R.muted)

        let c = z.isStale ? R.grey : R.white
        var index = 0
        for row in l.prRows {
            let baseline = L.rowBaseline(index)
            if row.ciFailing {
                ctx.setFillColor(R.red.cgColor)
                ctx.fillEllipse(in: CGRect(x: x0, y: baseline - 8, width: 7, height: 7))
            }
            text(ctx, row.repository, x: l.prRepoX, baseline: baseline, size: F.row, color: c,
                 maxWidth: l.prRepoMaxX - l.prRepoX)
            rightAligned(ctx, "\(row.toReview)", right: l.prReviewRight, baseline: baseline, size: F.row, bold: true,
                         color: row.hasExtraReview ? R.amber : c)
            rightAligned(ctx, "\(row.mine)", right: l.prMineRight, baseline: baseline, size: F.row, bold: true, color: c)
            index += 1
        }
        if l.prMore > 0 {
            text(ctx, "+\(l.prMore) weitere", x: l.prRepoX, baseline: L.rowBaseline(index), size: F.note, color: R.muted)
            index += 1
        }
        if let hint = l.prHiddenHint {
            drawHiddenHint(ctx, hint, hiddenCount: z.hiddenReviews.count,
                           hasExtra: z.hiddenReviews.contains { $0.hasExtraRequestForMe },
                           x: l.prRepoX, baseline: L.rowBaseline(index), maxX: zone.maxX - L.padding)
        }
    }

    /// „Ausgeblendet · N zu reviewen“ in Grau; bei einer Extra-Anfrage darunter nur die Zahl orange
    /// (wie `BoardRenderer`, status-display#21).
    private static func drawHiddenHint(_ ctx: CGContext, _ hint: String, hiddenCount: Int, hasExtra: Bool,
                                       x: CGFloat, baseline: CGFloat, maxX: CGFloat) {
        let number = "\(hiddenCount)"
        guard hasExtra, let range = hint.range(of: number) else {
            text(ctx, hint, x: x, baseline: baseline, size: F.note, color: R.grey, maxWidth: maxX - x)
            return
        }
        var tx = x
        tx += text(ctx, String(hint[..<range.lowerBound]), x: tx, baseline: baseline, size: F.note, color: R.grey)
        tx += text(ctx, number, x: tx, baseline: baseline, size: F.note, color: R.amber)
        text(ctx, String(hint[range.upperBound...]), x: tx, baseline: baseline, size: F.note, color: R.grey,
             maxWidth: maxX - tx)
    }

    // MARK: Hilfen

    private static func fill(_ ctx: CGContext, _ rect: CGRect, _ color: RGBColor) {
        ctx.setFillColor(color.cgColor)
        ctx.fill(rect)
    }

    private static func line(_ string: String, size: CGFloat, bold: Bool, color: RGBColor) -> CTLine {
        let font = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)!
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
    }

    /// Gezeichnete Breite von `string` in Punkt.
    static func textWidth(_ string: String, size: CGFloat, bold: Bool = false) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line(string, size: size, bold: bold, color: R.white), nil, nil, nil))
    }

    /// Zeichnet `string` ab `x` und kürzt es mit „…“ auf `maxWidth`; liefert die gezeichnete Breite.
    @discardableResult
    private static func text(_ ctx: CGContext, _ string: String, x: CGFloat, baseline: CGFloat, size: CGFloat,
                             bold: Bool = false, color: RGBColor, maxWidth: CGFloat? = nil) -> CGFloat {
        var drawn = line(string, size: size, bold: bold, color: color)
        if let maxWidth, CGFloat(CTLineGetTypographicBounds(drawn, nil, nil, nil)) > maxWidth {
            guard maxWidth > 0 else { return 0 }
            let token = line("…", size: size, bold: bold, color: color)
            guard let truncated = CTLineCreateTruncatedLine(drawn, Double(maxWidth), .end, token) else { return 0 }
            drawn = truncated
        }
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1) // Kontext ist gespiegelt
        ctx.textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(drawn, ctx)
        ctx.restoreGState()
        return CGFloat(CTLineGetTypographicBounds(drawn, nil, nil, nil))
    }

    private static func rightAligned(_ ctx: CGContext, _ string: String, right: CGFloat, baseline: CGFloat,
                                     size: CGFloat, bold: Bool = false, color: RGBColor) {
        text(ctx, string, x: right - textWidth(string, size: size, bold: bold), baseline: baseline, size: size,
             bold: bold, color: color)
    }
}
