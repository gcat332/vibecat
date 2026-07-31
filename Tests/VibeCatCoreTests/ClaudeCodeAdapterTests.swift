import Foundation
import Testing
@testable import VibeCatCore

private let adapter = ClaudeCodeAdapter()
private let origin = Origin(app: "com.googlecode.iterm2", termSession: "w0t1p0")

private func raw(_ json: String) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
}

@Test func preToolUseBecomesAPermissionThatWantsAReply() throws {
    let e = try #require(try adapter.parse(raw("""
      {"hook_event_name":"PreToolUse","session_id":"s1","cwd":"/Users/me/dev/api",
       "tool_name":"Bash","tool_input":{"command":"rm -rf build/"}}
      """), origin: origin))

    #expect(e.cli == "claude-code")
    #expect(e.kind == .permission)
    #expect(e.session == "s1")
    #expect(e.title == "Bash")
    #expect(e.body == "rm -rf build/")
    #expect(e.wantsReply == true)
    #expect(e.multi == false)
    #expect(e.choices?.map(\.id) == ["allow", "always", "deny"])
    #expect(e.origin == origin)
}

@Test func stopBecomesDoneAndWantsNoReply() throws {
    let e = try #require(try adapter.parse(raw("""
      {"hook_event_name":"Stop","session_id":"s1","cwd":"/Users/me/dev/api"}
      """), origin: origin))
    #expect(e.kind == .done)
    #expect(e.wantsReply == false)
}

@Test func notificationBecomesAQuestion() throws {
    let e = try #require(try adapter.parse(raw("""
      {"hook_event_name":"Notification","session_id":"s1","cwd":"/dev/api",
       "message":"Claude needs your permission"}
      """), origin: origin))
    #expect(e.kind == .question)
    #expect(e.body == "Claude needs your permission")
}

@Test func modelAndEffortAreCarriedWhenPresent() throws {
    let e = try #require(try adapter.parse(raw("""
      {"hook_event_name":"Stop","session_id":"s1","cwd":"/dev/api",
       "model":"Opus 4.8","reasoning_effort":"high"}
      """), origin: origin))
    #expect(e.model == "Opus 4.8")
    #expect(e.effort == "high")
}

@Test func aMissingSessionIdIsAnError() {
    #expect(throws: AdapterError.missingField("session_id")) {
        _ = try adapter.parse(try raw(#"{"hook_event_name":"Stop","cwd":"/dev/api"}"#),
                              origin: origin)
    }
}

@Test func anUnhandledHookIsIgnoredRatherThanFatal() throws {
    let e = try adapter.parse(raw("""
      {"hook_event_name":"SessionStart","session_id":"s1","cwd":"/dev/api"}
      """), origin: origin)
    #expect(e == nil)
}

@Test func everyEventCarriesAUniqueId() throws {
    let a = try #require(try adapter.parse(raw(#"{"hook_event_name":"Stop","session_id":"s","cwd":"/d"}"#), origin: origin))
    let b = try #require(try adapter.parse(raw(#"{"hook_event_name":"Stop","session_id":"s","cwd":"/d"}"#), origin: origin))
    #expect(a.id != b.id)
}

@Test func postToolUseReturnsTheSessionToRunning() throws {
    let e = try #require(try adapter.parse(raw("""
      {"hook_event_name":"PostToolUse","session_id":"s1","cwd":"/dev/api",
       "tool_name":"Bash"}
      """), origin: origin))
    #expect(e.kind == .running)
    #expect(e.wantsReply == false)
}

@Test func toolDetailFallsBackThroughKnownKeysThenAnyString() throws {
    func body(_ toolInput: String) throws -> String? {
        try adapter.parse(raw("""
          {"hook_event_name":"PreToolUse","session_id":"s1","cwd":"/d",
           "tool_name":"T","tool_input":\(toolInput)}
          """), origin: origin)?.body
    }
    #expect(try body(#"{"pattern":"handleRequest"}"#) == "handleRequest")
    #expect(try body(#"{"url":"https://example.com"}"#) == "https://example.com")
    #expect(try body(#"{"prompt":"find the bug"}"#) == "find the bug")
    // unknown key: still shows something rather than nothing
    #expect(try body(#"{"somethingNew":"a value"}"#) == "a value")
    // nothing usable at all
    #expect(try body(#"{"count":3}"#) == nil)
    #expect(try body(#"{}"#) == nil)
    #expect(try body(#""just a string""#) == nil)
}
