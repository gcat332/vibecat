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

/// Task 3's own launch-wiring test. `VibeCatHook/main.swift` builds its
/// registry with exactly one call — `SourceRegistry.loadingCustomSources
/// (builtIns:from:)` — so its own diff for this task is one line, untestable
/// by construction (an `executableTarget` with a `main.swift` cannot be
/// `@testable import`ed). This drives that same call through a real
/// `HookRunner.run`, one hop further than `CustomSourceTests`' own shadowing
/// test goes: not a hand-built `SourceRegistry(adapters:)` with the shadow
/// spliced in by the test, but the actual production factory, fed to the
/// actual production `HookRunner`, exercised the same way
/// `HookRunnerTests` already exercises the built-in preset.
///
/// **Why this test could fail and the `CustomSourceTests` one could not.** A
/// mistake that broke *only* `loadingCustomSources`'s wiring into
/// `HookRunner` — e.g. `main.swift` someday passing `builtIns` and `store` in
/// the wrong order, or a future refactor that made `HookRunner` build its own
/// registry internally and ignore the one it was handed — would leave every
/// `VibeCatCoreTests` assertion green, because none of them ever touch
/// `HookRunner`. This is the seam `LaunchWiringTests`' own doc comment calls
/// "the test that binds": it runs the real construction, not a construction
/// that merely resembles it.
private func tempSocketPath(_ n: String) -> String {
    "/tmp/vibecat-customsource-launchwiring-\(n)-\(getpid()).sock"
}

@Test func aCustomSourceLoadedFromAStoreShadowsClaudeCodeThroughARealHookRunner() throws {
    // Deliberately does not declare "PreToolUse" — the built-in's own
    // wantsReply event, mapped to `.permission`. A **real, listening**
    // server is required to make elapsed time mean anything: against an
    // absent socket, `connectSocket` fails at `connect()` (`ENOENT`)
    // near-instantly regardless of which adapter ran, which is exactly the
    // shape `withNoServerTheHookSaysNothingAndDoesNotHang` in
    // `HookRunnerTests` already relies on — a first version of this test
    // used that shape and stayed green under a mutation that broke the
    // shadow entirely (`builtIns + custom` reversed to `custom + builtIns`),
    // because both branches returned near-instantly for the wrong reason.
    // Caught by this plan's own mutation-verification step, not assumed.
    //
    // So the server here accepts the connection and then simply never
    // replies: if the built-in is still the one `HookRunner` resolves for
    // this id, `run` connects, sends, and blocks in `sendExpectingReply`
    // for the full client deadline waiting on a reply that never comes. If
    // the shadow is the one resolved, the event is simply undeclared and
    // `run` returns before ever touching the socket. Elapsed time is
    // therefore evidence of *which* adapter ran, not just that `run`
    // returned nil either way.
    let shadowConfig = GenericAdapterConfig(
        id: "claude-code", displayName: "Shadowed Claude Code",
        jumpStrategy: .none, reports: [.done],
        eventNameKey: "hook_event_name", sessionKey: "session_id", cwdKey: "cwd",
        events: ["Stop": EventRule(kind: .done)])
    let store = InMemoryCustomSourceStore([CustomSourceDefinition(config: shadowConfig)])

    let registry = SourceRegistry.loadingCustomSources(
        builtIns: [ClaudeCodeAdapter()], from: store)

    let path = tempSocketPath("shadow")
    let server = SocketServer(path: path, readDeadline: 5.0)
    // Never replies within the client's deadline — long enough that the
    // connection is still open (no EOF, no data) when the client's own read
    // times out, so a stall is observed as a stall and not as a closed pipe.
    // `HookRunner.run` waits on `client.answerDeadline` specifically (not
    // `client.deadline`, which only bounds delivery), so that is the one set
    // here, and the server's own sleep only needs to outlast it.
    try server.start { _ in Thread.sleep(forTimeInterval: 1.0); return nil }
    defer { server.stop() }

    let deadline = 0.3
    let runner = HookRunner(registry: registry,
                            client: SocketClient(path: path, deadline: deadline, answerDeadline: deadline),
                            env: [:])

    let permissionPayload = Data("""
      {"hook_event_name":"PreToolUse","session_id":"s1","cwd":"/dev/api",
       "tool_name":"Bash","tool_input":{"command":"ls"}}
      """.utf8)

    let started = Date()
    #expect(runner.run(cli: "claude-code", stdin: permissionPayload) == nil)
    #expect(Date().timeIntervalSince(started) < deadline / 2,
            "returning nil took near the full answer deadline — the built-in ClaudeCodeAdapter's PreToolUse→wantsReply mapping still ran, connected to the real server, and blocked waiting for a reply, so the custom source with the same id did not shadow it through HookRunner")

    // And the shadow really is wired through the same registry for its own
    // declared event — this isn't merely "everything returns nil":
    let stopPayload = Data(#"{"hook_event_name":"Stop","session_id":"s1","cwd":"/dev/api"}"#.utf8)
    #expect(runner.run(cli: "claude-code", stdin: stopPayload) == nil,
            "Stop has no reply to print either way, so this only confirms parsing didn't throw")
    let stopRaw = try #require(try JSONSerialization.jsonObject(with: stopPayload) as? [String: Any])
    #expect(try registry.adapter(for: "claude-code")?.parse(stopRaw, origin: OriginReader.read(env: [:]))?.kind == .done)
}

@Test func loadingCustomSourcesWithNoStoredDefinitionsBehavesExactlyLikeTheBuiltInsAlone() throws {
    // The other side of the same seam: an empty/never-written store must not
    // perturb the built-in preset's own behaviour through a real HookRunner.
    let store = InMemoryCustomSourceStore([])
    let registry = SourceRegistry.loadingCustomSources(builtIns: [ClaudeCodeAdapter()], from: store)

    let path = tempSocketPath("plain")
    let server = SocketServer(path: path)
    try server.start { event in Reply(id: event.id, choice: "allow") }
    defer { server.stop() }

    let runner = HookRunner(registry: registry,
                            client: SocketClient(path: path, deadline: 1.0),
                            env: [:])
    let permissionPayload = Data("""
      {"hook_event_name":"PreToolUse","session_id":"s1","cwd":"/dev/api",
       "tool_name":"Bash","tool_input":{"command":"ls"}}
      """.utf8)
    let out = try #require(runner.run(cli: "claude-code", stdin: permissionPayload))
    #expect(out.contains("\"permissionDecision\":\"allow\""))
}
