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
    private var parked = false

    /// Whether this question has been set aside — drawn under its session's row
    /// in the list rather than owning the drawer.
    ///
    /// **A position, not a state.** The session is still `waiting` and still
    /// `#FFA63C` while this is true, because it *is* still waiting on a person
    /// (§4.2: the session list is a view, not a state). Nothing about the island's
    /// report changes when a question parks.
    public var isParked: Bool {
        lock.lock()
        defer { lock.unlock() }
        return parked
    }

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

    /// Set aside without answering — Escape, or the notch collapsing.
    ///
    /// **The one thing this must not do is signal `gate`.** `lapse()` above is
    /// eleven lines long and signals; this one is the same shape and must not,
    /// because the waiting hook thread has to stay waiting. A `park()` written by
    /// copying `lapse()` releases the agent to carry on while the island goes on
    /// drawing the question — every UI test still passes, and the person then
    /// answers a question nobody is listening to.
    /// `parkingDoesNotReleaseTheWaitingHook` is the assertion, and it works by
    /// bounding the waiter's wall clock from *below*: an unsignalled `await()`
    /// must ride out its whole deadline.
    ///
    /// **Parking does not touch `expiry`.** The hook fixed its own wait against
    /// that instant before anything could park, and knows nothing about parking —
    /// so a parked question that stopped expiring would outlive the thread it
    /// belongs to, and the island would keep offering an answer down a connection
    /// the hook had already abandoned.
    public func park() {
        lock.lock()
        defer { lock.unlock() }
        // A question the hook has already given up on must not come back into the
        // list. Two ways that arrives: dismissed, or timed out while the notch was
        // collapsed.
        guard !settled else { return }
        parked = true
    }

    /// Brought back to the front — tapping the row it is parked under.
    ///
    /// Same `settled` guard as `park()`, for the same reason: this must not be
    /// able to revive a question whose hook has moved on.
    public func unpark() {
        lock.lock()
        defer { lock.unlock() }
        guard !settled else { return }
        parked = false
    }

    public func hasLapsed(at instant: Date) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return settled || instant >= expiry
    }
}
