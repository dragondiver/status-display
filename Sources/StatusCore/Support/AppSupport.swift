import Foundation
import Security

public struct Endpoint: Codable, Equatable {
    public var port: UInt16
    /// PID der Instanz, die diese Datei geschrieben hat (status-display#27). Optional, damit eine
    /// von einer älteren Version geschriebene `endpoint.json` ohne `pid` noch decodierbar ist – der
    /// Hook-Befehl liest ohnehin nur `port`. `nil` heißt „unbekannt/fremd“, nie „ist meine“.
    public var pid: Int32?
    public init(port: UInt16, pid: Int32? = nil) {
        self.port = port
        self.pid = pid
    }
}

/// Lokal zwischengespeicherte Repo-Liste eines Hosts (Einstellungs-Reiter „Repos“, #15) mit
/// Ladezeitpunkt, damit die UI „Stand …“ anzeigen kann statt bei jedem Öffnen neu zu laden.
public struct RepoCache: Codable, Equatable {
    public var repos: [String]
    public var fetchedAt: Date
    public init(repos: [String], fetchedAt: Date) { self.repos = repos; self.fetchedAt = fetchedAt }
}

/// Token und Port in ~/Library/Application Support/status-display, gelesen von App und Hook-Befehl.
public struct AppSupport {
    public let directory: URL

    public init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/status-display")) {
        self.directory = directory
    }

    public var tokenURL: URL { directory.appendingPathComponent("token") }
    public var endpointURL: URL { directory.appendingPathComponent("endpoint.json") }

    public func loadOrCreateToken() throws -> String {
        if let t = readToken() {
            try ensureDirectory()
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenURL.path)
            return t
        }
        return try regenerateToken()
    }

    public func regenerateToken() throws -> String {
        try ensureDirectory()
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw CocoaError(.fileWriteUnknown)
        }
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        try writeSecurely(Data(token.utf8), to: tokenURL)
        return token
    }

    /// Schreibt über eine temporäre Datei mit 0600 von Anfang an (kein Fenster mit weiteren Rechten)
    /// und ersetzt die Zieldatei atomar.
    private func writeSecurely(_ data: Data, to url: URL) throws {
        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: tempURL.path, contents: data,
                                              attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func readToken() -> String? {
        guard let data = try? Data(contentsOf: tokenURL) else { return nil }
        let t = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    public func writeEndpoint(_ endpoint: Endpoint) throws {
        try ensureDirectory()
        try JSONEncoder().encode(endpoint).write(to: endpointURL, options: .atomic)
    }

    /// Hooks sollen das Token nie an einen Port schicken, den die App nicht (mehr) belegt.
    /// Bedingungslos – nur als Baustein für `removeEndpointIfOwn` bzw. für Tests gedacht, denn
    /// alleine entfernt sie auch eine `endpoint.json`, die einer anderen, noch laufenden Instanz
    /// gehört (status-display#27).
    public func removeEndpoint() {
        try? FileManager.default.removeItem(at: endpointURL)
    }

    /// Wie `removeEndpoint()`, aber nur, wenn die aktuell auf der Platte stehende `endpoint.json`
    /// nachweislich von dieser Instanz (`ownPid`) geschrieben wurde – siehe `EndpointOwnership`.
    /// Das ist der Aufruf, den die App bei eigenen Fehlern/beim Beenden benutzen soll, damit eine
    /// zweite, gescheiterte Instanz nie die Datei einer erfolgreich laufenden Instanz löscht.
    public func removeEndpointIfOwn(ownPid: Int32) {
        guard EndpointOwnership.mayRemove(endpoint: readEndpoint(), ownPid: ownPid) else { return }
        removeEndpoint()
    }

    public func readEndpoint() -> Endpoint? {
        (try? Data(contentsOf: endpointURL)).flatMap { try? JSONDecoder().decode(Endpoint.self, from: $0) }
    }

    /// Eine Datei je Host: `host` besteht laut `AppSettings.normalizedHost` nur aus
    /// Kleinbuchstaben, Ziffern, `-` und `.` und ist damit als Dateinamensteil unbedenklich.
    public func repoCacheURL(host: String) -> URL {
        directory.appendingPathComponent("repos-\(host).json")
    }

    public func writeRepoCache(_ cache: RepoCache, host: String) throws {
        try ensureDirectory()
        try JSONEncoder().encode(cache).write(to: repoCacheURL(host: host), options: .atomic)
    }

    public func readRepoCache(host: String) -> RepoCache? {
        (try? Data(contentsOf: repoCacheURL(host: host))).flatMap { try? JSONDecoder().decode(RepoCache.self, from: $0) }
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }
}
