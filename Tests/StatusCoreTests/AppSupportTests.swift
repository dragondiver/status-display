import XCTest
@testable import StatusCore

final class AppSupportTests: XCTestCase {
    private func temp() -> AppSupport {
        AppSupport(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    func testTokenIsCreatedOnceWithPrivatePermissions() throws {
        let s = temp()
        let t1 = try s.loadOrCreateToken()
        XCTAssertEqual(t1.count, 64)
        XCTAssertEqual(try s.loadOrCreateToken(), t1)
        XCTAssertEqual(s.readToken(), t1)
        let perms = try FileManager.default.attributesOfItem(atPath: s.tokenURL.path)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600)
        let dirPerms = try FileManager.default.attributesOfItem(atPath: s.directory.path)[.posixPermissions] as? Int
        XCTAssertEqual(dirPerms, 0o700)
    }

    func testLoadOrCreateRepairsPermissions() throws {
        let s = temp()
        try FileManager.default.createDirectory(at: s.directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o755])
        let existing = String(repeating: "ab", count: 32)
        XCTAssertTrue(FileManager.default.createFile(atPath: s.tokenURL.path, contents: Data(existing.utf8),
                                                       attributes: [.posixPermissions: 0o644]))
        let loaded = try s.loadOrCreateToken()
        XCTAssertEqual(loaded, existing)
        let perms = try FileManager.default.attributesOfItem(atPath: s.tokenURL.path)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600)
        let dirPerms = try FileManager.default.attributesOfItem(atPath: s.directory.path)[.posixPermissions] as? Int
        XCTAssertEqual(dirPerms, 0o700)
    }

    func testRegenerateChangesToken() throws {
        let s = temp()
        let t1 = try s.loadOrCreateToken()
        XCTAssertNotEqual(try s.regenerateToken(), t1)
    }

    func testEndpointRoundTrip() throws {
        let s = temp()
        XCTAssertNil(s.readEndpoint())
        try s.writeEndpoint(Endpoint(port: 47615))
        XCTAssertEqual(s.readEndpoint(), Endpoint(port: 47615))
    }

    func testRemoveEndpoint() throws {
        let s = temp()
        s.removeEndpoint() // fehlt: kein Fehler
        try s.writeEndpoint(Endpoint(port: 47615))
        s.removeEndpoint()
        XCTAssertNil(s.readEndpoint())
        XCTAssertFalse(FileManager.default.fileExists(atPath: s.endpointURL.path))
    }

    func testEndpointDecodesPid() throws {
        let s = temp()
        try s.writeEndpoint(Endpoint(port: 47615, pid: 4242))
        XCTAssertEqual(s.readEndpoint(), Endpoint(port: 47615, pid: 4242))
    }

    /// Eine `endpoint.json` von vor #27 hat kein `pid`-Feld – muss trotzdem decodierbar bleiben,
    /// der Hook-Befehl liest ohnehin nur `port`.
    func testEndpointDecodesWithoutPidField() throws {
        let s = temp()
        try FileManager.default.createDirectory(at: s.directory, withIntermediateDirectories: true)
        try Data(#"{"port":47615}"#.utf8).write(to: s.endpointURL)
        XCTAssertEqual(s.readEndpoint(), Endpoint(port: 47615, pid: nil))
    }

    /// status-display#27: eine zweite Instanz, die auf `.failed` läuft, darf die `endpoint.json`
    /// der laufenden Instanz nicht löschen, weil deren PID nicht die eigene ist.
    func testRemoveEndpointIfOwnKeepsForeignPid() throws {
        let s = temp()
        try s.writeEndpoint(Endpoint(port: 47615, pid: 111))
        s.removeEndpointIfOwn(ownPid: 222)
        XCTAssertEqual(s.readEndpoint(), Endpoint(port: 47615, pid: 111))
    }

    func testRemoveEndpointIfOwnRemovesOwnPid() throws {
        let s = temp()
        try s.writeEndpoint(Endpoint(port: 47615, pid: 111))
        s.removeEndpointIfOwn(ownPid: 111)
        XCTAssertNil(s.readEndpoint())
    }

    /// Alte Datei ohne PID: gehört niemandem nachweislich, bleibt unangetastet statt entfernt zu
    /// werden.
    func testRemoveEndpointIfOwnKeepsFileWithoutPid() throws {
        let s = temp()
        try s.writeEndpoint(Endpoint(port: 47615))
        s.removeEndpointIfOwn(ownPid: 111)
        XCTAssertEqual(s.readEndpoint(), Endpoint(port: 47615))
    }

    func testRemoveEndpointIfOwnOnMissingFileIsNoop() {
        let s = temp()
        s.removeEndpointIfOwn(ownPid: 111) // fehlt: kein Fehler
        XCTAssertNil(s.readEndpoint())
    }

    func testRepoCacheRoundTripIsPerHost() throws {
        let s = temp()
        XCTAssertNil(s.readRepoCache(host: "github.com"))
        let fetchedAt = Date(timeIntervalSince1970: 1_790_000_000)
        try s.writeRepoCache(RepoCache(repos: ["a/b", "a/c"], fetchedAt: fetchedAt), host: "github.com")
        XCTAssertNil(s.readRepoCache(host: "ghe.firma.de")) // anderer Host, eigene Datei
        let loaded = s.readRepoCache(host: "github.com")
        XCTAssertEqual(loaded?.repos, ["a/b", "a/c"])
        XCTAssertEqual(loaded?.fetchedAt, fetchedAt)
    }

    func testRepoCacheOverwritesPreviousValue() throws {
        let s = temp()
        try s.writeRepoCache(RepoCache(repos: ["a/b"], fetchedAt: Date(timeIntervalSince1970: 1)), host: "github.com")
        try s.writeRepoCache(RepoCache(repos: ["a/b", "a/c"], fetchedAt: Date(timeIntervalSince1970: 2)), host: "github.com")
        XCTAssertEqual(s.readRepoCache(host: "github.com")?.repos, ["a/b", "a/c"])
    }
}
