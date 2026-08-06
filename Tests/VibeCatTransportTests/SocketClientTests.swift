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

/// The clamp arithmetic itself, isolated from any socket, deadline object,
/// or wait — pure and deterministic, so this runs in sub-millisecond time
/// instead of needing an end-to-end run past the ceiling to observe the
/// unbounded-wait failure mode the clamp exists to prevent.
@Test func theClampPassesInRangeValuesThroughAndBoundsTheRest() {
    #expect(SocketClient.clamped(9999) == SocketClient.ceilingDeadline)
    #expect(SocketClient.clamped(-1) == SocketClient.floorDeadline)
    #expect(SocketClient.clamped(5) == 5)
}

/// **The bound itself, not just that there is one (Plan 9, Task 7).** Every
/// assertion above compares against `ceilingDeadline` by name, so all of them
/// would keep passing against a ceiling of any size — including one raised to
/// `.infinity`, which is the change that reintroduces the unbounded wait §2.3
/// forbids. This pins the number, and pins *why* it is that number: the hand-back
/// is a value a person sets in **minutes** (`Preferences
/// .handBackToTerminalAfter`, `0.5…60`), and the top of that range is 3600
/// seconds. Against the old ceiling of 60 a chosen hour would have silently
/// become one minute.
@Test func theCeilingLeavesAnHourLongHandBackReachable() {
    #expect(SocketClient.ceilingDeadline == 3600)
    #expect(SocketClient.clamped(3600) == 3600, "an hour is inside the range, not on the wrong side of it")
    #expect(SocketClient.clamped(3601) == 3600)
    #expect(SocketClient.clamped(86_400) == 3600, "a day-long hold was honoured verbatim")
}

/// The floor did **not** move with the ceiling, and this is the assertion that
/// catches someone raising it to "long enough for a person to read a sentence".
/// It is a wire-level bound, not a product one: `timeval{0,0}` means *no timeout*
/// to `setsockopt` and a negative value is rejected outright, so both ends of a
/// hung terminal live just below 0.02. The product bound is a different clamp in a
/// different module (`UserDefaultsPreferenceStore.clampedHandBack`, in minutes).
///
/// It is also what keeps this suite fast: `PendingQuestionTests` and
/// `NotchControllerTests` observe a real answer timeout at 0.05s and 0.6s. A floor
/// of 30 seconds would not make those tests slower, it would make them impossible.
@Test func theFloorStaysAtTheWireLevelSoAShortDeadlineIsStillObservable() {
    #expect(SocketClient.floorDeadline == 0.02)
    #expect(SocketClient.clamped(0.05) == 0.05)
    #expect(SocketClient.clamped(0.6) == 0.6)
    #expect(SocketClient.clamped(0.001) == 0.02, "a value below the floor must still be a real timeout")
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

/// `aTricklingPeerCannotOutlastTheDeadline` above never overrides `deadline:`,
/// so `readTimeout == self.deadline` there and it cannot tell a correctly
/// threaded wall clock apart from one pinned to the short delivery deadline —
/// a peer that trickles one byte every 100ms keeps every individual read()
/// well inside either value. This test sets `answerDeadline` strictly longer
/// than `deadline`, so the two genuinely differ: the trickle must be allowed
/// to run past the short delivery deadline, and must still be cut off at
/// roughly the (longer) answer deadline, not left to hang on the server's
/// eventual close five bytes later.
@Test func aTricklingPeerOutlastsDeliveryButIsStillBoundedByTheAnswerDeadline() throws {
    let path = tempSocketPath("trickle-answer")
    let server = TricklingServer(path: path)
    defer { server.stop() }

    let c = SocketClient(path: path, deadline: 0.2, answerDeadline: 0.6)
    let start = Date()
    let reply = c.sendExpectingReply(Data("{}\n".utf8), deadline: c.answerDeadline)
    let elapsed = Date().timeIntervalSince(start)

    #expect(reply == nil, "no newline ever arrives, so this must fail open")
    #expect(elapsed > 0.4, "gave up after \(elapsed)s — bounded by the short delivery deadline, not the answer deadline")
    #expect(elapsed < 1.0, "waited \(elapsed)s — the answer deadline is not bounding it")
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
