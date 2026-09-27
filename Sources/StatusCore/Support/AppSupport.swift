import Foundation
import Security

public struct Endpoint: Codable, Equatable {
    public var port: UInt16
    public init(port: UInt16) { self.port = port }
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
    public func removeEndpoint() {
        try? FileManager.default.removeItem(at: endpointURL)
    }

    public func readEndpoint() -> Endpoint? {
        (try? Data(contentsOf: endpointURL)).flatMap { try? JSONDecoder().decode(Endpoint.self, from: $0) }
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }
}
