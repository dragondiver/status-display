import XCTest
@testable import StatusCore

final class IngressRouterTests: XCTestCase {
    private var events: [AgentEvent] = []
    private var statuses: [(String, TimeInterval?)] = []

    private func router(mcp: ((HTTPRequest) -> HTTPResponse)? = nil) -> IngressRouter {
        IngressRouter(token: "geheim", knownPresets: Locked(["deep-focus", "available"]), mcp: mcp,
                      onEvent: { self.events.append($0) }, onStatus: { self.statuses.append(($0, $1)) })
    }

    private func req(_ method: String, _ path: String, body: String = "", token: String? = "geheim") -> HTTPRequest {
        var h: [String: String] = [:]
        if let token { h["authorization"] = "Bearer \(token)" }
        return HTTPRequest(method: method, path: path, headers: h, body: Data(body.utf8))
    }

    func testHealthNeedsNoToken() {
        XCTAssertEqual(router().handle(req("GET", "/v1/health", token: nil)).status, 200)
    }

    func testMissingOrWrongTokenIs401() {
        XCTAssertEqual(router().handle(req("POST", "/v1/events", body: "{}", token: nil)).status, 401)
        XCTAssertEqual(router().handle(req("POST", "/v1/events", body: "{}", token: "falsch")).status, 401)
        XCTAssertTrue(events.isEmpty)
    }

    func testValidEventIsDelivered() {
        let r = router().handle(req("POST", "/v1/events",
            body: #"{"source":"claude-code","session":"s1","state":"running","project":"telefon-ai"}"#))
        XCTAssertEqual(r.status, 202)
        XCTAssertEqual(events, [AgentEvent(source: "claude-code", session: "s1", state: "running", project: "telefon-ai")])
    }

    func testEventCarriesPathAndPrompt() {
        let r = router().handle(req("POST", "/v1/events",
            body: #"{"source":"claude-code","session":"s1","state":"running","path":"/private/tmp/beispiel-1","prompt":"Zeile 1\nZeile 2"}"#))
        XCTAssertEqual(r.status, 202)
        XCTAssertEqual(events.first?.path, "/private/tmp/beispiel-1")
        XCTAssertEqual(events.first?.prompt, "Zeile 1\nZeile 2")
    }

    func testRelativePathIs400() {
        let r = router().handle(req("POST", "/v1/events",
            body: #"{"source":"a","session":"b","state":"running","path":"beispiel"}"#))
        XCTAssertEqual(r.status, 400)
        XCTAssertTrue(String(decoding: r.body, as: UTF8.self).contains("absoluter Pfad"))
        XCTAssertTrue(events.isEmpty)
    }

    func testBrokenJSONAndInvalidStateAre400() {
        XCTAssertEqual(router().handle(req("POST", "/v1/events", body: "{kaputt")).status, 400)
        let r = router().handle(req("POST", "/v1/events", body: #"{"source":"a","session":"b","state":"busy"}"#))
        XCTAssertEqual(r.status, 400)
        XCTAssertTrue(String(decoding: r.body, as: UTF8.self).contains("unbekannter Zustand"))
        XCTAssertTrue(events.isEmpty)
    }

    func testStatusKnownAndUnknown() {
        XCTAssertEqual(router().handle(req("POST", "/v1/status", body: #"{"preset":"deep-focus","minutes":30}"#)).status, 202)
        XCTAssertEqual(statuses.first?.0, "deep-focus")
        XCTAssertEqual(statuses.first?.1, 1800)
        XCTAssertEqual(router().handle(req("POST", "/v1/status", body: #"{"preset":"nix"}"#)).status, 400)
        XCTAssertEqual(statuses.count, 1)
    }

    func testInvalidMinutesAreRejected() {
        for minutes in ["-5", "0", "1e308"] {
            let r = router().handle(req("POST", "/v1/status", body: #"{"preset":"deep-focus","minutes":\#(minutes)}"#))
            XCTAssertEqual(r.status, 400, "minutes=\(minutes)")
            XCTAssertTrue(String(decoding: r.body, as: UTF8.self).contains("ungültige Dauer"), "minutes=\(minutes)")
        }
        XCTAssertTrue(statuses.isEmpty)
    }

    func testMCPIsForwardedOnlyWithToken() {
        let r = router(mcp: { _ in HTTPResponse(status: 299) })
        XCTAssertEqual(r.handle(req("POST", "/mcp", body: "{}")).status, 299)
        XCTAssertEqual(r.handle(req("POST", "/mcp", body: "{}", token: nil)).status, 401)
        XCTAssertEqual(router().handle(req("POST", "/mcp", body: "{}")).status, 404)
    }

    func testUnknownPathIs404() {
        XCTAssertEqual(router().handle(req("GET", "/etc/passwd")).status, 404)
    }
}
