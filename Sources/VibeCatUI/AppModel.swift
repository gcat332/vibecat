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
    ///
    /// **`nil` while every outstanding question is parked**, which is how the
    /// drawer gets sent to the session list: `NotchController.setQuestion(nil)`
    /// clears `model.question`, and `IslandModel.face` then resolves to
    /// `.sessionList`. So parking needs no separate signal to the view layer.
    public private(set) var pending: PendingQuestion?

    /// Every question the model is holding — one per session, in arrival order.
    ///
    /// **An array, not a `[SessionKey: PendingQuestion]`, and the reason is
    /// order.** The session list is ordered and which question the drawer shows
    /// has to be stable, or the face flickers between two of them on unrelated
    /// redraws. A dictionary plus a parallel `[SessionKey]` for order is the
    /// classic way to have two things that can disagree; there are never more
    /// than a handful of outstanding questions, so a linear scan to find one by
    /// id is cheaper than that risk.
    ///
    /// **The invariant:** every element is either `=== pending` or `isParked`.
    /// A third state — held, shown nowhere, not parked — is a question nobody
    /// can answer, and `everyHeldQuestionIsEitherTheFrontmostOrParked` is the
    /// assertion.
    ///
    /// One per *session*, not one per question: a session can only be blocked on
    /// one tool call at a time, so a second question from the same session means
    /// the first is already gone and gets lapsed rather than parked. See
    /// `present(_:)`.
    public private(set) var questions: [PendingQuestion] = []

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
        let key = SessionKey(cli: question.event.cli, session: question.event.session)

        // **A second question from the same session lapses the first; one from a
        // different session parks it.** The distinction is the whole of Plan 9
        // Task 2. A session can only be blocked on one tool call at a time, so a
        // repeat from the same session means the first call is already gone —
        // parking it would leave a row offering an answer to a call that no
        // longer exists. Two *different* agents asking at once is the case the
        // old unconditional `pending?.lapse()` got wrong: it fail-opened the
        // first without anyone ever seeing it.
        if let i = questions.firstIndex(where: { keyOf($0) == key }) {
            questions[i].lapse()
            questions.remove(at: i)
        }
        // The displaced question, if it belongs to another session, keeps its
        // hook waiting and moves into the list.
        pending?.park()

        questions.append(question)
        pending = question
        onQuestion?(question)
    }

    /// **Answers any question the model is holding, parked or frontmost**, looked
    /// up by the reply's own id.
    ///
    /// It used to require `pending?.id == reply.id`, which was right when there
    /// was one slot and is wrong now: a parked question is answered *in place*,
    /// from the block drawn under its session's row, with no gesture that brings
    /// it back to the drawer first. Keeping the old guard made every parked
    /// question unanswerable, and the way that surfaced is worth recording —
    /// `aPruneThatDropsNoQuestionDoesNotNotify` took **60 seconds**, because its
    /// `answer` call silently did nothing and the waiter rode out its full
    /// deadline. A test that was merely slow, not red.
    ///
    /// A reply whose id matches nothing is still refused, which is what
    /// `aMismatchedReplyIsIgnored` pins.
    @MainActor public func answer(_ reply: Reply) {
        guard let question = questions.first(where: { $0.id == reply.id }) else { return }
        question.resolve(reply)
        forget(question)
        // Only the drawer's own question empties the drawer. Answering a parked
        // one leaves whatever is frontmost exactly where it was.
        if pending === question { clearQuestion() }
    }

    @MainActor public func dismissQuestion() {
        if let pending {
            pending.lapse()
            forget(pending)
        }
        clearQuestion()
    }

    /// Set the frontmost question aside — Escape, or the notch collapsing. It
    /// keeps its place in `questions` and its hook keeps waiting; only the drawer
    /// lets go of it.
    ///
    /// **No auto-promotion of the next parked question**, here or in `answer`. A
    /// drawer that swapped a different question in under the cursor invites
    /// answering the wrong one by reflex, and choosing among several is what the
    /// session list is for.
    @MainActor public func parkQuestion() {
        guard let pending else { return }
        pending.park()
        clearQuestion()
    }

    // **There is deliberately no `resumeQuestion`.** An earlier draft had one, to
    // bring a parked question back to the drawer's richer `.question` face — and
    // nothing ever called it. The owner's design answers a parked question in
    // place, from the block under its row, and jumping is the only thing the row
    // header does. An unused public entry point that looks like part of the flow
    // is worse than its absence, so `PendingQuestion.unpark()` stays (Task 1's
    // contract, and the symmetry that makes `park` readable) with no caller in
    // this class. If a later task needs one it arrives with its caller.

    @MainActor private func clearQuestion() {
        pending = nil
        onQuestion?(nil)
    }

    /// Drops a question the model is done with. Not folded into `clearQuestion`:
    /// `answer` and `dismissQuestion` are done with theirs, `parkQuestion` is
    /// emphatically not, and all three call `clearQuestion`. One shared removal
    /// there would delete parked questions — the exact bug this plan exists to
    /// prevent.
    @MainActor private func forget(_ question: PendingQuestion) {
        questions.removeAll { $0 === question }
    }

    @MainActor private func keyOf(_ question: PendingQuestion) -> SessionKey {
        SessionKey(cli: question.event.cli, session: question.event.session)
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

        // **A parked question has nothing else watching its expiry.**
        // `NotchController.setQuestion(nil)` cancels `lapseCheck`, and parking
        // reaches exactly that path, so the per-question timer is gone the moment
        // a question moves into the list. The hook still times out on its own —
        // no agent is left hanging — but the *list* would keep offering an answer
        // to a call nobody is listening to. This is where that gets cleared, at
        // the 60s tick's granularity, which is fine for cleanup and costs nothing
        // on an idle machine.
        //
        // Guarded, like `store != before` above and for the same reason:
        // `@Observable` notifies on the write, not on the change, so an
        // unconditional notify here is a re-render every minute forever.
        let live = questions.filter { !$0.hasLapsed(at: now) }
        if live.count != questions.count {
            questions = live
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
