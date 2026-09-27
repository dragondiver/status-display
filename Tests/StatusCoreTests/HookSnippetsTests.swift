import XCTest
@testable import StatusCore

final class HookSnippetsTests: XCTestCase {
    func testClaudeHooksJSONShape() throws {
        let json = HookSnippets.hooksJSON(executable: "/Applications/StatusDisplay.app/Contents/MacOS/StatusDisplay",
                                          source: "claude-code", events: HookSnippets.claudeEvents)
        let obj = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        let hooks = obj["hooks"] as! [String: Any]
        XCTAssertEqual(Set(hooks.keys), Set(HookSnippets.claudeEvents))
        let entry = ((hooks["Stop"] as! [[String: Any]])[0]["hooks"] as! [[String: Any]])[0]
        XCTAssertEqual(entry["type"] as? String, "command")
        XCTAssertEqual(entry["command"] as? String, "'/Applications/StatusDisplay.app/Contents/MacOS/StatusDisplay' hook claude-code")
        XCTAssertEqual(entry["timeout"] as? Int, 2)
    }

    func testExecutablePathWithSingleQuoteIsShellEscaped() throws {
        let json = HookSnippets.hooksJSON(executable: "/Users/o'neil/Apps/Status Display.app/Contents/MacOS/StatusDisplay",
                                          source: "claude-code", events: HookSnippets.claudeEvents)
        let obj = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        let hooks = obj["hooks"] as! [String: Any]
        let entry = ((hooks["Stop"] as! [[String: Any]])[0]["hooks"] as! [[String: Any]])[0]
        XCTAssertEqual(entry["command"] as? String,
                       "'/Users/o'\\''neil/Apps/Status Display.app/Contents/MacOS/StatusDisplay' hook claude-code")
    }

    func testMCPJSONContainsTokenHeader() throws {
        let obj = try JSONSerialization.jsonObject(with: Data(HookSnippets.mcpJSON(port: 47615, token: "abc").utf8)) as! [String: Any]
        let server = obj["status-display"] as! [String: Any]
        XCTAssertEqual(server["url"] as? String, "http://127.0.0.1:47615/mcp")
        XCTAssertEqual((server["headers"] as? [String: String])?["Authorization"], "Bearer abc")
    }
}
