import Foundation

/// Einstellungen pro Mac. Nichts wird zwischen Macs synchronisiert.
public struct AppSettings: Codable, Equatable {
    public var hosts: [String] = ["github.com"]
    public var brightness = 60
    public var port: UInt16 = 47615
    public var ghPath = ""

    public init() {}

    private static let key = "settings"

    public static func load(from defaults: UserDefaults = .standard) -> AppSettings {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(AppSettings.self, from: $0) } ?? AppSettings()
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.key)
    }
}
