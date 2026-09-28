import Foundation

/// Baut die Einträge des Status-Menüs – **einmal**, für Menüleiste, Dashboard-Etikett und
/// Board-Fenster (Entscheidung Florian, 28.09.2026, status-display#33): keine dritte, abweichende
/// Liste pflegen. Reine Daten/Logik, ohne AppKit/SwiftUI, damit sie ohne UI testbar ist.
public enum StatusMenuBuilder {
    /// Eine Dauer-Vorgabe innerhalb des Untermenüs eines Status-Presets.
    public struct DurationChoice: Equatable {
        public let title: String
        /// `nil` heißt „ohne feste Dauer“ – das gilt sowohl für „Ohne Ende“ (`untilEndOfDay == false`)
        /// als auch für „Bis Tagesende“ (`untilEndOfDay == true`), die beide nicht über `duration`
        /// unterschieden werden können.
        public let duration: TimeInterval?
        public let untilEndOfDay: Bool

        public init(title: String, duration: TimeInterval?, untilEndOfDay: Bool) {
            self.title = title; self.duration = duration; self.untilEndOfDay = untilEndOfDay
        }
    }

    /// Reihenfolge und Beschriftung wie in der bestehenden Menüleiste (status-display, vor #33).
    public static let durationChoices: [DurationChoice] = [
        DurationChoice(title: "Ohne Ende", duration: nil, untilEndOfDay: false),
        DurationChoice(title: "30 Minuten", duration: 1800, untilEndOfDay: false),
        DurationChoice(title: "1 Stunde", duration: 3600, untilEndOfDay: false),
        DurationChoice(title: "2 Stunden", duration: 7200, untilEndOfDay: false),
        DurationChoice(title: "Bis Tagesende", duration: nil, untilEndOfDay: true),
    ]

    /// Ein Status-Preset mit seinem Dauer-Untermenü.
    public struct Entry: Equatable {
        public let presetID: String
        public let presetName: String
        public let choices: [DurationChoice]
    }

    /// Ein Eintrag pro Preset, in der übergebenen Reihenfolge, jeweils mit allen `durationChoices`.
    public static func entries(presets: [StatusPreset]) -> [Entry] {
        presets.map { Entry(presetID: $0.id, presetName: $0.name, choices: durationChoices) }
    }
}
