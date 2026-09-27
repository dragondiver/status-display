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
}
