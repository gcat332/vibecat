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

    /// Fires when an ingested event changes what the island has to announce.
    /// Never fires with "nothing" — a cue that means "ignore me" would make
    /// every consumer branch on it. Prunes never cue: a session ageing out is
    /// not an event.
    ///
    /// `@ObservationIgnored` for the same reason `onChange` is: this is wiring,
    /// and nothing should re-render because the closure was reassigned.
    ///
    /// The player that answers this lives in the app's own wiring, not here —
    /// `AppModel` stays free of `AVFoundation` so it remains testable without an
    /// audio device.
    @ObservationIgnored
    public var onCue: (@MainActor (Cue) -> Void)?

    private let socketPath: String
    private var server: SocketServer?
    private var pruneTimer: Timer?

    /// The single source of truth for `Preferences.alerts` — Plan 6.5 Task 4's
    /// own seam. Read fresh in `applyAndNotify` rather than snapshotted once
    /// here, so a switch flipped on the Notifications page (a plain
    /// load-mutate-save through this same store, elsewhere) takes effect on
    /// the very next event with nothing else to wire — no callback to remember
    /// to add later, the way `NotchController.onSoundEnabledChanged` had to be
    /// for `soundEnabled`. Defaulted to `InMemoryPreferenceStore()` — matching
    /// `NotchController`'s own precedent for this exact protocol — so every
    /// existing call site that predates this parameter keeps compiling against
    /// an isolated, throwaway store rather than a shared one.
    ///
    /// That default is *not* what stands between this and Plan 6.4's
    /// three-times-repeated "persisted but never read" defect — a default
    /// parameter cannot protect against `main.swift` itself forgetting to
    /// thread its real, shared `UserDefaultsPreferenceStore` through here, and
    /// no test runs `main.swift` to catch that (§2.3's own precedent: Plan 6.2
    /// shipped an `abort()` on launch invisible to 509 green tests for the same
    /// reason). What actually closes the loop is `CueSelector.cue`'s `policy:`
    /// having no default of its own, so the two call sites below in
    /// `applyAndNotify` cannot compile without naming a real value, and
    /// `AppModelCueTests`'s "the important mutation" section exercises this
    /// store end to end rather than only proving `CueSelector` honours
    /// whatever `AlertPolicy` it is handed.
    private let preferences: PreferenceStoring

    public init(socketPath: String, preferences: PreferenceStoring = InMemoryPreferenceStore()) {
        self.socketPath = socketPath
        self.preferences = preferences
    }

    public var islandState: IslandState { IslandState(store: store) }
    public var sessionCount: Int { store.sessions.count }

    /// The question the island is showing, if any. Main actor: the UI reads it
    /// every render.
    public private(set) var pending: PendingQuestion?
    public var onQuestion: (@MainActor (PendingQuestion?) -> Void)?

    /// Returns the reply to hand back to the hook.
    ///
    /// Called on `SocketServer`'s per-connection thread. For a `wantsReply`
    /// event this blocks *that thread* until the person answers or the
    /// question expires — which is the point, and why the question is
    /// published to the main actor without waiting for it. Hopping
    /// synchronously here would deadlock the moment the main actor tried to
    /// read anything this thread holds.
    @discardableResult
    nonisolated public func ingest(_ event: VibeEvent, now: Date = Date()) -> Reply? {
        applyAndNotify(event, now: now)
        guard event.wantsReply, event.choices?.isEmpty == false else { return nil }

        let question = PendingQuestion(
            event: event,
            // The hook's own deadline, carried on the event. A second constant
            // here would drift from it, and the island would keep showing a
            // question the hook had already abandoned.
            //
            // Clamped (whole-branch review minor): `event.answerDeadline` is
            // decoded off the wire and trusted here unclamped otherwise. The
            // real hook always sends an already-clamped value, but `ingest`
            // has no way to tell a hook-originated event apart from one a
            // non-hook client wrote directly to the socket — and this socket
            // is 0600, reachable by anything running as the same user. An
            // absurd value (say, ~1e12 seconds) would make `DispatchTime.now()
            // + …` inside `PendingQuestion.await()` saturate to
            // `.distantFuture`, parking that thread permanently rather than
            // for any bounded time — exactly what §2.3's fail-open guarantee
            // forbids. `SocketClient.clamped` is the same clamp `HookRunner`'s
            // own value already went through once; this is hardening, not a
            // reachable production path today.
            deadline: SocketClient.clamped(event.answerDeadline ?? SocketClient.defaultAnswerDeadline),
            now: now)
        Task { @MainActor [weak self] in self?.present(question) }
        return question.await()
    }

    /// `store` and `onChange` are main-actor state, but `ingest` itself is
    /// not — it has to be callable directly on `SocketServer`'s
    /// per-connection thread. Two cases, handled differently:
    ///
    /// Already on the main actor's own thread: every synchronous test in this
    /// file calls `ingest` this way and checks `store`/`onChange`'s effects
    /// with no intervening `await`, so this path must apply them inline,
    /// before returning — `MainActor.assumeIsolated` is exactly "run this
    /// now, we already hold the actor," which is true here by construction.
    ///
    /// Not on the main thread (the real `SocketServer` case, and every
    /// `Task.detached`-simulated one in tests): fire-and-forget, same as
    /// `present` below. Nothing observes `store`/`onChange` synchronously
    /// from *this* calling thread's own timeline — the reply `ingest`
    /// eventually returns never depends on this having run first — so there
    /// is nothing to block this thread on. This is not just the cheaper
    /// choice: an earlier version bridged this branch through
    /// `DispatchQueue.main.sync`, which — confirmed by deliberately
    /// replacing its body with a no-op `DispatchQueue.main.sync {}` and
    /// re-running the full suite — reproduced the exact same slow,
    /// full-suite-only flake this comment is warning about, even with
    /// nothing inside it. `Task.detached` draws from Swift's small, shared
    /// cooperative thread pool (unlike `SocketServer`'s real, uncounted
    /// `Thread`s), and blocking enough of those pool threads on
    /// `DispatchQueue.main.sync` at once — which the full suite's parallel
    /// tests do, this file's answering tests alone do not — can leave none
    /// free to run the very `Task { @MainActor … }` hops that would unblock
    /// them, so the only thing that eventually resolves the pile-up is each
    /// `PendingQuestion`'s own multi-second timeout, not the 50ms the tests
    /// actually wait.
    ///
    /// The three lines are duplicated across both branches deliberately. The
    /// obvious de-duplication — routing the main-thread branch through
    /// `Task { @MainActor }` too — is exactly the change the paragraph above
    /// records as having reproduced a full-suite-only flake. `onCue` fires
    /// *after* `onChange`, so a listener that redraws and a listener that plays
    /// a sound both see the same store; and the cue is computed against the
    /// store as it was **before** the apply, because `CueSelector`'s whole rule
    /// is a before/after comparison and a `before` read afterwards would make
    /// every pair identical.
    nonisolated private func applyAndNotify(_ event: VibeEvent, now: Date) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                let before = store          // SessionStore is a value type
                store.apply(event, now: now)
                onChange?()
                if let cue = CueSelector.cue(for: event, before: before, after: store,
                                             policy: preferences.load().alerts) {
                    onCue?(cue)
                }
            }
        } else {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let before = store
                store.apply(event, now: now)
                onChange?()
                if let cue = CueSelector.cue(for: event, before: before, after: store,
                                             policy: preferences.load().alerts) {
                    onCue?(cue)
                }
            }
        }
    }

    @MainActor private func present(_ question: PendingQuestion) {
        // One question at a time. The displaced one fails open rather than
        // leaving a socket thread parked with nothing that can ever wake it.
        pending?.lapse()
        pending = question
        onQuestion?(question)
    }

    @MainActor public func answer(_ reply: Reply) {
        guard let pending, pending.id == reply.id else { return }
        pending.resolve(reply)
        clearQuestion()
    }

    @MainActor public func dismissQuestion() {
        pending?.lapse()
        clearQuestion()
    }

    @MainActor private func clearQuestion() {
        pending = nil
        onQuestion?(nil)
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
        // SocketServer runs the handler on a fresh thread per connection, and
        // that thread is exactly what a wantsReply question needs to park —
        // see ingest's own doc comment. So, unlike Plan 2, this calls straight
        // through rather than hopping first: hopping here would mean the
        // *socket* thread returns immediately and some other thread would need
        // to block waiting for an answer, which is not how SocketServer's
        // request/response handoff works.
        try server.start { [weak self] event in
            self?.ingest(event)
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
