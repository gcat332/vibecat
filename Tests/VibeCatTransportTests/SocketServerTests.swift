import Foundation
import Testing
import VibeCatCore
@testable import VibeCatTransport

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
