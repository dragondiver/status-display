import CoreGraphics
import Foundation

/// Layout des Board-Fensters in Fensterpunkten (Entscheidung Florian, 28.09.2026, status-display#38):
/// Das Fenster rendert selbst in seiner Größe statt das 1920×462-Bild des AKP02 zu skalieren. Schrift
/// hat feste Punktgrößen, Zonenbreiten folgen der Fensterbreite, die Zeilenzahl folgt der Höhe, und
/// ohne Agenten entfällt deren Zone – die PR-Tabelle bekommt den Platz.
///
/// Reine Geometrie ohne Zeichnen und ohne AppKit, damit sie ohne Fenster testbar ist. Koordinaten
/// von oben links (wie `BoardRenderer` und die gespiegelte Fensteransicht).
public struct BoardWindowLayout: Equatable {
    /// Kleinste sinnvolle Fenstergröße: Statusname (zwei Zeilen) und Uhr überlappen nicht, und die
    /// Tabellen haben mindestens vier Zeilen (Platz für Zeile, „+N weitere“ und die Hinweiszeile).
    public static let minimumSize = CGSize(width: 400, height: 100)

    /// Feste Schriftgrößen in Punkt (unabhängig von der Fenstergröße).
    public enum FontSize {
        /// Statusname, fett; wird für lange Wörter bis `statusMin` verkleinert.
        public static let statusMax: CGFloat = 16
        public static let statusMin: CGFloat = 11
        public static let clock: CGFloat = 16
        public static let since: CGFloat = 11
        /// Zonenüberschriften („AGENTEN“, „PRs“, „Review“, „Offen“).
        public static let header: CGFloat = 10
        public static let row: CGFloat = 12
        /// „+N weitere“ und „Ausgeblendet · N zu reviewen“.
        public static let note: CGFloat = 11
        /// Großes „?“, solange noch nie PRs abgerufen wurden.
        public static let unknown: CGFloat = 28
    }

    /// Innenabstand jeder Zone.
    public static let padding: CGFloat = 8
    /// Zeilenabstand der Tabellen (Grundlinie zu Grundlinie).
    public static let rowHeight: CGFloat = 17
    /// Grundlinie der Zonenüberschrift.
    public static let headerBaseline: CGFloat = padding + FontSize.header
    /// Grundlinie der ersten Tabellenzeile.
    public static let firstRowBaseline: CGFloat = headerBaseline + rowHeight
    /// Mindestabstand der letzten Grundlinie zum unteren Rand (Unterlängen).
    static let bottomInset: CGFloat = 5
    /// Anteil der Agenten-Zone an der Breite rechts der Statuszone (falls Agenten da sind).
    static let agentsShare: CGFloat = 0.45
    /// Breite der Zahlenspalten „Review“/„Offen“ (rechtsbündig, Platz für die Überschrift).
    static let numberColumnWidth: CGFloat = 40

    public let size: CGSize

    // MARK: Zonen

    /// Statuszone links, volle Höhe; zugleich die Klickfläche fürs Status-Menü (status-display#33).
    public let statusRect: CGRect
    /// Agenten-Zone; `nil`, wenn keine Agenten gemeldet sind.
    public let agentsRect: CGRect?
    public let prsRect: CGRect

    // MARK: Statuszone

    /// Höchstens zwei Wörter des Statusnamens in Großbuchstaben, je eine Zeile (wie auf dem Display).
    public let statusWords: [String]
    public let statusFontSize: CGFloat
    public let statusBaselines: [CGFloat]
    public let clockBaseline: CGFloat
    public let sinceBaseline: CGFloat

    // MARK: Tabellen

    /// Zeilen, die in die Höhe passen (inklusive „+N weitere“ und Hinweiszeile).
    public let maxRows: Int
    public let agentRows: [AgentActivity]
    public let agentMore: Int
    public let prRows: [PRRow]
    public let prMore: Int
    public let prHiddenHint: String?

    /// Rechte Kanten der Zahlenspalten und rechte Grenze des Repo-Namens in der PR-Tabelle.
    public let prMineRight: CGFloat
    public let prReviewRight: CGFloat
    public let prRepoX: CGFloat
    public let prRepoMaxX: CGFloat

    public init(state: BoardState, size: CGSize) {
        self.size = size
        let w = max(size.width, 0)
        let h = max(size.height, 0)
        let pad = Self.padding

        // Zonen
        let statusWidth = min(Self.statusWidth(forWindowWidth: w), w)
        statusRect = CGRect(x: 0, y: 0, width: statusWidth, height: h)
        let rest = max(w - statusWidth, 0)
        if state.agents.isEmpty {
            agentsRect = nil
            prsRect = CGRect(x: statusWidth, y: 0, width: rest, height: h)
        } else {
            let agentsWidth = (rest * Self.agentsShare).rounded()
            agentsRect = CGRect(x: statusWidth, y: 0, width: agentsWidth, height: h)
            prsRect = CGRect(x: statusWidth + agentsWidth, y: 0, width: rest - agentsWidth, height: h)
        }

        // Statuszone: Name oben, Uhr und „seit …“ unten.
        let words = state.statusName.uppercased().split(separator: " ").map(String.init).prefix(2)
        statusWords = Array(words)
        let textWidth = max(statusWidth - 2 * pad, 1)
        let fitted = words.map { BoardText.statusFontSize(for: $0, width: textWidth, maxSize: FontSize.statusMax) }.min()
            ?? FontSize.statusMax
        let fontSize = max(fitted, FontSize.statusMin)
        statusFontSize = fontSize
        statusBaselines = words.indices.map { pad + fontSize + CGFloat($0) * (fontSize + 3) }
        sinceBaseline = h - 6
        clockBaseline = sinceBaseline - FontSize.since - 5

        // Tabellen
        let usable = h - Self.bottomInset - Self.firstRowBaseline
        maxRows = usable < 0 ? 0 : Int((usable / Self.rowHeight).rounded(.down)) + 1
        (agentRows, agentMore) = BoardText.visibleAgents(state.agents, maxRows: max(maxRows, 1))
        (prRows, prMore, prHiddenHint) = BoardText.visiblePRRows(state.prs.rows,
                                                                 hiddenReviewCount: state.prs.hiddenReviews.count,
                                                                 maxRows: maxRows)
        prMineRight = prsRect.maxX - pad
        prReviewRight = prMineRight - Self.numberColumnWidth
        prRepoX = prsRect.minX + pad + 12
        prRepoMaxX = max(prReviewRight - Self.numberColumnWidth, prRepoX)
    }

    /// Breite der Statuszone: ein gutes Viertel der Fensterbreite, mindestens so breit, dass Uhr und
    /// „seit 12:59 h“ passen, höchstens so breit, dass sie bei breiten Fenstern nicht ausufert.
    public static func statusWidth(forWindowWidth width: CGFloat) -> CGFloat {
        min(max((width * 0.26).rounded(), 120), 220)
    }

    /// Grundlinie der Tabellenzeile `index` (0 = erste Zeile unter der Überschrift).
    public static func rowBaseline(_ index: Int) -> CGFloat {
        firstRowBaseline + CGFloat(index) * rowHeight
    }
}
