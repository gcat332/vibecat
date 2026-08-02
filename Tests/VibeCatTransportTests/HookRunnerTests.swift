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
    let json = try #require(try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])
    let perm = try #require(json["hookSpecificOutput"] as? [String: Any])
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

@Test func aReplyForADifferentEventIsNotHonoured() throws {
    let path = tempPath("crossed")
    let server = SocketServer(path: path)
    try server.start { _ in Reply(id: "a-completely-different-event", choice: "allow") }
    defer { server.stop() }

    let runner = HookRunner(registry: registry,
                            client: SocketClient(path: path, deadline: 1.0),
                            env: [:])
    #expect(runner.run(cli: "claude-code", stdin: permissionPayload) == nil)
}

/// HookRunner's one call to `sendExpectingReply` must forward
/// `client.answerDeadline`, not let the read fall back to `client.deadline`.
/// Every other test in this file uses a server that replies almost
/// instantly, so a reply slower than delivery but still inside the answer
/// deadline is the only thing that would notice HookRunner failing to pass
/// it through — without this, that one-line regression is invisible to the
/// whole suite.
@Test func aReplySlowerThanDeliveryButWithinTheAnswerDeadlineIsStillHonoured() throws {
    let path = tempPath("slowreply")
    let server = SocketServer(path: path)
    try server.start { event in
        Thread.sleep(forTimeInterval: 0.4)   // slower than the delivery deadline below
        return Reply(id: event.id, choice: "allow")
    }
    defer { server.stop() }

    let runner = HookRunner(registry: registry,
                            client: SocketClient(path: path, deadline: 0.2, answerDeadline: 0.6),
                            env: [:])
    let out = try #require(runner.run(cli: "claude-code", stdin: permissionPayload))
    #expect(out.contains("\"permissionDecision\":\"allow\""))
}

/// Exercises the real binary, not HookRunner — main.swift's argument
/// handling, stdin read and exit code are otherwise untested.
private func runHookBinary(arguments: [String],
                           stdin: String,
                           env: [String: String] = [:]) throws -> (out: String, code: Int32) {
    let binary = URL(fileURLWithPath: #filePath)          // …/Tests/VibeCatTransportTests/…
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent(".build/debug/vibecat-hook")

    let process = Process()
    process.executableURL = binary
    process.arguments = arguments
    var environment = ProcessInfo.processInfo.environment
    for (k, v) in env { environment[k] = v }
    process.environment = environment

    let inPipe = Pipe(), outPipe = Pipe()
    process.standardInput = inPipe
    process.standardOutput = outPipe
    process.standardError = Pipe()

    try process.run()
    inPipe.fileHandleForWriting.write(Data(stdin.utf8))
    inPipe.fileHandleForWriting.closeFile()
    let out = outPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (String(decoding: out, as: UTF8.self), process.terminationStatus)
}

@Test func theBinaryAlwaysExitsZeroAndSaysNothingWhenItCannotReport() throws {
    // Every one of these must leave the calling CLI's turn untouched.
    let cases: [(String, [String], String)] = [
        ("no server",      ["claude-code"], #"{"hook_event_name":"Stop","session_id":"s1","cwd":"/tmp"}"#),
        ("malformed json", ["claude-code"], "not json at all"),
        ("unknown cli",    ["nope"],        #"{"hook_event_name":"Stop","session_id":"s1","cwd":"/tmp"}"#),
        ("no argument",    [],              #"{"hook_event_name":"Stop","session_id":"s1","cwd":"/tmp"}"#),
        ("empty stdin",    ["claude-code"], ""),
    ]
    for (label, args, input) in cases {
        let r = try runHookBinary(arguments: args, stdin: input,
                                  env: ["VIBECAT_SOCKET": "/tmp/vibecat-absent-\(getpid()).sock"])
        #expect(r.code == 0, "\(label): exit code")
        #expect(r.out.isEmpty, "\(label): stdout")
    }
}
