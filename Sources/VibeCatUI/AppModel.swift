import Foundation
import Observation
import VibeCatCore
import VibeCatTransport

/// Everything the island is reporting on. Owns the store and the socket.
@MainActor @Observable public final class AppModel {
    /// Finished sessions disappear after this long. Anything still running, or
    /// still waiting on you, stays however old it is.
    public static let idleTTL: TimeInterval = 20 * 60

    public private(set) var store = SessionStore()

    /// Fires after `ingest` or a `prune` that actually changed `store`.
    ///
    /// `AppModel` stays `@Observable` for Plans 4 and 5, where a SwiftUI view
    /// will read it directly — but `NotchController` is a plain AppKit class,
    /// not a view, and a manual bridge onto Observation
    /// (`withObservationTracking`) has a real gap: its `onChange` fires once
    /// per registration, so a mutation landing between a fire and the
    /// re-arm falls through unobserved. That is fixable by patching the
    /// re-arm timing, but an explicit callback removes the race outright —
    /// every mutation notifies, with no one-shot registration to race
    /// against — and it is trivially testable without a window server.
    /// `@ObservationIgnored` because this is wiring, not model state; nothing
    /// should ever depend on a view re-rendering when this closure itself is
    /// reassigned.
    @ObservationIgnored
    public var onChange: (@MainActor () -> Void)?

    private let socketPath: String
    private var server: SocketServer?
    private var pruneTimer: Timer?

    public init(socketPath: String) {
        self.socketPath = socketPath
    }

    public var islandState: IslandState { IslandState(store: store) }
    public var sessionCount: Int { store.sessions.count }

    /// Returns the reply to hand back to the hook. Always nil in Plan 2: the
    /// island cannot answer yet, and nil is what lets the hook fall through to
    /// the CLI's own prompt instead of blocking on us. Plan 4 replaces this.
    @discardableResult
    public func ingest(_ event: VibeEvent, now: Date = Date()) -> Reply? {
        store.apply(event, now: now)
        onChange?()
        return nil
    }

    /// Only notifies when a prune actually removed something. The timer
    /// below fires every 60 seconds regardless of whether anything is stale,
    /// and a no-op tick should not cost a re-render — the island must stay
    /// idle when the machine is idle.
    public func prune(now: Date = Date()) {
        let before = store
        store.prune(idleFor: Self.idleTTL, now: now)
        if store != before {
            onChange?()
        }
    }

    public func start() throws {
        let server = SocketServer(path: socketPath)
        // SocketServer runs the handler on a fresh thread per connection and
        // may run it concurrently with itself, so this must hop rather than
        // assume isolation. Nothing waits on the hop: Plan 2 always replies nil.
        try server.start { [weak self] event in
            Task { @MainActor in self?.ingest(event) }
            return nil
        }
        self.server = server

        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.prune() }
        }
        RunLoop.main.add(t, forMode: .common)
        pruneTimer = t
    }

    public func stop() {
        server?.stop()
        server = nil
        pruneTimer?.invalidate()
        pruneTimer = nil
    }

    /// RunLoop.main holds the prune Timer strongly regardless of what happens
    /// to this object, and the socket server's accept thread otherwise runs
    /// forever too — so without this, a caller that drops an AppModel after
    /// start() without calling stop() first would leak both the timer and the
    /// listening socket for the rest of the process. `isolated deinit` (this
    /// class is @MainActor, and a plain deinit can't call MainActor-isolated
    /// methods) lets teardown happen automatically at deallocation, the same
    /// fix already applied to HoverMonitor for the identical timer-lifecycle
    /// risk.
    isolated deinit {
        stop()
    }
}
