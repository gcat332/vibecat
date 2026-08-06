import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// The hook side of the socket. Deliberately blocking and deliberately
/// infallible: every error path returns nil so the calling CLI carries on.
///
/// The deadline is absolute, not per-syscall. SO_RCVTIMEO alone bounds one
/// read() at a time, which a peer that trickles bytes can exceed without
/// limit — so every loop below also checks the wall clock.
public struct SocketClient: Sendable {
    /// Never zero: timeval{0,0} means "no timeout" to setsockopt, which would
    /// let a wedged app hang the terminal. Never negative: setsockopt rejects
    /// it and the socket silently keeps its default of no timeout.
    /// **Stays at the wire level, deliberately, while the ceiling rose.** `timeval{0,0}`
    /// means *no timeout at all* to `setsockopt` and a negative value is rejected
    /// outright, so both ends of a hung terminal live just below this. The bound a
    /// *person* may choose is a different clamp in a different module —
    /// `UserDefaultsPreferenceStore.clampedHandBack`, in minutes.
    ///
    /// It is also what keeps the suite fast: `PendingQuestionTests` and
    /// `NotchControllerTests` observe a real answer timeout at 0.05s and 0.6s. A floor
    /// of "long enough for a person to read a sentence" would not make those tests
    /// slower, it would make them impossible.
    static let floorDeadline: TimeInterval = 0.02
    /// Never unbounded: Int(deadline) traps on infinity and on overflow, and a
    /// hook that traps is a hook that failed closed.
    ///
    /// `public` (whole-branch review minor, alongside `clamped` above):
    /// `AppModelTests.anAbsurdAnswerDeadlineIsClampedRatherThanTrustedVerbatim`,
    /// in a different module and target, needs this bound to assert against
    /// directly rather than repeating the literal `60` as a second, driftable
    /// copy.
    /// **Raised 60 → 3600 by Plan 9 Task 7, and the ceiling is a wire bound, not a
    /// product one.** Its only job is to reject the absurd: `AppModel.ingest` decodes
    /// `answerDeadline` off a `0600` socket reachable by anything running as this
    /// user, and a value near `Int64.max` nanoseconds saturates `DispatchTime.now()
    /// + …` into `.distantFuture`, parking a thread for the life of the process.
    ///
    /// An hour is now inside the range because the hand-back a person may choose is
    /// expressed in **minutes** (`Preferences.handBackToTerminalAfter`, `0.5…60`) and
    /// the top of that range is 3600 seconds. Against the old ceiling a chosen hour
    /// would silently have become one minute.
    ///
    /// **The floor did not move with it** — see `floorDeadline`.
    public static let ceilingDeadline: TimeInterval = 3600

    /// The one clamp, shared by every place a caller-supplied interval
    /// becomes a deadline: both `init` parameters, `sendExpectingReply`'s
    /// read override, and `setTimeout`'s last-line-of-defence re-clamp. Used
    /// to be the same two-line expression copied at each of those four
    /// sites — one function means one place to get it right, and one place
    /// a test can reach directly instead of only through an observable
    /// property or an end-to-end socket wait.
    ///
    /// `public`, not merely `internal` (whole-branch review minor): `AppModel
    /// .ingest`, in `VibeCatUI`, decodes `VibeEvent.answerDeadline` off the
    /// wire and hands it straight to `PendingQuestion` as a deadline. The
    /// hook always sends its own already-clamped `client.answerDeadline`, but
    /// `ingest` has no way to know who actually wrote the bytes it decoded —
    /// only `HookRunner` is trusted to have clamped upstream, and nothing
    /// enforces that a client speaking the wire protocol directly must have.
    /// Exposing this lets the untrusted value be clamped again on the way in,
    /// rather than duplicating the same two-line expression a second time in
    /// a different module.
    public static func clamped(_ value: TimeInterval) -> TimeInterval {
        Swift.min(ceilingDeadline, Swift.max(floorDeadline, value))
    }

    /// The default bound on a human answer. Hoisted into a named constant
    /// rather than left as a bare `20` in `init` because Task 3 depends on
    /// this exact symbol name existing — not because anything in this file
    /// refers to it by name. `HookRunner` never mentions
    /// `defaultAnswerDeadline`; it reaches the same value through the
    /// instance property `client.answerDeadline`.
    public static let defaultAnswerDeadline: TimeInterval = 20

    public let path: String
    public let deadline: TimeInterval
    /// The bound on a *human* answer, not on delivery. §2.3 fixes delivery at
    /// 300ms and calls fail-open the most important property in the design; a
    /// person cannot answer a permission prompt in 300ms, so taken literally
    /// answering could never work.
    ///
    /// These bound different things. Waiting buys a fire-and-forget event
    /// nothing, so 300ms stands there. A `wantsReply` event is one where the
    /// CLI would *otherwise block on its own prompt indefinitely* — a bounded
    /// wait is not a regression against that, it is a ceiling that did not
    /// previously exist. Clamped by the same floor and ceiling, so a hook
    /// still cannot be made to wait forever.
    public let answerDeadline: TimeInterval

    public init(path: String, deadline: TimeInterval = 0.3,
                answerDeadline: TimeInterval = defaultAnswerDeadline) {
        self.path = path
        self.deadline = Self.clamped(deadline)
        self.answerDeadline = Self.clamped(answerDeadline)
    }

