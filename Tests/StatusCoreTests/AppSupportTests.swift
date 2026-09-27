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
}
