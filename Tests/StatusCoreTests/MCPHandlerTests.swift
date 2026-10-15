import XCTest
@testable import StatusCore

final class MCPHandlerTests: XCTestCase {
    private var events: [AgentEvent] = []
    private lazy var handler = MCPHandler { self.events.append($0) }

    private func call(_ json: String, session: String? = nil) -> (HTTPResponse, [String: Any]) {
        var headers: [String: String] = [:]
        if let session { headers["mcp-session-id"] = session }
        let r = handler.handle(HTTPRequest(method: "POST", path: "/mcp", headers: headers, body: Data(json.utf8)))
        let obj = (try? JSONSerialization.jsonObject(with: r.body)) as? [String: Any] ?? [:]
        return (r, obj)
    }

    private func initialize() -> String {
        let (r, obj) = call(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","clientInfo":{"name":"copilot"}}}"#)
        XCTAssertEqual(r.status, 200)
        let result = obj["result"] as? [String: Any]
        XCTAssertEqual(result?["protocolVersion"] as? String, "2025-06-18")
        XCTAssertNotNil((result?["capabilities"] as? [String: Any])?["tools"])
        return r.headers["Mcp-Session-Id"]!
    }

    func testInitializeReturnsSessionID() {
        XCTAssertFalse(initialize().isEmpty)
    }

    func testNotificationIs202() {
        XCTAssertEqual(call(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#).0.status, 202)
    }

    func testToolsList() {
        let (_, obj) = call(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        let tools = (obj["result"] as? [String: Any])?["tools"] as? [[String: Any]]
        XCTAssertEqual(tools?.first?["name"] as? String, "report_status")
    }

    func testReportStatusCreatesEventWithClientAndSession() {
        let sid = initialize()
        let (_, obj) = call(#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"report_status","arguments":{"state":"waiting","name":"mise-en-place","detail":"Frage zur Migration"}}}"#, session: sid)
        XCTAssertNil((obj["result"] as? [String: Any])?["isError"])
        XCTAssertEqual(events, [AgentEvent(source: "mcp:copilot", session: sid, state: "waiting",
                                           name: "mise-en-place", detail: "Frage zur Migration")])
    }

    // MARK: path (status-display#52)

    func testToolSchemaHasOptionalPath() {
        let (_, obj) = call(#"{"jsonrpc":"2.0","id":10,"method":"tools/list"}"#)
        let tool = ((obj["result"] as? [String: Any])?["tools"] as? [[String: Any]])?.first
        let schema = tool?["inputSchema"] as? [String: Any]
        let path = (schema?["properties"] as? [String: Any])?["path"] as? [String: Any]
        XCTAssertEqual(path?["type"] as? String, "string")
        XCTAssertEqual(schema?["required"] as? [String], ["state", "name"])
    }

    func testReportStatusPassesPath() {
        let sid = initialize()
        let (_, obj) = call(#"{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"report_status","arguments":{"state":"running","name":"beispiel","path":"/Users/kollegin-a/Development/beispiel"}}}"#, session: sid)
        XCTAssertNil((obj["result"] as? [String: Any])?["isError"])
        XCTAssertEqual(events, [AgentEvent(source: "mcp:copilot", session: sid, state: "running", name: "beispiel",
                                           path: "/Users/kollegin-a/Development/beispiel")])
        XCTAssertNil(events.first?.prompt)
    }

    func testReportStatusWithoutPathStillWorks() {
        _ = call(#"{"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"report_status","arguments":{"state":"running","name":"beispiel"}}}"#)
        XCTAssertEqual(events.count, 1)
        XCTAssertNil(events.first?.path)
    }

    func testRelativePathIsToolError() {
        let (r, obj) = call(#"{"jsonrpc":"2.0","id":13,"method":"tools/call","params":{"name":"report_status","arguments":{"state":"running","name":"beispiel","path":"~/Development/beispiel"}}}"#)
        XCTAssertEqual(r.status, 200)
        let result = obj["result"] as? [String: Any]
        XCTAssertEqual(result?["isError"] as? Bool, true)
        let text = (result?["content"] as? [[String: Any]])?.first?["text"] as? String
        XCTAssertEqual(text, "path muss ein absoluter Pfad sein (beginnt mit /): ~/Development/beispiel")
        XCTAssertTrue(events.isEmpty)
    }

    func testInvalidStateIsToolErrorNotCrash() {
        let (r, obj) = call(#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"report_status","arguments":{"state":"busy","name":"x"}}}"#)
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual((obj["result"] as? [String: Any])?["isError"] as? Bool, true)
        XCTAssertTrue(events.isEmpty)
    }

    func testWithoutSessionFallsBackToName() {
        _ = call(#"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"report_status","arguments":{"state":"running","name":"heim-agent"}}}"#)
        XCTAssertEqual(events.first?.session, "heim-agent")
        XCTAssertEqual(events.first?.source, "mcp:mcp")
    }

    func testUnknownMethodAndGarbage() {
        let (_, obj) = call(#"{"jsonrpc":"2.0","id":6,"method":"resources/list"}"#)
        XCTAssertEqual((obj["error"] as? [String: Any])?["code"] as? Int, -32601)
        let (_, bad) = call("{kaputt")
        XCTAssertEqual((bad["error"] as? [String: Any])?["code"] as? Int, -32700)
        let get = handler.handle(HTTPRequest(method: "GET", path: "/mcp"))
        XCTAssertEqual(get.status, 405)
    }

    func testMissingMethodIsInvalidRequest() {
        let (_, obj) = call(#"{"jsonrpc":"2.0","id":7}"#)
        XCTAssertEqual((obj["error"] as? [String: Any])?["code"] as? Int, -32600)
    }

    func testSessionCapEvictsOldest() {
        let firstSession = initialize()
        var lastSession = firstSession
        for _ in 0..<256 {
            lastSession = initialize()
        }

        let (_, oldObj) = call(#"{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"report_status","arguments":{"state":"running","name":"x"}}}"#, session: firstSession)
        XCTAssertNil((oldObj["result"] as? [String: Any])?["isError"])
        XCTAssertEqual(events.last?.source, "mcp:mcp")

        let (_, newObj) = call(#"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"report_status","arguments":{"state":"running","name":"y"}}}"#, session: lastSession)
        XCTAssertNil((newObj["result"] as? [String: Any])?["isError"])
        XCTAssertEqual(events.last?.source, "mcp:copilot")
    }
}
