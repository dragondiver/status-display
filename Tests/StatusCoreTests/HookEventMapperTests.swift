import XCTest
@testable import StatusCore

final class HookEventMapperTests: XCTestCase {
    private func map(_ json: String, source: String = "claude-code") throws -> AgentEvent? {
        try HookEventMapper.event(source: source, payload: Data(json.utf8))
    }

    func testRunningEvents() throws {
        for hook in ["SessionStart", "UserPromptSubmit", "PostToolUse"] {
            let e = try map(#"{"hook_event_name":"\#(hook)","session_id":"abc","cwd":"/Users/f/Development/telefon-ai"}"#)
            XCTAssertEqual(e, AgentEvent(source: "claude-code", session: "abc", state: "running",
                                         name: "telefon-ai", project: "telefon-ai",
                                         path: "/Users/f/Development/telefon-ai"))
        }
    }

    // MARK: Pfad und Prompt (status-display#52)

    func testKeepsFullCwdAsPathAndLastComponentAsProject() throws {
        for hook in ["SessionStart", "PostToolUse", "Stop", "PermissionRequest"] {
            let e = try map(#"{"hook_event_name":"\#(hook)","session_id":"s","cwd":"/private/tmp/beispiel-1"}"#)
            XCTAssertEqual(e?.path, "/private/tmp/beispiel-1", hook)
            XCTAssertEqual(e?.project, "beispiel-1", hook)
            XCTAssertNil(e?.prompt, hook)
        }
    }

    func testRelativeOrMissingCwdGivesNoPath() throws {
        let relative = try map(#"{"hook_event_name":"PostToolUse","session_id":"s","cwd":"beispiel"}"#)
        XCTAssertNil(relative?.path)
        XCTAssertEqual(relative?.project, "beispiel")
        XCTAssertNoThrow(try relative?.validate())
        XCTAssertNil(try map(#"{"hook_event_name":"PostToolUse","session_id":"s"}"#)?.path)
    }

    func testUserPromptSubmitCarriesPromptWithLineBreaks() throws {
        let e = try map(#"{"hook_event_name":"UserPromptSubmit","session_id":"s","cwd":"/Users/kollegin-a/Development/beispiel","prompt":"Bitte die Tests ergänzen.\nDanach den Build prüfen."}"#)
        XCTAssertEqual(e?.state, "running")
        XCTAssertEqual(e?.prompt, "Bitte die Tests ergänzen.\nDanach den Build prüfen.")
        XCTAssertEqual(e?.path, "/Users/kollegin-a/Development/beispiel")
    }

    func testUserPromptSubmitWithoutPromptLeavesItOut() throws {
        // Codex: ob `prompt` mitkommt, ist ungeprüft – fehlt es, bleibt das Feld leer.
        let e = try map(#"{"hook_event_name":"UserPromptSubmit","session_id":"c","cwd":"/x/beispiel"}"#, source: "codex")
        XCTAssertEqual(e?.state, "running")
        XCTAssertNil(e?.prompt)
        XCTAssertNil(try map(#"{"hook_event_name":"UserPromptSubmit","session_id":"c","cwd":"/x","prompt":"  \n "}"#)?.prompt)
    }

    func testLongPromptIsShortenedBeforeLeavingTheHook() throws {
        let long = String(repeating: "a", count: 5_000)
        let e = try map(#"{"hook_event_name":"UserPromptSubmit","session_id":"s","cwd":"/x","prompt":"\#(long)"}"#)
        XCTAssertEqual(e?.prompt, String(repeating: "a", count: 300) + "…")
    }

    func testPermissionNotificationIsWaitingWithMessage() throws {
        let e = try map(#"{"hook_event_name":"Notification","session_id":"abc","cwd":"/x/rundfunk","notification_type":"permission_prompt","message":"Claude needs your permission to use Bash"}"#)
        XCTAssertEqual(e?.state, "waiting")
        XCTAssertEqual(e?.detail, "Claude needs your permission to use Bash")
    }

    func testIdleNotificationIsIgnored() throws {
        XCTAssertNil(try map(#"{"hook_event_name":"Notification","session_id":"a","cwd":"/x","notification_type":"idle_prompt","message":"Claude is waiting for your input"}"#))
        XCTAssertNil(try map(#"{"hook_event_name":"Notification","session_id":"a","cwd":"/x","message":"Claude is waiting for your input"}"#))
    }

    func testCodexPermissionRequest() throws {
        let e = try map(#"{"hook_event_name":"PermissionRequest","session_id":"c1","cwd":"/x/heim-agent","tool_name":"exec_command"}"#, source: "codex")
        XCTAssertEqual(e?.source, "codex")
        XCTAssertEqual(e?.state, "waiting")
        XCTAssertEqual(e?.detail, "wartet auf Freigabe: exec_command")
    }

    func testStopAndSessionEnd() throws {
        XCTAssertEqual(try map(#"{"hook_event_name":"Stop","session_id":"a","cwd":"/x"}"#)?.state, "done")
        XCTAssertEqual(try map(#"{"hook_event_name":"SessionEnd","session_id":"a","cwd":"/x"}"#)?.state, "ended")
    }

    func testUnknownOrIncompleteIsIgnored() throws {
        XCTAssertNil(try map(#"{"hook_event_name":"PreCompact","session_id":"a"}"#))
        XCTAssertNil(try map(#"{"session_id":"a"}"#))
        XCTAssertThrowsError(try map("kein json"))
    }
}
