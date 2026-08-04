import Foundation
import Testing
import VibeCatCore
@testable import VibeCatHookKit
@testable import VibeCatTransport
@testable import VibeCatUI
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

private func tempPath(_ n: String) -> String { "/tmp/vibecat-e2e-\(n)-\(getpid()).sock" }

/// A hook event travels all the way into a session store and an answer travels
/// all the way back — the whole point of the pipeline, in one test.
@Test func aPermissionPromptReachesTheStoreAndIsAnswered() async throws {
    let path = tempPath("full")
    let store = StoreBox()

    let server = SocketServer(path: path)
    try server.start { event in
        store.apply(event, now: Date(timeIntervalSince1970: 1_000_000))
        return event.wantsReply ? Reply(id: event.id, choice: "allow") : nil
    }
    defer { server.stop() }

    let runner = HookRunner(
        registry: SourceRegistry(adapters: [ClaudeCodeAdapter()]),
        client: SocketClient(path: path, deadline: 1.0),
        env: ["__CFBundleIdentifier": "com.googlecode.iterm2",
              "TERM_SESSION_ID": "w0t1p0:ABC"])

    let out = runner.run(cli: "claude-code", stdin: Data("""
      {"hook_event_name":"PreToolUse","session_id":"s1","cwd":"/Users/me/dev/api",
       "tool_name":"Bash","tool_input":{"command":"rm -rf build/"}}
      """.utf8))

    #expect(out?.contains("\"permissionDecision\":\"allow\"") == true)

    let snapshot = store.snapshot()
    #expect(snapshot.aggregate == .waiting)
    // #expect is a soft assertion, so indexing after it would trap and take the
    // whole suite down instead of failing this one test. #require stops here.
    let session = try #require(snapshot.sessions.first)
    #expect(snapshot.sessions.count == 1)
    #expect(session.project == "api")
    // Two fields, not one joined string: the sentence and the command reach the
    // row separately so the row can emphasise the command (see `Session.Activity`).
    #expect(session.activity == Session.Activity(sentence: "Bash", command: "rm -rf build/"))
    #expect(session.origin.termSession == "w0t1p0:ABC")
}

@Test func threeSessionsAggregateToTheMostUrgent() async throws {
    let path = tempPath("three")
    let store = StoreBox()
    let server = SocketServer(path: path)
    try server.start { event in
        store.apply(event, now: Date(timeIntervalSince1970: 1_000_000))
        return nil
    }
    defer { server.stop() }

    let client = SocketClient(path: path, deadline: 1.0)
    for (session, kind) in [("a", Kind.running), ("b", .running), ("c", .permission)] {
        client.send(try WireCodec.encode(
            VibeEvent(id: session, cli: "claude-code", kind: kind,
                      session: session, cwd: "/dev/\(session)")))
    }

    try await waitUntil { store.snapshot().sessions.count == 3 }
    let snapshot = store.snapshot()
    #expect(snapshot.aggregate == .waiting)
    #expect(snapshot.counts[.running] == 2)
    #expect(snapshot.counts[.waiting] == 1)
}

/// The one deadline the answered-pipeline test hands its client, named once so the
/// assertion window inside it cannot drift shorter than it. A window shorter than
/// the deadline the code under test may legitimately use is a stopwatch on this
/// machine, not a test of the behaviour.
private let clientAnswerDeadline: TimeInterval = 5.0

