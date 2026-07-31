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

private func tempPath(_ n: String) -> String { "/tmp/vibecat-hook-\(n)-\(getpid()).sock" }

private let registry = SourceRegistry(adapters: [ClaudeCodeAdapter()])
private let stopPayload = Data(#"{"hook_event_name":"Stop","session_id":"s1","cwd":"/dev/api"}"#.utf8)
private let permissionPayload = Data("""
  {"hook_event_name":"PreToolUse","session_id":"s1","cwd":"/dev/api",
   "tool_name":"Bash","tool_input":{"command":"rm -rf build/"}}
  """.utf8)

@Test func withNoServerTheHookSaysNothingAndDoesNotHang() {
    let runner = HookRunner(registry: registry,
                            client: SocketClient(path: tempPath("absent"), deadline: 0.1),
                            env: [:])
    let started = Date()
    #expect(runner.run(cli: "claude-code", stdin: permissionPayload) == nil)
    #expect(Date().timeIntervalSince(started) < 1.0)
}

@Test func garbageOnStdinIsIgnored() {
    let runner = HookRunner(registry: registry,
                            client: SocketClient(path: tempPath("absent2"), deadline: 0.1),
                            env: [:])
    #expect(runner.run(cli: "claude-code", stdin: Data("not json".utf8)) == nil)
}

@Test func anUnknownCliIsIgnored() {
    let runner = HookRunner(registry: registry,
                            client: SocketClient(path: tempPath("absent3"), deadline: 0.1),
                            env: [:])
    #expect(runner.run(cli: "nope", stdin: stopPayload) == nil)
}

@Test func anAllowReplyBecomesClaudeCodeDecisionJson() throws {
    let path = tempPath("allow")
    let server = SocketServer(path: path)
    try server.start { event in Reply(id: event.id, choice: "allow") }
    defer { server.stop() }

    let runner = HookRunner(registry: registry,
                            client: SocketClient(path: path, deadline: 1.0),
                            env: [:])
    let out = try #require(runner.run(cli: "claude-code", stdin: permissionPayload))
    let json = try JSONSerialization.jsonObject(with: Data(out.utf8)) as! [String: Any]
    let perm = json["hookSpecificOutput"] as! [String: Any]
    #expect(perm["permissionDecision"] as? String == "allow")
}

@Test func aDenyReplyBecomesADenyDecision() throws {
    let path = tempPath("deny")
    let server = SocketServer(path: path)
    try server.start { event in Reply(id: event.id, choice: "deny") }
    defer { server.stop() }

    let runner = HookRunner(registry: registry,
                            client: SocketClient(path: path, deadline: 1.0),
                            env: [:])
    let out = try #require(runner.run(cli: "claude-code", stdin: permissionPayload))
    #expect(out.contains("\"permissionDecision\":\"deny\""))
}

@Test func anEventThatWantsNoReplyPrintsNothing() throws {
    let path = tempPath("noreply")
    let server = SocketServer(path: path)
    try server.start { _ in nil }
    defer { server.stop() }

    let runner = HookRunner(registry: registry,
                            client: SocketClient(path: path, deadline: 1.0),
                            env: [:])
    #expect(runner.run(cli: "claude-code", stdin: stopPayload) == nil)
}
