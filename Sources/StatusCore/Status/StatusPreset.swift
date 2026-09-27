import Foundation

public struct StatusPreset: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var colorHex: String

    public init(id: String, name: String, colorHex: String) {
        self.id = id; self.name = name; self.colorHex = colorHex
    }

    public var color: RGBColor { RGBColor(hex: colorHex) ?? RGBColor(r: 0.35, g: 0.37, b: 0.4) }

    public static let availableID = "available"

    public static let defaults: [StatusPreset] = [
        StatusPreset(id: "deep-focus", name: "Deep Focus", colorHex: "#B3263E"),
        StatusPreset(id: "in-meeting", name: "In Meeting", colorHex: "#6B3FA0"),
        StatusPreset(id: "easy-coding", name: "Easy Coding", colorHex: "#2E8B57"),
        StatusPreset(id: availableID, name: "Verfügbar", colorHex: "#5A5F66"),
        StatusPreset(id: "pause", name: "Pause", colorHex: "#2F6DB5"),
    ]
}

public struct ActiveStatus: Codable, Equatable {
    public var presetID: String
    public var since: Date
    public var until: Date?
}

public struct AutoStatus: Equatable {
    public var presetID: String
    public var source: String
    public var since: Date
}