/// The whole point of the plan, over a real socket: a permission event goes in
/// as JSON, the island answers it, and claude-code's own decision shape comes
/// back out.
///
/// `HookRunner.run` below is deliberately handed to a real `Thread`, not
/// `Task.detached` — it blocks the calling thread until answered (the same
/// shape `SocketServer`'s own accept/serve threads use, for the identical
/// reason). `Task.detached` draws from Swift's small, shared cooperative
/// pool; parking one of those for however long a human takes to answer is
/// exactly the hazard this plan's own warning describes — it passes a
/// filtered run and can fail roughly two thirds of full-suite runs, because
/// the *other* tests running at the same time are what actually exhausts the
/// pool. `AppModel.ingest` itself already makes this exact distinction (see
/// its own doc comment on `applyAndNotify`); this test's plumbing mirrors it.
@MainActor @Test func aPermissionAnsweredInTheIslandReachesTheCLI() async throws {
    let path = tempPath("answered")
    let appModel = AppModel(socketPath: path)
    try appModel.start()
    defer { appModel.stop() }

    let runner = HookRunner(
        registry: SourceRegistry(adapters: [ClaudeCodeAdapter()]),
        client: SocketClient(path: path, deadline: 1.0, answerDeadline: clientAnswerDeadline),
        env: ["__CFBundleIdentifier": "com.googlecode.iterm2",
              "TERM_SESSION_ID": "w0t1p0:ABC"])

    let stdin = Data("""
      {"hook_event_name":"PreToolUse","session_id":"s1","cwd":"/Users/me/dev/api",
       "tool_name":"Bash","tool_input":{"command":"ls"}}
      """.utf8)

    let output = OutputBox()
    Thread.detachNewThread {
        output.set(runner.run(cli: "claude-code", stdin: stdin))
    }

    // Poll rather than a fixed sleep, for the same reason
    // NotchControllerTests.aLapsedQuestionClosesTheDrawer does: reaching the
    // main actor after ingest's own Task hop is not instant under full-suite
    // parallel load.
    let arrived = Date().addingTimeInterval(2)
    while appModel.pending == nil, Date() < arrived {
        try await Task.sleep(for: .milliseconds(10))
    }
    let pending = try #require(appModel.pending, "the question never reached the island")
    // "The island answers it": AppModel.answer is the one call a real
    // click-driven UI would eventually make too (see NotchController's own
    // setQuestion/click, Task 8) — calling it directly here is what stands
    // in for a rendered tap, exactly as this whole plan's own PipelineTests
    // already stand in for a real hook process.
    appModel.answer(Reply(id: pending.id, choice: "allow"))

    // Bounded by the client's **own** `answerDeadline` above, plus slack — not by
    // an arbitrary two seconds, which is what this line used to say.
    //
    // The hook is *permitted* to take up to `answerDeadline` before it gives up
    // and fails open. Waiting less than that does not test the behaviour, it
    // tests how fast this machine happens to be: the round trip has to cross a
    // real socket, a real detached thread, and `ingest`'s own hop to the main
    // actor. Measured, that bound was the whole flake — it failed 2 runs in 4 at
    // 647 tests, having failed about 1 in 20 when the suite was 40% smaller, and
    // every failure read `output.value == nil` rather than a wrong decision. The
    // assertion window was simply shorter than the deadline the code under test
    // is allowed to use.
    //
    // Still bounded, and still fails rather than hanging: if the reply never
    // arrives the hook fails open and writes its own default, so `output.value`
    // becomes non-nil without `"allow"` in it and the expectation below fails on
    // content instead of on time.
    let answered = Date().addingTimeInterval(clientAnswerDeadline + 2)
    while output.value == nil, Date() < answered {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(output.value?.contains("\"permissionDecision\":\"allow\"") == true)
}

/// And the property that outranks it: nobody answers, and the CLI still gets
/// its own prompt rather than a hung terminal.
///
/// A short `answerDeadline` (not the real 20s default) so this test itself
/// stays fast — `HookRunner` carries it onto the event
/// (`event.answerDeadline = client.answerDeadline`), which is what
/// `PendingQuestion`'s own expiry is built from, so the hook and the island
/// agree on the same short bound rather than the hook alone giving up early.
@MainActor @Test func anUnansweredPermissionFailsOpen() async throws {
    let path = tempPath("unanswered")
    let appModel = AppModel(socketPath: path)
    try appModel.start()
    defer { appModel.stop() }

    let runner = HookRunner(
        registry: SourceRegistry(adapters: [ClaudeCodeAdapter()]),
        client: SocketClient(path: path, deadline: 1.0, answerDeadline: 0.1),
        env: ["__CFBundleIdentifier": "com.googlecode.iterm2",
              "TERM_SESSION_ID": "w0t1p0:ABC"])

    let stdin = Data("""
      {"hook_event_name":"PreToolUse","session_id":"s2","cwd":"/Users/me/dev/api",
       "tool_name":"Bash","tool_input":{"command":"ls"}}
      """.utf8)

    let output = OutputBox()
    Thread.detachNewThread {
        output.set(runner.run(cli: "claude-code", stdin: stdin))
    }

    // Confirm the question actually reached the island before letting nobody
    // answer it — otherwise this would only prove that an event with no
    // listener at all produces no output, which every fire-and-forget event
    // already does, and would say nothing about failing open specifically.
    let arrived = Date().addingTimeInterval(2)
    while appModel.pending == nil, Date() < arrived {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(appModel.pending != nil, "the question never reached the island")

    // Nobody answers. HookRunner.run must still return — nil, since there is
    // nothing to print — rather than hang the calling thread past its own
    // answerDeadline.
    let gaveUp = Date().addingTimeInterval(2)
    while !output.isDone, Date() < gaveUp {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(output.isDone, "the hook never returned — it hung waiting for an answer nobody gave")
    #expect(output.value == nil, "an unanswered question printed something instead of staying silent")
}

// MARK: - helpers

private final class StoreBox: @unchecked Sendable {
    private let lock = NSLock()
    private var store = SessionStore()
    func apply(_ e: VibeEvent, now: Date) { lock.lock(); store.apply(e, now: now); lock.unlock() }
    func snapshot() -> SessionStore { lock.lock(); defer { lock.unlock() }; return store }
}

/// A thread-safe box for `HookRunner.run`'s return value — set from the real
/// `Thread` the run happens on, read from the test's own main-actor task.
/// `isDone` is distinct from `value != nil`: the hook returning nil (no
/// output) is itself a meaningful, expected outcome for
/// `anUnansweredPermissionFailsOpen`, not "hasn't finished yet."
private final class OutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: String?
    private var _isDone = false
    func set(_ v: String?) { lock.lock(); _value = v; _isDone = true; lock.unlock() }
    var value: String? { lock.lock(); defer { lock.unlock() }; return _value }
    var isDone: Bool { lock.lock(); defer { lock.unlock() }; return _isDone }
}

private func waitUntil(timeout: TimeInterval = 2,
                       _ condition: @Sendable () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    Issue.record("condition never became true")
}
