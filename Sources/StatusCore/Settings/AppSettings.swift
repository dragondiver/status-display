import Foundation

/// Einstellungen pro Mac. Nichts wird zwischen Macs synchronisiert.
public struct AppSettings: Codable, Equatable {
    public var hosts: [String] = ["github.com"]
    public var brightness = 60
    public var port: UInt16 = 47615
    public var ghPath = ""
    /// Einträge der Form `host/owner/name`. Erscheinen in der PR-Tabelle immer, auch mit 0/0.
    /// Zunächst leer; die Auswahl-UI dafür folgt in einer eigenen Karte.
    public var pinnedRepos: [String] = []
    /// Einträge der Form `host/owner/name`. Erscheinen nie in der PR-Tabelle.
    public var hiddenRepos: [String] = []

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case hosts, brightness, port, ghPath, pinnedRepos, hiddenRepos
    }

    // Handgeschrieben statt synthetisiert: Felder, die es in gespeicherten Einstellungen noch
    // nicht gibt (z. B. `pinnedRepos`/`hiddenRepos`, hinzugefügt nach dem ersten Release), sollen
    // beim Dekodieren auf ihren Default fallen statt den ganzen Ladevorgang scheitern zu lassen.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hosts = try c.decodeIfPresent([String].self, forKey: .hosts) ?? AppSettings().hosts
        brightness = try c.decodeIfPresent(Int.self, forKey: .brightness) ?? AppSettings().brightness
        port = try c.decodeIfPresent(UInt16.self, forKey: .port) ?? AppSettings().port
        ghPath = try c.decodeIfPresent(String.self, forKey: .ghPath) ?? AppSettings().ghPath
        pinnedRepos = try c.decodeIfPresent([String].self, forKey: .pinnedRepos) ?? []
        hiddenRepos = try c.decodeIfPresent([String].self, forKey: .hiddenRepos) ?? []
    }

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
