import Foundation
import Testing
@testable import VibeCatCore

private let origin = Origin(app: "com.googlecode.iterm2", termSession: "w0t1p0")

private func raw(_ json: String) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
}

/// Compares two events ignoring `id` — every `VibeEvent` gets a fresh UUID, so
/// an equivalence check has to strip it or it can never pass.
private func stripID(_ e: VibeEvent) -> VibeEvent {
    var e = e
    e.id = ""
    return e
}

// MARK: - A minimal, hand-built config (not claude-code) for the adapter's own behaviour

private let stub = GenericAdapterConfig(
    id: "stub-cli",
    displayName: "Stub CLI",
    icon: "/tmp/nonexistent-icon-for-test.png",
    jumpStrategy: .vscode,
    reports: [.running, .done],
    eventNameKey: "event",
    sessionKey: "sid",
    cwdKey: "dir",
    modelKey: "model",
    effortKey: "effort",
    events: [
        "start": EventRule(kind: .running),
        "finish": EventRule(kind: .done, titleKey: "reason"),
        "ask": EventRule(kind: .permission, wantsReply: true, bodyKey: "msg",
                         choices: [Choice(id: "yes", label: "Yes"), Choice(id: "no", label: "No")]),
    ])

@Test func configValuesSurfaceThroughTheProtocol() {
    let a = GenericAdapter(config: stub)
    #expect(a.id == "stub-cli")
    #expect(a.displayName == "Stub CLI")
    #expect(a.icon == "/tmp/nonexistent-icon-for-test.png")
    #expect(a.jumpStrategy == .vscode)
    #expect(a.reports == [.running, .done])
}

@Test func aDeclaredEventNameMapsToItsConfiguredKind() throws {
    let a = GenericAdapter(config: stub)
    let e = try #require(try a.parse(raw(#"{"event":"start","sid":"s1","dir":"/d"}"#), origin: origin))
    #expect(e.kind == .running)
    #expect(e.cli == "stub-cli")
    #expect(e.session == "s1")
    #expect(e.cwd == "/d")
}

