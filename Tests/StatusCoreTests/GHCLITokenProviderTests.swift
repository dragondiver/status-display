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

    func testTimesOutInsteadOfHangingForever() throws {
        let path = try script("sleep 5")
        let start = Date()
        XCTAssertThrowsError(try GHCLITokenProvider(candidates: [path], timeout: 0.5).token(for: "h")) {
            XCTAssertEqual($0 as? GitHubError, .ghTimeout)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    func testLargeStderrDoesNotDeadlock() throws {
        // ~200 KB > the typical 64 KB pipe buffer: if stderr were still piped and unread,
        // gh would block writing to it and this call would hang.
        let path = try script(#"yes "x" | head -c 200000 >&2; echo gho_ok"#)
        XCTAssertEqual(try GHCLITokenProvider(candidates: [path]).token(for: "h"), "gho_ok")
    }
}
