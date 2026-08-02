import Foundation
import VibeCatCore

/// One question the island is showing and a socket thread is waiting on.
///
/// Not `async`, on purpose. `SocketServer` invokes its handler on a fresh
/// thread per connection and takes a synchronous `Reply?` back, so that thread
/// is exactly the right place to wait: it has nothing else to do, and parking
/// it costs one blocked thread per outstanding question. Bridging to
/// `async`/`await` here would mean the handler returning before the answer
/// existed, which the socket's request/response shape cannot express.
public final class PendingQuestion: @unchecked Sendable {
    public let id: String
    public let event: VibeEvent
    /// When the *hook* gives up. Mirrored here so the island can close a
    /// question that nobody is listening to any more.
    public let expiry: Date

    private let gate = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var reply: Reply?
    private var settled = false

    public init(event: VibeEvent, deadline: TimeInterval, now: Date = Date()) {
        self.id = event.id
        self.event = event
        self.expiry = now.addingTimeInterval(deadline)
    }

    /// Blocks the calling thread until answered or expired. `nil` means fail
    /// open: the hook prints nothing and the CLI falls back to its own prompt.
    public func await() -> Reply? {
        _ = gate.wait(timeout: .now() + max(0, expiry.timeIntervalSinceNow))
        lock.lock()
        defer { lock.unlock() }
        // Settle even on the timeout path, so a late answer cannot be sent
        // down a connection the hook has already abandoned.
        settled = true
        return reply
    }

    /// Returns false if this reply is for another question or the question has
    /// already settled. Both are fail-open: nothing is sent.
    @discardableResult
    public func resolve(_ reply: Reply) -> Bool {
        lock.lock()
        guard reply.id == id, !settled else { lock.unlock(); return false }
        self.reply = reply
        settled = true
        lock.unlock()
        gate.signal()
        return true
    }

    /// Settle with no answer — the person dismissed it, or it aged out of the
    /// UI before the socket thread noticed.
    public func lapse() {
        lock.lock()
        guard !settled else { lock.unlock(); return }
        settled = true
        lock.unlock()
        gate.signal()
    }

    public func hasLapsed(at instant: Date) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return settled || instant >= expiry
    }
}