@Test func titleKeyBodyKeyWantsReplyAndChoicesAllCarryThrough() throws {
    let a = GenericAdapter(config: stub)
    let e = try #require(try a.parse(raw(#"""
      {"event":"ask","sid":"s1","dir":"/d","msg":"proceed?"}
      """#), origin: origin))
    #expect(e.kind == .permission)
    #expect(e.wantsReply == true)
    #expect(e.body == "proceed?")
    #expect(e.choices?.map(\.id) == ["yes", "no"])
}

@Test func modelAndEffortAreReadUnconditionallyWhenConfigured() throws {
    let a = GenericAdapter(config: stub)
    let e = try #require(try a.parse(raw(#"""
      {"event":"start","sid":"s1","dir":"/d","model":"Opus","effort":"high"}
      """#), origin: origin))
    #expect(e.model == "Opus")
    #expect(e.effort == "high")
}

@Test func anUndeclaredEventNameIsIgnoredNotErrored() throws {
    let a = GenericAdapter(config: stub)
    let e = try a.parse(raw(#"{"event":"totally-unknown","sid":"s1","dir":"/d"}"#), origin: origin)
    #expect(e == nil)
}

@Test func aMissingEventNameKeyThrows() {
    let a = GenericAdapter(config: stub)
    #expect(throws: AdapterError.missingField("event")) {
        _ = try a.parse(try raw(#"{"sid":"s1","dir":"/d"}"#), origin: origin)
    }
}

@Test func aMissingSessionKeyThrowsEvenForAnUndeclaredEvent() {
    // Mirrors ClaudeCodeAdapter's own order: the required fields are checked
    // before the event name is looked up, so a missing session throws even
    // when the event itself would have been ignored.
    let a = GenericAdapter(config: stub)
    #expect(throws: AdapterError.missingField("sid")) {
        _ = try a.parse(try raw(#"{"event":"never-declared","dir":"/d"}"#), origin: origin)
    }
}

@Test func aMissingCwdKeyThrows() {
    let a = GenericAdapter(config: stub)
    #expect(throws: AdapterError.missingField("dir")) {
        _ = try a.parse(try raw(#"{"event":"start","sid":"s1"}"#), origin: origin)
    }
}

@Test func aWrongTypeForADeclaredKeyThrowsLikeAMissingKey() {
    // JSON's `session_id: 123` is well-formed JSON but the wrong shape; `as?
    // String` already turns "wrong type" into "missing" and the same guard
    // handles both, so no separate branch is needed.
    let a = GenericAdapter(config: stub)
    #expect(throws: AdapterError.missingField("sid")) {
        _ = try a.parse(try raw(#"{"event":"start","sid":123,"dir":"/d"}"#), origin: origin)
    }
}

@Test func everyEventCarriesAFreshId() throws {
    let a = GenericAdapter(config: stub)
    let p = try raw(#"{"event":"start","sid":"s1","dir":"/d"}"#)
    let e1 = try #require(try a.parse(p, origin: origin))
    let e2 = try #require(try a.parse(p, origin: origin))
    #expect(e1.id != e2.id)
}

// MARK: - The load-bearing test: express claude-code itself as generic-adapter data

/// `ClaudeCodeAdapter`, rebuilt as pure `GenericAdapterConfig` values — no
/// Swift code specific to Claude Code, only the four things the plan allows:
/// which keys carry the event name / session / cwd, and per-event-name kind +
/// (title, body, wantsReply, choices).
private let claudeCodeAsData = GenericAdapterConfig(
    id: "claude-code",
    displayName: "Claude Code",
    jumpStrategy: .terminalSession,
    reports: [.running, .done, .permission, .question, .failed],
    eventNameKey: "hook_event_name",
    sessionKey: "session_id",
    cwdKey: "cwd",
    modelKey: "model",
    effortKey: "reasoning_effort",
    events: [
        "PreToolUse": EventRule(kind: .permission, wantsReply: true, titleKey: "tool_name"),
        "PostToolUse": EventRule(kind: .running),
        "Notification": EventRule(kind: .question, bodyKey: "message"),
        "Stop": EventRule(kind: .done),
        "SubagentStop": EventRule(kind: .running),
    ])

private let claudeCode = ClaudeCodeAdapter()
private let claudeCodeGeneric = GenericAdapter(config: claudeCodeAsData)

@Test func stopRoundTripsExactlyAsGenericData() throws {
    let payload = try raw(#"{"hook_event_name":"Stop","session_id":"s1","cwd":"/Users/me/dev/api"}"#)
    let a = try #require(try claudeCode.parse(payload, origin: origin))
    let b = try #require(try claudeCodeGeneric.parse(payload, origin: origin))
    #expect(stripID(a) == stripID(b))
}

@Test func postToolUseRoundTripsExactlyAsGenericData() throws {
    let payload = try raw(#"""
      {"hook_event_name":"PostToolUse","session_id":"s1","cwd":"/dev/api","tool_name":"Bash"}
      """#)
    let a = try #require(try claudeCode.parse(payload, origin: origin))
    let b = try #require(try claudeCodeGeneric.parse(payload, origin: origin))
    #expect(stripID(a) == stripID(b))
}

@Test func subagentStopRoundTripsExactlyAsGenericData() throws {
    let payload = try raw(#"{"hook_event_name":"SubagentStop","session_id":"s1","cwd":"/dev/api"}"#)
    let a = try #require(try claudeCode.parse(payload, origin: origin))
    let b = try #require(try claudeCodeGeneric.parse(payload, origin: origin))
    #expect(stripID(a) == stripID(b))
}

@Test func notificationRoundTripsExactlyAsGenericData() throws {
    let payload = try raw(#"""
      {"hook_event_name":"Notification","session_id":"s1","cwd":"/dev/api",
       "message":"Claude needs your permission"}
      """#)
    let a = try #require(try claudeCode.parse(payload, origin: origin))
    let b = try #require(try claudeCodeGeneric.parse(payload, origin: origin))
    #expect(stripID(a) == stripID(b))
}

@Test func modelAndEffortRoundTripAsGenericData() throws {
    let payload = try raw(#"""
      {"hook_event_name":"Stop","session_id":"s1","cwd":"/dev/api",
       "model":"Opus 4.8","reasoning_effort":"high"}
      """#)
    let a = try #require(try claudeCode.parse(payload, origin: origin))
    let b = try #require(try claudeCodeGeneric.parse(payload, origin: origin))
    #expect(stripID(a) == stripID(b))
}

@Test func anUnhandledHookIsIgnoredIdenticallyAsGenericData() throws {
    let payload = try raw(#"{"hook_event_name":"SessionStart","session_id":"s1","cwd":"/dev/api"}"#)
    let a = try claudeCode.parse(payload, origin: origin)
    let b = try claudeCodeGeneric.parse(payload, origin: origin)
    #expect(a == nil)
    #expect(b == nil)
}

@Test func aMissingSessionIdThrowsIdenticallyAsGenericData() {
    let payload = try! raw(#"{"hook_event_name":"Stop","cwd":"/dev/api"}"#)
    #expect(throws: AdapterError.missingField("session_id")) {
        _ = try claudeCode.parse(payload, origin: origin)
    }
    #expect(throws: AdapterError.missingField("session_id")) {
        _ = try claudeCodeGeneric.parse(payload, origin: origin)
    }
}

/// **The finding.** `PreToolUse` is where the generalisation stops being free.
/// `kind`, `wantsReply` and `title` (a flat `tool_name` lookup) round-trip
/// exactly. `body` and `choices` do not, and the plan asks for this to be
/// reported rather than papered over by widening the config:
///
/// - `ClaudeCodeAdapter.command(from:)` walks *into* `tool_input` with a
///   preferred-key list (`command`, `file_path`, `pattern`, `url`, `query`,
///   `prompt`, `notebook_path`, `path`) and a sorted-keys fallback. That is a
///   nested key path plus a multi-step transform — the thing the plan's
///   Global Constraints call "the road to a DSL" — so `EventRule.bodyKey`
///   (one flat top-level key) cannot reach it. Generic `body` is `nil` here.
/// - The "always" choice's label embeds the tool name into a sentence
///   (`"Allow every \(tool_name) call this session"`). `EventRule.choices` is
///   a static list; there is nothing in a static declaration that can build a
///   sentence from the payload. Generic `choices` carries no dynamic label —
///   this test declares no choices for `PreToolUse` at all, to keep the
///   config honest about what it can express rather than shipping a close but
///   wrong static list.
///
/// Both gaps are real preset behaviour a hand-written adapter still needs;
/// neither is small enough to add to `EventRule` without turning it into the
/// second parser §3 rules out. That is the honest outcome the plan asked for.
@Test func preToolUseKindAndTitleRoundTripButBodyAndChoicesDoNotAndThatIsTheFinding() throws {
    let payload = try raw(#"""
      {"hook_event_name":"PreToolUse","session_id":"s1","cwd":"/Users/me/dev/api",
       "tool_name":"Bash","tool_input":{"command":"rm -rf build/"}}
      """#)
    let a = try #require(try claudeCode.parse(payload, origin: origin))
    let b = try #require(try claudeCodeGeneric.parse(payload, origin: origin))

    // What matches:
    #expect(a.kind == b.kind)
    #expect(a.wantsReply == b.wantsReply)
    #expect(a.title == b.title)
    #expect(a.session == b.session)
    #expect(a.cwd == b.cwd)

    // What does not — asserted explicitly so a future widening of EventRule
    // that makes these equal is a deliberate, visible change, not an accident:
    #expect(a.body == "rm -rf build/")
    #expect(b.body == nil)
    #expect(a.choices?.map(\.id) == ["allow", "always", "deny"])
    #expect(b.choices == nil)
}
