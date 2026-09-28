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
        fill(ctx, CGRect(x: 1239, y: 40, width: 2, height: 382), separator)
        return ctx.makeImage()!
    }

    // MARK: Zonen

    private static func drawStatus(_ ctx: CGContext, _ s: BoardState) {
        fill(ctx, CGRect(x: 0, y: 0, width: 480, height: height), s.statusColor)
        let words = s.statusName.uppercased().split(separator: " ").map(String.init).prefix(2)
        let size = words.map { BoardText.statusFontSize(for: $0, width: 420, maxSize: 92) }.min() ?? 92
        var baseline: CGFloat = words.count > 1 ? 110 : 150
        for w in words {
            text(ctx, w, x: 40, baseline: baseline, size: size, bold: true, color: white)
            baseline += size + 8
        }
        // Uhr unten links in der Statuszone: 72 pt fett, darunter „seit …" kleiner.
        text(ctx, BoardText.clock(s.now), x: 40, baseline: 400, size: 72, bold: true, color: white)
        text(ctx, BoardText.since(s.statusSince, now: s.now), x: 40, baseline: 438, size: 30,
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
            // Name bis x≈940, Label ab 960 bis ≈1230 (längstes: „unklar seit 12:59 h“): bleibt links der Trennlinie bei 1240.
            text(ctx, BoardText.truncate(a.name, max: 16), x: x0 + 50, baseline: baseline, size: 44,
                 color: a.isStale ? grey : white)
            text(ctx, BoardText.agentLabel(a, now: s.now), x: x0 + 440, baseline: baseline, size: 34, color: color)
            baseline += 80
        }
        if more > 0 {
            text(ctx, "+\(more) weitere", x: x0 + 50, baseline: baseline, size: 36, color: muted)
        }
    }

    /// Tabellenspalten relativ zu `x0`: Repo-Name (mit rotem Punkt bei roter CI), „zu reviewen",
    /// „eigene offen".
    private static let prRepoColumn: CGFloat = 50
    private static let prToReviewColumn: CGFloat = 390
    private static let prMineColumn: CGFloat = 530

    private static func drawPRs(_ ctx: CGContext, _ s: BoardState) {
        let x0: CGFloat = 1270
        let z = s.prs
        if z.ciFailingCount > 0 && !z.isStale {
            ctx.setStrokeColor(red.cgColor)
            ctx.setLineWidth(8)
            ctx.stroke(CGRect(x: 1246, y: 6, width: 668, height: 450))
        }
        text(ctx, "PRs", x: x0, baseline: 70, size: 34, color: muted)
        if z.isStale, let t = z.lastSuccess {
            text(ctx, "Stand \(BoardText.clock(t))", x: x0 + 460, baseline: 70, size: 28, color: grey)
        }
        guard z.lastSuccess != nil else {
            text(ctx, "?", x: x0, baseline: 250, size: 110, bold: true, color: grey)
            return
        }
        guard !z.rows.isEmpty || !z.hiddenReviews.isEmpty else {
            text(ctx, "keine PRs", x: x0, baseline: 200, size: 40, color: muted)
            return
        }
        let c = z.isStale ? grey : white
        text(ctx, "Repo", x: x0 + prRepoColumn, baseline: 110, size: 24, color: muted)
        text(ctx, "Review", x: x0 + prToReviewColumn, baseline: 110, size: 24, color: muted)
        text(ctx, "Offen", x: x0 + prMineColumn, baseline: 110, size: 24, color: muted)

        let (rows, more, hiddenHint) = BoardText.visiblePRRows(z.rows, hiddenReviewCount: z.hiddenReviews.count)
        var baseline: CGFloat = 165
        for row in rows {
            if row.ciFailing {
                ctx.setFillColor(red.cgColor)
                ctx.fillEllipse(in: CGRect(x: x0, y: baseline - 32, width: 26, height: 26))
            }
            text(ctx, BoardText.truncate(row.repository, max: 16), x: x0 + prRepoColumn, baseline: baseline,
                 size: 38, color: c)
            // Extra-Anfrage an mich in diesem Repo: Review-Zahl orange statt weiß/grau (Entscheidung
            // Florian, 28.09.2026, status-display#21).
            text(ctx, "\(row.toReview)", x: x0 + prToReviewColumn, baseline: baseline, size: 38, bold: true,
                 color: row.hasExtraReview ? amber : c)
            text(ctx, "\(row.mine)", x: x0 + prMineColumn, baseline: baseline, size: 38, bold: true, color: c)
            baseline += 55
        }
        if more > 0 {
            text(ctx, "+\(more) weitere", x: x0 + prRepoColumn, baseline: baseline, size: 32, color: muted)
            baseline += 55
        }
        // Immer als letzte Zeile, nie durch „+N weitere“ verdeckt oder abgeschnitten
        // (`BoardText.visiblePRRows` reserviert dafür einen eigenen Platz).
        if let hiddenHint {
            drawHiddenHint(ctx, hiddenHint, hiddenCount: z.hiddenReviews.count,
                          hasExtra: z.hiddenReviews.contains { $0.hasExtraRequestForMe },
                          x: x0 + prRepoColumn, baseline: baseline)
        }
    }

    /// Zeichnet die Hinweiszeile „Ausgeblendet · N zu reviewen“; ist unter den ausgeblendeten
    /// Review-Requests mindestens eine Extra-Anfrage, wird nur die Zahl N orange gefärbt
    /// (Entscheidung Florian, 28.09.2026, status-display#21) – der Rest bleibt grau.
    private static func drawHiddenHint(_ ctx: CGContext, _ hint: String, hiddenCount: Int, hasExtra: Bool,
                                       x: CGFloat, baseline: CGFloat) {
        guard hasExtra else {
            text(ctx, hint, x: x, baseline: baseline, size: 32, color: grey)
            return
        }
        let numberString = "\(hiddenCount)"
        guard let range = hint.range(of: numberString) else {
            text(ctx, hint, x: x, baseline: baseline, size: 32, color: grey)
            return
        }
        let prefix = String(hint[hint.startIndex..<range.lowerBound])
        let suffix = String(hint[range.upperBound...])
        var tx = x
        tx += text(ctx, prefix, x: tx, baseline: baseline, size: 32, color: grey)
        tx += text(ctx, numberString, x: tx, baseline: baseline, size: 32, color: amber)
        text(ctx, suffix, x: tx, baseline: baseline, size: 32, color: grey)
    }

    // MARK: Hilfen

    /// Auch vom Board-Fenster (`BoardWindowRenderer`) genutzt – gleiche Farbregeln wie auf dem Display.
    static func stateColor(_ a: AgentActivity) -> RGBColor {
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

    /// Zeichnet `string` und liefert seine gezeichnete Breite zurück, damit Aufrufer mehrere
    /// Textstücke mit unterschiedlicher Farbe nahtlos aneinanderreihen können (z. B. die
    /// Hinweiszeile mit orange gefärbter Zahl).
    @discardableResult
    private static func text(_ ctx: CGContext, _ string: String, x: CGFloat, baseline: CGFloat,
                             size: CGFloat, bold: Bool = false, color: RGBColor) -> CGFloat {
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
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }
}
