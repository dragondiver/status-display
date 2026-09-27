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

    /// Trimmt, entfernt ein führendes `https://`/`http://` und ein abschließendes `/`, kleinschreibt,
    /// und liefert nil, wenn das Ergebnis kein gültiger Hostname ist (leer, Leerzeichen, ungültige
    /// Zeichen, oder keine gültige URL damit bildbar).
    public static func normalizedHost(_ input: String) -> String? {
        var h = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.lowercased().hasPrefix("https://") {
            h.removeFirst(8)
        } else if h.lowercased().hasPrefix("http://") {
            h.removeFirst(7)
        }
        while h.hasSuffix("/") { h.removeLast() }
        h = h.lowercased()
        guard !h.isEmpty else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.")
        guard h.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        guard URL(string: "https://\(h)/api/graphql") != nil else { return nil }
        return h
    }
}
