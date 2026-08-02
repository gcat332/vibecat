import Foundation
import Testing
import VibeCatCore
@testable import VibeCatTransport
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

private func tempSocketPath(_ name: String) -> String {
    "/tmp/vibecat-\(name)-\(getpid()).sock"
}

@Test func missingSocketFailsOpenRatherThanThrowing() {
    let client = SocketClient(path: tempSocketPath("absent"), deadline: 0.1)
    #expect(client.sendExpectingReply(Data("{}\n".utf8)) == nil)
}

@Test func sendWithoutAReplyIsSafeWhenNobodyIsListening() {
    let client = SocketClient(path: tempSocketPath("absent2"), deadline: 0.1)
    client.send(Data("{}\n".utf8))   // must not crash or hang
}

@Test func aServerThatNeverAnswersHitsTheDeadline() async throws {
    let path = tempSocketPath("silent")
    let server = try SilentServer(path: path)
    defer { server.stop() }

    let started = Date()
    let client = SocketClient(path: path, deadline: 0.2)
    let reply = client.sendExpectingReply(Data("{}\n".utf8))

    #expect(reply == nil)
    #expect(Date().timeIntervalSince(started) < 1.0)   // gave up promptly
}

@Test func aTricklingPeerCannotOutlastTheDeadline() throws {
    let path = tempSocketPath("trickle")
    let server = TricklingServer(path: path)
    defer { server.stop() }

    let started = Date()
    let client = SocketClient(path: path, deadline: 0.2)
    let reply = client.sendExpectingReply(Data("{}\n".utf8))
    let elapsed = Date().timeIntervalSince(started)

    #expect(reply == nil)          // a partial line is never a valid reply
    #expect(elapsed < 1.0)         // the loop, not just each read(), is bounded
}

@Test func aZeroDeadlineIsClampedRatherThanMeaningNoTimeout() {
    // timeval{0,0} means "block forever" to setsockopt.
    #expect(SocketClient(path: "/tmp/x", deadline: 0).deadline > 0)
    #expect(SocketClient(path: "/tmp/x", deadline: -5).deadline > 0)
}

@Test func aReplyWithoutANewlineIsNotMistakenForSuccess() throws {
    let path = tempSocketPath("nonewline")
    let server = NoNewlineServer(path: path)
    defer { server.stop() }

    let client = SocketClient(path: path, deadline: 0.2)
    #expect(client.sendExpectingReply(Data("{}\n".utf8)) == nil)
}

/// §2.3's 300ms is the right bound for delivery and the wrong one for a human
/// answer. They are separate deadlines because they bound separate things.
@Test func theAnswerDeadlineIsSeparateFromTheDeliveryDeadline() {
    let c = SocketClient(path: "/tmp/x.sock")
    #expect(c.deadline == 0.3)
    #expect(c.answerDeadline == 20)
    #expect(c.answerDeadline > c.deadline)
}

/// Bounded, still. A hook that waits forever is a hook that hangs a terminal,
/// which is the one thing §2.3 forbids outright.
@Test func theAnswerDeadlineIsClampedLikeTheOther() {
    #expect(SocketClient(path: "/tmp/x.sock", answerDeadline: 9999).answerDeadline
            == SocketClient.ceilingDeadline)
    #expect(SocketClient(path: "/tmp/x.sock", answerDeadline: -1).answerDeadline
            == SocketClient.floorDeadline)
}

/// The mechanism, not just the constant: a server that never answers must
/// return nil after roughly the answer deadline, not after the 300ms one.
@Test func waitingForAnAnswerOutlastsTheDeliveryDeadline() throws {
    let path = "/tmp/vibecat-answer-\(UUID().uuidString).sock"
    let server = SocketServer(path: path)
    // Accept, then never reply.
    try server.start { _ in Thread.sleep(forTimeInterval: 1.0); return nil }
    defer { server.stop() }

    let c = SocketClient(path: path, deadline: 0.3, answerDeadline: 0.8)
    let line = try WireCodec.encode(VibeEvent(id: "q", cli: "claude-code",
                                              kind: .permission, session: "s", cwd: "/tmp/proj",
                                              wantsReply: true))
    let start = Date()
    let out = c.sendExpectingReply(line, deadline: c.answerDeadline)
    let elapsed = Date().timeIntervalSince(start)
    #expect(out == nil, "no reply came, so this must fail open")
    #expect(elapsed > 0.5, "gave up after \(elapsed)s — it used the 300ms delivery deadline, not the answer deadline")
    #expect(elapsed < 2.0, "waited \(elapsed)s — the answer deadline is not bounding it")
}

/// Accepts a connection and then says nothing, to exercise the deadline.
private final class SilentServer: @unchecked Sendable {
    private let fd: Int32
    private let path: String
    private var running = true

    init(path: String) throws {
        self.path = path
        unlink(path)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = try UnixAddress.make(path)
        _ = UnixAddress.withSockaddr(&addr) { bind(fd, $0, $1) }
        listen(fd, 4)
        Thread.detachNewThread { [fd] in
            while self.running {
                let c = accept(fd, nil, nil)
                if c >= 0 { Thread.sleep(forTimeInterval: 2); close(c) }
            }
        }
    }

    func stop() {
        running = false
        close(fd)
        unlink(path)
    }
}

/// Accepts a connection and writes one byte every 100ms for about 1.5s,
/// never a newline, to exercise a peer that trickles bytes past what a
/// per-syscall SO_RCVTIMEO alone would bound.
private final class TricklingServer: @unchecked Sendable {
    private let fd: Int32
    private let path: String
    private var running = true

    init(path: String) {
        self.path = path
        unlink(path)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        if var addr = try? UnixAddress.make(path) {
            _ = UnixAddress.withSockaddr(&addr) { bind(fd, $0, $1) }
        }
        listen(fd, 4)
        Thread.detachNewThread { [fd] in
            while self.running {
                let c = accept(fd, nil, nil)
                guard c >= 0 else { continue }
                var byte: UInt8 = UInt8(ascii: ".")
                for _ in 0..<15 {
                    guard self.running else { break }
                    _ = write(c, &byte, 1)
                    Thread.sleep(forTimeInterval: 0.1)
                }
                close(c)
            }
        }
    }

    func stop() {
        running = false
        close(fd)
        unlink(path)
    }
}

/// Accepts a connection, writes a JSON object with no trailing newline, then
/// sleeps for 1s before closing, so a reply that never terminates cannot be
/// mistaken for a complete one.
private final class NoNewlineServer: @unchecked Sendable {
    private let fd: Int32
    private let path: String
    private var running = true

    init(path: String) {
        self.path = path
        unlink(path)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        if var addr = try? UnixAddress.make(path) {
            _ = UnixAddress.withSockaddr(&addr) { bind(fd, $0, $1) }
        }
        listen(fd, 4)
        Thread.detachNewThread { [fd] in
            while self.running {
                let c = accept(fd, nil, nil)
                guard c >= 0 else { continue }
                let bytes = Array("{\"id\":\"x\"}".utf8)
                _ = bytes.withUnsafeBufferPointer { write(c, $0.baseAddress, $0.count) }
                Thread.sleep(forTimeInterval: 1)
                close(c)
            }
        }
    }

    func stop() {
        running = false
        close(fd)
        unlink(path)
    }
}
