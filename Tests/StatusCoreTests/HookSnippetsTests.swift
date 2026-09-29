import XCTest
@testable import StatusCore

final class HookSnippetsTests: XCTestCase {
    private func command(_ json: String, event: String = "Stop") throws -> [String: Any] {
        let obj = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        let hooks = obj["hooks"] as! [String: Any]
        return ((hooks[event] as! [[String: Any]])[0]["hooks"] as! [[String: Any]])[0]
    }

    func testClaudeHooksJSONShape() throws {
        let json = HookSnippets.hooksJSON(entry: "/tmp/status-display/hook",
                                          source: "claude-code", events: HookSnippets.claudeEvents)
        let obj = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        let hooks = obj["hooks"] as! [String: Any]
        XCTAssertEqual(Set(hooks.keys), Set(HookSnippets.claudeEvents))
        let entry = try command(json)
        XCTAssertEqual(entry["type"] as? String, "command")
        XCTAssertEqual(entry["command"] as? String, "'/tmp/status-display/hook' claude-code")
        XCTAssertEqual(entry["timeout"] as? Int, 2)
    }

    /// status-display#42: Der Block zum Kopieren nennt den festen Einstieg, dessen Pfad wegen
    /// „Application Support“ ein Leerzeichen enthält und deshalb gequotet sein muss.
    func testFixedEntryWithSpaceIsQuotedForClaudeAndCodex() throws {
        let entryPath = AppSupport(directory: URL(fileURLWithPath: "/Users/florian/Library/Application Support/status-display"))
            .hookEntryURL.path
        XCTAssertEqual(entryPath, "/Users/florian/Library/Application Support/status-display/hook")
        let claude = try command(HookSnippets.hooksJSON(entry: entryPath, source: "claude-code",
                                                        events: HookSnippets.claudeEvents))
        XCTAssertEqual(claude["command"] as? String,
                       "'/Users/florian/Library/Application Support/status-display/hook' claude-code")
        let codex = try command(HookSnippets.hooksJSON(entry: entryPath, source: "codex",
                                                       events: HookSnippets.codexEvents), event: "PermissionRequest")
        XCTAssertEqual(codex["command"] as? String,
                       "'/Users/florian/Library/Application Support/status-display/hook' codex")
    }

    func testEntryPathWithSingleQuoteIsShellEscaped() throws {
        let entry = try command(HookSnippets.hooksJSON(entry: "/Users/o'neil/Library/Application Support/status-display/hook",
                                                       source: "claude-code", events: HookSnippets.claudeEvents))
        XCTAssertEqual(entry["command"] as? String,
                       "'/Users/o'\\''neil/Library/Application Support/status-display/hook' claude-code")
    }

    func testMCPJSONContainsTokenHeader() throws {
        let obj = try JSONSerialization.jsonObject(with: Data(HookSnippets.mcpJSON(port: 47615, token: "abc").utf8)) as! [String: Any]
        let server = obj["status-display"] as! [String: Any]
        XCTAssertEqual(server["url"] as? String, "http://127.0.0.1:47615/mcp")
        XCTAssertEqual((server["headers"] as? [String: String])?["Authorization"], "Bearer abc")
    }
}
