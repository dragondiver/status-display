import Foundation

/// Manueller Status (persistent, optional mit Ablauf) und automatischer Status (Vorrang, flüchtig).
/// Nur vom Main-Thread benutzen.
public final class StatusStore {
    public private(set) var presets: [StatusPreset]
    public private(set) var manual: ActiveStatus
    public private(set) var automatic: AutoStatus?

    private let defaults: UserDefaults
    private let time: TimeSource
    private let calendar: Calendar
    private static let presetsKey = "status.presets"
    private static let manualKey = "status.manual"

    public init(defaults: UserDefaults = .standard, time: TimeSource = SystemTime(), calendar: Calendar = .current) {
        self.defaults = defaults
        self.time = time
        self.calendar = calendar
        presets = Self.decode([StatusPreset].self, defaults.data(forKey: Self.presetsKey)) ?? StatusPreset.defaults
        manual = Self.decode(ActiveStatus.self, defaults.data(forKey: Self.manualKey))
            ?? ActiveStatus(presetID: StatusPreset.availableID, since: time.now, until: nil)
    }

    public func set(_ presetID: String, for duration: TimeInterval? = nil) {
        manual = ActiveStatus(presetID: presetID, since: time.now, until: duration.map { time.now.addingTimeInterval($0) })
        save()
    }

    public func setUntilEndOfDay(_ presetID: String) {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: time.now)!
        manual = ActiveStatus(presetID: presetID, since: time.now, until: calendar.startOfDay(for: tomorrow))
        save()
    }

    public func setAutomatic(_ presetID: String?, source: String) {
        automatic = presetID.map { AutoStatus(presetID: $0, source: source, since: time.now) }
    }

    public func setPresets(_ newPresets: [StatusPreset]) {
        guard !newPresets.isEmpty else { return }
        presets = newPresets
        save()
    }

    public func effective() -> (preset: StatusPreset, since: Date) {
        if let auto = automatic, let p = preset(auto.presetID) { return (p, auto.since) }
        if let until = manual.until, until <= time.now {
            manual = ActiveStatus(presetID: StatusPreset.availableID, since: until, until: nil)
            save()
        }
        let p = preset(manual.presetID) ?? preset(StatusPreset.availableID) ?? presets[0]
        return (p, manual.since)
    }

    public func preset(_ id: String) -> StatusPreset? { presets.first { $0.id == id } }

    private func save() {
        defaults.set(try? JSONEncoder().encode(presets), forKey: Self.presetsKey)
        defaults.set(try? JSONEncoder().encode(manual), forKey: Self.manualKey)
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data?) -> T? {
        data.flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}
