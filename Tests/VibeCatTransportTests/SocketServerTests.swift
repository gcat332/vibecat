import Foundation
import Testing
import VibeCatCore
@testable import VibeCatTransport
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

private func tempPath(_ name: String) -> String {
    "/tmp/vibecat-srv-\(name)-\(getpid()).sock"
}

private func sampleEvent(wantsReply: Bool) -> VibeEvent {
    VibeEvent(id: "e1", cli: "claude-code", kind: .permission,
              session: "s1", cwd: "/dev/api", wantsReply: wantsReply)
}

@Test func serverDeliversAnEventToTheHandler() async throws {
    let path = tempPath("deliver")
    let server = SocketServer(path: path)
    let box = Box<VibeEvent?>(nil)
    try server.start { event in box.set(event); return nil }
    defer { server.stop() }

    let client = SocketClient(path: path, deadline: 1.0)
    client.send(try WireCodec.encode(sampleEvent(wantsReply: false)))

    try await waitUntil { box.get() != nil }
    #expect(box.get()?.session == "s1")
}

@Test func serverWritesTheHandlersReplyBack() async throws {
    let path = tempPath("reply")
    let server = SocketServer(path: path)
    try server.start { event in Reply(id: event.id, choice: "allow") }
    defer { server.stop() }

    let client = SocketClient(path: path, deadline: 1.0)
    let raw = try #require(client.sendExpectingReply(try WireCodec.encode(sampleEvent(wantsReply: true))))
    let reply = try WireCodec.decode(Reply.self, from: raw)

    #expect(reply.id == "e1")
    #expect(reply.choice == "allow")
}

@Test func theSocketFileIsOwnerOnly() throws {
    let path = tempPath("perms")
    let server = SocketServer(path: path)
    try server.start { _ in nil }
    defer { server.stop() }

    let mode = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as! NSNumber
    #expect(mode.int16Value == 0o600)
}

@Test func startingOverAStaleSocketFileSucceeds() throws {
    let path = tempPath("stale")
    FileManager.default.createFile(atPath: path, contents: Data())
    let server = SocketServer(path: path)
    try server.start { _ in nil }
    server.stop()
}

@Test func aSilentPeerDoesNotParkAServerThreadForever() async throws {
    let path = tempPath("silent-peer")
    let server = SocketServer(path: path, readDeadline: 0.2)
    try server.start { _ in nil }
    defer { server.stop() }

    // Connect and say nothing, holding the connection open.
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    var addr = try UnixAddress.make(path)
    #expect(UnixAddress.withSockaddr(&addr) { connect(fd, $0, $1) } == 0)
    defer { close(fd) }

    // The server must give up on its own rather than waiting for us.
    try await Task.sleep(nanoseconds: 600_000_000)
    // Still healthy: a well-behaved client is served normally afterwards.
    let box = Box<VibeEvent?>(nil)
    server.stop()
    let live = SocketServer(path: path, readDeadline: 0.2)
    try live.start { e in box.set(e); return nil }
    defer { live.stop() }
    SocketClient(path: path, deadline: 1.0).send(try WireCodec.encode(sampleEvent(wantsReply: false)))
    try await waitUntil { box.get() != nil }
    #expect(box.get()?.session == "s1")
}

@Test func theHandlerRunsEvenWhenTheReplyIsNotWanted() async throws {
    let path = tempPath("nogate")
    let server = SocketServer(path: path)
    let box = Box<VibeEvent?>(nil)
    // Handler returns a reply, but the event does not want one.
    try server.start { e in box.set(e); return Reply(id: e.id, choice: "allow") }
    defer { server.stop() }

    let client = SocketClient(path: path, deadline: 0.5)
    let raw = client.sendExpectingReply(try WireCodec.encode(sampleEvent(wantsReply: false)))
    #expect(raw == nil)                      // reply suppressed
    try await waitUntil { box.get() != nil } // handler still ran
}

// MARK: - helpers

private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func get() -> T { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ new: T) { lock.lock(); value = new; lock.unlock() }
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
