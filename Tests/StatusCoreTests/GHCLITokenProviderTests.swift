import XCTest
@testable import StatusCore

final class GHCLITokenProviderTests: XCTestCase {
    private func script(_ body: String) throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gh-\(UUID().uuidString)")
        try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }

    func testMissingBinary() {
        let p = GHCLITokenProvider(candidates: ["/nicht/vorhanden/gh"])
        XCTAssertThrowsError(try p.token(for: "github.com")) { XCTAssertEqual($0 as? GitHubError, .ghNotFound) }
    }

    func testReturnsTokenAndPassesHost() throws {
        let path = try script(#"[ "$1 $2 $3 $4" = "auth token --hostname ghe.firma.de" ] && echo gho_abc || exit 1"#)
        XCTAssertEqual(try GHCLITokenProvider(candidates: [path]).token(for: "ghe.firma.de"), "gho_abc")
    }

    func testNotLoggedIn() throws {
        let path = try script("echo 'no oauth token' >&2; exit 1")
        XCTAssertThrowsError(try GHCLITokenProvider(candidates: [path]).token(for: "ghe.firma.de")) {
            XCTAssertEqual($0 as? GitHubError, .notLoggedIn("ghe.firma.de"))
        }
    }

    func testCustomPathComesFirst() {
        XCTAssertEqual(GHCLITokenProvider(customPath: "/x/gh").candidates.first, "/x/gh")
        XCTAssertEqual(GHCLITokenProvider(customPath: "").candidates.first, "/opt/homebrew/bin/gh")
    }
}
