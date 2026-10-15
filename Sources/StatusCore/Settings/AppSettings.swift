import Foundation

/// Einstellungen pro Mac. Nichts wird zwischen Macs synchronisiert.
public struct AppSettings: Codable, Equatable {
    public var hosts: [String] = ["github.com"]
    public var brightness = 60
    public var port: UInt16 = 47615
    public var ghPath = ""
    /// Einträge der Form `host/owner/name`. Erscheinen in der PR-Tabelle immer, auch mit 0/0.
    public var pinnedRepos: [String] = []
    /// Einträge der Form `host/owner/name`. Erscheinen nie in der PR-Tabelle.
    public var hiddenRepos: [String] = []
    /// Einträge der Form `host/owner/name`, die explizit auf „normal“ stehen, obwohl der
    /// Host-Standard (`hostDefaults`) für ihren Host „ausgeblendet“ ist. Ohne diese Liste ließe
    /// sich unter einem Host-Standard von „ausgeblendet“ kein einzelnes Repo wieder normal
    /// schalten (Entscheidung Florian, 28.09.2026, status-display#19).
    public var shownRepos: [String] = []
    /// Standard-Zustand (normal/ausgeblendet) für Repos ohne Eintrag in `pinnedRepos`/
    /// `hiddenRepos`/`shownRepos`, pro Host. Bewusst ein eigener Standard statt Hunderte
    /// Einträge in `hiddenRepos`: später auf einem Host neu angelegte Repos folgen so automatisch
    /// dem Standard. Gesetzt beim Hinzufügen eines Hosts (`addHost`, `github.com` normal, alle
    /// anderen Hosts ausgeblendet) und beim Dekodieren alter Einstellungen ohne dieses Feld
    /// (siehe `init(from:)`); siehe `RepoSelection.hostDefault(for:hostDefaults:)` für die Regel,
    /// die dabei angewendet wird.
    public var hostDefaults: [String: RepoDefault] = [:]
    /// Sichtbarkeit des Board-Fensters (status-display#23). Standard „automatisch“: sichtbar,
    /// solange kein AKP02 verbunden ist.
    public var boardWindowMode: BoardWindowMode = .automatic
    /// „Immer im Vordergrund“-Schalter für das Board-Fenster (status-display#23).
    public var boardWindowAlwaysOnTop = false
    public var jiraServers: [JiraServer] = []

    public var jiraConfigured: Bool { !jiraServers.isEmpty }

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case hosts, brightness, port, ghPath, pinnedRepos, hiddenRepos, shownRepos, hostDefaults,
             boardWindowMode, boardWindowAlwaysOnTop,
             jiraServers
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
        shownRepos = try c.decodeIfPresent([String].self, forKey: .shownRepos) ?? []
        if let decoded = try c.decodeIfPresent([String: RepoDefault].self, forKey: .hostDefaults) {
            hostDefaults = decoded
        } else {
            // Vor Issue #19 gespeicherte Einstellungen kennen `hostDefaults` noch nicht: für ihre
            // damals schon eingetragenen Hosts gilt rückwirkend dieselbe Regel wie für neu
            // hinzugefügte (`addHost`) – github.com normal, alle anderen ausgeblendet – (Entscheidung
            // Florian, 28.09.2026). `github.com` bekommt dabei bewusst keinen expliziten Eintrag:
            // `RepoSelection.hostDefault(for:hostDefaults:)` liefert für ihn ohnehin „normal“, und so
            // bleibt der ganz normale Fall (nur github.com, keine anderen Hosts) identisch mit
            // `AppSettings()` statt unnötig einen Eintrag mitzuschleppen.
            hostDefaults = Dictionary(uniqueKeysWithValues: hosts.filter { $0 != "github.com" }.map { host in
                (host, RepoDefault.hidden)
            })
        }
        boardWindowMode = try c.decodeIfPresent(BoardWindowMode.self, forKey: .boardWindowMode)
            ?? AppSettings().boardWindowMode
        boardWindowAlwaysOnTop = try c.decodeIfPresent(Bool.self, forKey: .boardWindowAlwaysOnTop)
            ?? AppSettings().boardWindowAlwaysOnTop
        if let servers = try c.decodeIfPresent([JiraServer].self, forKey: .jiraServers) {
            jiraServers = servers
        } else {
            // Migration: einzelne Felder aus früherer Version in JiraServer umwandeln.
            struct LegacyKey: CodingKey {
                var stringValue: String; init(stringValue s: String) { stringValue = s }
                var intValue: Int? { nil }; init?(intValue: Int) { nil }
            }
            let legacy = try decoder.container(keyedBy: LegacyKey.self)
            let d = (try? legacy.decodeIfPresent(String.self, forKey: LegacyKey(stringValue: "jiraDomain"))) ?? ""
            let e = (try? legacy.decodeIfPresent(String.self, forKey: LegacyKey(stringValue: "jiraEmail")))  ?? ""
            let t = (try? legacy.decodeIfPresent(String.self, forKey: LegacyKey(stringValue: "jiraToken")))  ?? ""
            jiraServers = (!d.isEmpty && !e.isEmpty && !t.isEmpty)
                ? [JiraServer(domain: d, email: e, token: t)] : []
        }
    }

    private static let key = "settings"

    public static func load(from defaults: UserDefaults = .standard) -> AppSettings {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(AppSettings.self, from: $0) } ?? AppSettings()
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.key)
    }

    /// Fügt `host` zu `hosts` hinzu (falls noch nicht vorhanden) und setzt seinen Standard:
    /// `github.com` normal, jeder andere Host ausgeblendet (Entscheidung Florian, 28.09.2026,
    /// status-display#19). Für `github.com` selbst wird bewusst kein Eintrag angelegt – siehe
    /// `init(from:)`.
    public mutating func addHost(_ host: String) {
        guard !hosts.contains(host) else { return }
        hosts.append(host)
        if host != "github.com" { hostDefaults[host] = .hidden }
    }

    /// Schaltet den Host-Standard für `host` um (Reiter „Repos“) – auch für `github.com`, das ohne
    /// Eintrag über den Fallback in `RepoSelection.hostDefault` normal ist: Umschalten legt dann
    /// den ersten expliziten Eintrag an.
    ///
    /// `shownRepos` ist nur unter einem ausgeblendeten Standard sinnvoll (der einzige Weg, ein
    /// einzelnes Repo trotzdem auf normal zu stellen). Wechselt der Standard auf normal, sind
    /// diese Einträge für `host` überflüssig – wirkungslos, weil normal ohnehin der Standard ist,
    /// aber ohne Aufräumen würden sie bei einem späteren Zurückschalten auf ausgeblendet unerwartet
    /// wieder genau diese Repos freischalten. Deshalb werden sie hier entfernt (Entscheidung
    /// Florian, 28.09.2026, status-display#19 Nachbesserung).
    public mutating func setHostDefault(_ def: RepoDefault, for host: String) {
        hostDefaults[host] = def
        if def == .normal {
            shownRepos.removeAll { RepoSelection.repository(forKey: $0, host: host) != nil }
        }
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