    public func send(_ line: Data) {
        guard let fd = connectSocket(readTimeout: deadline) else { return }
        defer { close(fd) }
        _ = writeAll(fd, line, expiry: Date().addingTimeInterval(deadline))
    }

    public func sendExpectingReply(_ line: Data,
                                   deadline: TimeInterval? = nil) -> Data? {
        // Delivery keeps the short deadline even when the answer gets a long
        // one: a socket that will not accept bytes is dead, and waiting 20s to
        // learn that is 20s of hung terminal for nothing.
        //
        // Clamped via the same `clamped` helper `init` uses — this parameter
        // takes an arbitrary caller-supplied override (Task 3 builds on this
        // type), and setTimeout's own re-clamp only protects the per-syscall
        // SO_RCVTIMEO. It does not protect readExpiry below: an unclamped
        // value there is a wall clock with no upper bound, and a peer that
        // trickles at least one byte before every SO_RCVTIMEO window closes
        // can ride that forever — the unbounded wait §2.3 forbids outright.
        let readTimeout = Self.clamped(deadline ?? self.deadline)
        let writeExpiry = Date().addingTimeInterval(self.deadline)
        let readExpiry = Date().addingTimeInterval(readTimeout)
        // readTimeout, not self.deadline: SO_RCVTIMEO bounds each read()
        // syscall below the wall clock does, so if it stayed pinned to the
        // short delivery deadline, a peer that never sends a byte would have
        // its very first read() time out at 300ms — returning nil well
        // before readExpiry ever got a say, and silently defeating the
        // longer answer deadline for exactly the case that matters most.
        guard let fd = connectSocket(readTimeout: readTimeout) else { return nil }
        defer { close(fd) }
        guard writeAll(fd, line, expiry: writeExpiry) else { return nil }
        return readLine(fd, expiry: readExpiry)
    }

    // MARK: - plumbing

    private func connectSocket(readTimeout: TimeInterval) -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        // A peer that has gone away must not be able to kill us: without this,
        // write() to a closed peer raises SIGPIPE, whose default disposition
        // terminates the process. Per-socket rather than signal(SIGPIPE, SIG_IGN),
        // because the hook runs inside a CLI's process and must not change that
        // process's global signal disposition.
        #if canImport(Darwin)
        var nosigpipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe,
                   socklen_t(MemoryLayout<Int32>.size))
        #else
        // Linux has no SO_NOSIGPIPE; the equivalent is MSG_NOSIGNAL on each
        // send(). Not adopted yet — Linux support is compile-only today.
        #endif
        guard var addr = try? UnixAddress.make(path) else {
            close(fd)
            return nil
        }
        // SO_SNDTIMEO stays on the short delivery deadline regardless of
        // readTimeout — see the comment on writeExpiry above. Only the
        // receive side may be widened for an answer.
        setTimeout(fd, SO_SNDTIMEO, duration: deadline)
        setTimeout(fd, SO_RCVTIMEO, duration: readTimeout)
        let rc = UnixAddress.withSockaddr(&addr) { connect(fd, $0, $1) }
        guard rc == 0 else {
            close(fd)
            return nil
        }
        return fd
    }

    /// Belt to the absolute deadline's braces: keeps a single syscall from
    /// parking forever. `duration` is always already clamped by the time it
    /// reaches here — via `clamped` in `init` or in `sendExpectingReply` —
    /// so this never asks for the "no timeout" timeval and never traps
    /// converting to a timeval's fields. Re-clamped anyway: this is the last
    /// line before setsockopt, where an unclamped zero would silently mean
    /// "no timeout" rather than fail closed. That makes this call
    /// deliberately redundant with every caller's own clamp, not leftover
    /// duplication — do not delete it as a copy of `clamped`.
    private func setTimeout(_ fd: Int32, _ option: Int32, duration: TimeInterval) {
        let whole = Self.clamped(duration)
        let fraction = (whole - floor(whole)) * 1_000_000
        #if canImport(Darwin)
        var tv = timeval(tv_sec: Int(whole), tv_usec: Int32(fraction))
        #else
        // Glibc's tv_usec is __suseconds_t (Int), not Int32.
        var tv = timeval(tv_sec: Int(whole), tv_usec: Int(fraction))
        #endif
        setsockopt(fd, SOL_SOCKET, option, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    private func writeAll(_ fd: Int32, _ data: Data, expiry: Date) -> Bool {
        var sent = 0
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
            guard let base = raw.baseAddress else { return false }
            while sent < data.count {
                if Date() >= expiry { return false }
                let n = write(fd, base.advanced(by: sent), data.count - sent)
                if n > 0 { sent += n; continue }
                // A signal is not a failure; anything else is.
                if n < 0 && errno == EINTR { continue }
                return false
            }
            return true
        }
    }

    /// Reads until the first newline or the deadline. A partial line is
    /// discarded rather than returned: the caller decodes what comes back as
    /// JSON, and half a line is never valid.
    private func readLine(_ fd: Int32, expiry: Date) -> Data? {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 1024)
        while true {
            if Date() >= expiry { return nil }
            let n = read(fd, &chunk, chunk.count)
            if n > 0 {
                buffer.append(contentsOf: chunk[0..<n])
                if let idx = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                    return Data(buffer[buffer.startIndex..<idx])
                }
                continue
            }
            if n < 0 && errno == EINTR { continue }
            return nil
        }
    }
}
