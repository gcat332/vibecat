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

    /// Written decision 3: one alert per quiet period. A session's key lives
    /// here from the tick that finds it stalled until any event lands for
    /// that session again — `applyAndNotify` clears the entry the moment a
    /// session does anything, which is what "re-armed by any event" means.
    /// Plain, unannotated storage: it is private bookkeeping nothing outside
    /// this file ever reads, the same as `server`/`pruneTimer` above.
    private var stalledReported: Set<SessionKey> = []

    /// Fires once per quiet period for a session `StallDetector` finds —
    /// never for `.waiting` (the island is already amber for that) or a
    /// session already reported. Checked against `AlertPolicy.allows(.stalled)`
    /// here, in `prune`, for the same reason `CueSelector` is where `onCue`'s
    /// own policy gating happens: one place decides whether a trigger is
    /// allowed to sound, not each wiring site.
    ///
    /// **What a fired stall does today: nothing consumes this yet.** §14 has
    /// no `Cue` for "stalled" — Plan 6.2's written decision 3 forbids
    /// inventing one — so this deliberately does not call `onCue`. Task 7
    /// builds `Notifier`, and posting a system notification from there is the
    /// intended consumer; wiring that is left to Task 7, not guessed at here.
    /// `@ObservationIgnored` for the reason `onChange`/`onCue`/`onQuestion`
    /// all are: this is wiring, not model state a view should re-render for.
    @ObservationIgnored
    public var onStall: (@MainActor (SessionKey) -> Void)?

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

    /// **The app's own source registry, and the reason Plan 7's mechanism is
    /// connected to anything at all.**
    ///
    /// Before this, `SourceRegistry(adapters:)` appeared exactly once in
    /// `Sources/` — in `VibeCatHook/main.swift`, the *hook* process — so
    /// `SourceAdapter.icon` (Task 1), `GenericAdapter` (Task 2),
    /// `custom-sources.json` (Task 3) and `SessionRow`'s `SourceIcon` call
    /// (Task 5) were a complete mechanism with no path from a real definition to
    /// a real drawn row. `Session.icon` was declared and assigned from nowhere.
    /// That is this project's third "built but never populated" — after
    /// `Session.lastUserMessage` and Plan 6.4's three write-only preferences —
    /// and this property is what closes it.
    ///
    /// **Why here and not on the wire.** An icon field on `VibeEvent` would
    /// also have worked and is the wrong shape: the icon is a display concern,
    /// this is the display side, and a wire change would put a presentation
    /// detail on a socket shared by two executables and every test that speaks
    /// to it. See `Session.icon`'s own doc comment.
    ///
    /// **Why the same factory the hook uses.** `SourceRegistry
    /// .loadingCustomSources(builtIns:from:)` is called by both processes, from
    /// the same `JSONFileCustomSourceStore` default, so an app that draws an
    /// icon for a source and a hook that parses events for it cannot disagree
    /// about which sources exist or which definition won a duplicate id.
    ///
    /// **Read once, in `init`.** A registry is not live: a definition added to
    /// the JSON file mid-session is picked up on the next launch, exactly as
    /// the hook picks it up on its next invocation. Re-reading the file on every
    /// event would put a file read on `SocketServer`'s per-connection thread,
    /// which is the thread §2.3 forbids blocking.
    ///
    /// `nonisolated let` because `applyAndNotify` — which runs on that
    /// connection thread — is what reads it, and `SourceRegistry` is `Sendable`.
    nonisolated private let sources: SourceRegistry

    /// `sources:` defaults to an empty in-memory store, matching
    /// `preferences:`' own precedent: ~30 test call sites predate the parameter
    /// and have no custom sources to declare, and an empty store resolves every
    /// id to the built-in presets alone. As with `preferences:`, that default
    /// is *not* what protects against `main.swift` forgetting to pass the real
    /// one — nothing can, since no test runs that file. What makes the omission
    /// visible is `anIconFromACustomSourceReachesARenderedRow` in
    /// `CustomSourceIconWiringTests`, which drives this initialiser with a real
    /// `CustomSourceStoring` and rasterises the row at the end of it.
    public init(socketPath: String,
                preferences: PreferenceStoring = InMemoryPreferenceStore(),
                sources: CustomSourceStoring = InMemoryCustomSourceStore()) {
        self.socketPath = socketPath
        self.preferences = preferences
        self.sources = SourceRegistry.loadingCustomSources(
            builtIns: [ClaudeCodeAdapter()], from: sources)
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
        // Written decision 3's re-arming: whatever this event does to `store`,
        // the session it names just did *something*, so a quiet period that
        // was building toward a stall (or already reported one) starts over.
        let key = SessionKey(cli: event.cli, session: event.session)

        // §3's icon, resolved once per event on the thread the event arrived on,
        // and handed to the store as a value. A dictionary lookup on a
        // `Sendable` `let` — no I/O, nothing that can block the connection
        // thread §2.3 forbids blocking. See `sources`' own doc comment for why
        // the app holds a registry at all.
        let icon = sources.adapter(for: event.cli)?.icon

        if Thread.isMainThread {
            MainActor.assumeIsolated {
                let before = store          // SessionStore is a value type
                store.apply(event, now: now, icon: icon)
                stalledReported.remove(key)
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
                store.apply(event, now: now, icon: icon)
                stalledReported.remove(key)
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
    ///
    /// Also where `StallDetector` runs, riding this same 60s tick rather than
    /// a second timer — Task 5's own reasoning. This must stay as
    /// conditional as the `onChange` guard above it: `StallDetector.stalled`
    /// already excludes anything in `stalledReported`, so a quiet machine
    /// with nothing newly stalled costs one array scan and calls nothing.
    /// The mutation that matters here is making that call unconditional —
    /// see `StallCostProbe.swift` for the measured cost of doing that.
    public func prune(now: Date = Date()) {
        let before = store
        store.prune(idleFor: Self.idleTTL, now: now)
        if store != before {
            onChange?()
        }

        // Drop keys for sessions this same prune just aged out, so the set
        // doesn't grow for the life of a long-running process. **Unmeasured
        // as a defect and untestable through this class's public surface**:
        // `applyAndNotify`'s own `stalledReported.remove(key)` already clears
        // an entry the moment any event reuses that key, so no assertion
        // reachable from outside this file can tell this line apart from its
        // absence — tried, and removing it left every test in
        // `StallWiringTests.swift` green. Kept anyway for a long-running
        // process's memory, not for correctness a test could pin.
        stalledReported.formIntersection(Set(store.sessions.map(\.id)))

        guard preferences.load().alerts.allows(.stalled) else { return }
        let newlyStalled = StallDetector.stalled(in: store, now: now, alreadyReported: stalledReported)
        guard !newlyStalled.isEmpty else { return }
        stalledReported.formUnion(newlyStalled)
        for key in newlyStalled {
            onStall?(key)
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
