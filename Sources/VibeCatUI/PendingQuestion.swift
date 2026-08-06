import Foundation
import VibeCatCore
import VibeCatTransport

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
    /// When the *hook* gives up, or `nil` for `Never`. Mirrored here so the island can
    /// close a question that nobody is listening to any more.
    ///
    /// **`nil` is the absence of an instant, not a very late one** (Plan 9 Task 7).
    /// Spelling `Never` as `Date.distantFuture` would make `expiry.timeIntervalSinceNow`
    /// about 6e10 seconds, and `DispatchTime.now() + 6e10` **saturates** rather than
    /// trapping — so the accidental forever and the deliberate one would be
    /// indistinguishable from here. `waitInstant(until:)` is the one place either is
    /// produced.
    public let expiry: Date?

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

    /// `deadline: nil` is `Never`: the notch holds this question for as long as the hook
    /// lives and the terminal is never prompted. Available, and not the default — see
    /// `Preferences.handBackToTerminalAfter`.
    public init(event: VibeEvent, deadline: TimeInterval?, now: Date = Date()) {
        self.id = event.id
        self.event = event
        self.expiry = deadline.map(now.addingTimeInterval)
    }

    /// The single place a `DispatchTime` is derived from an expiry, and the single place
    /// `.distantFuture` is ever produced.
    ///
    /// **`Never` is spelled out; nothing is allowed to arrive at it by arithmetic.**
    /// `DispatchTime`'s `+` saturates instead of trapping, so an expiry far enough out
    /// silently becomes `.distantFuture` — a thread parked for the life of the process,
    /// which is what §2.3 forbids outright. The `min` against
    /// `SocketClient.ceilingDeadline` is what stops that: a finite expiry, however
    /// absurd, comes back finite. `neverIsSpelledOutRatherThanArrivedAtByArithmetic`
    /// feeds it `Date.distantFuture` and requires a finite answer.
    ///
    /// `internal`, not `private`: that test drives it directly, because the alternative
    /// is observing a saturation by waiting out the life of the process.
    static func waitInstant(until expiry: Date?) -> DispatchTime {
        guard let expiry else { return .distantFuture }
        let remaining = min(max(0, expiry.timeIntervalSinceNow), SocketClient.ceilingDeadline)
        return .now() + remaining
    }

    /// Blocks the calling thread until answered or expired. `nil` means fail
    /// open: the hook prints nothing and the CLI falls back to its own prompt.
    public func await() -> Reply? {
        _ = gate.wait(timeout: Self.waitInstant(until: expiry))
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

    /// **A `Never` question can only lapse by settling**, which is why `expiry == nil`
    /// answers "not yet" rather than "never" here. There is no clock to lapse by, so
    /// `resolve`/`lapse` is the only way out — and `AppModel.prune` reads this, so a
    /// branch that answered `false` unconditionally would hold the question, and the row
    /// it draws, for the life of the app.
    public func hasLapsed(at instant: Date) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if settled { return true }
        guard let expiry else { return false }
        return instant >= expiry
    }
}
