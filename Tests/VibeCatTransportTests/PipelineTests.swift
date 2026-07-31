import Foundation
import Testing
import VibeCatCore
@testable import VibeCatHookKit
@testable import VibeCatTransport
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
    #expect(snapshot.sessions.count == 1)
    #expect(snapshot.aggregate == .waiting)
    #expect(snapshot.sessions[0].project == "api")
    #expect(snapshot.sessions[0].activity == "Bash rm -rf build/")
    #expect(snapshot.sessions[0].origin.termSession == "w0t1p0:ABC")
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

// MARK: - helpers

private final class StoreBox: @unchecked Sendable {
    private let lock = NSLock()
    private var store = SessionStore()
    func apply(_ e: VibeEvent, now: Date) { lock.lock(); store.apply(e, now: now); lock.unlock() }
    func snapshot() -> SessionStore { lock.lock(); defer { lock.unlock() }; return store }
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
