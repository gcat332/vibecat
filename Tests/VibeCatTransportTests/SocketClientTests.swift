import Foundation
import Testing
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
