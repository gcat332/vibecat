import AppKit
import SwiftUI
import VibeCatCore

/// Owns the panel, the geometry and the hover monitor, and keeps the
/// `IslandModel` in step with the app model and with the display.
@MainActor public final class NotchController {
    public private(set) var geometry: IslandGeometry?

    /// The one object the view reads. Built here, handed to SwiftUI once in
    /// `present()`, and mutated thereafter — never rebuilt into a fresh view
    /// tree, because a fresh `IslandModel` would break the observation
    /// SwiftUI already established with the old one.
    ///
    /// `let`, not `private(set) var`: it is assigned only in `init`, and the
    /// once-only hosting guard in `present()` keys on the hosted *type*
    /// (`NSHostingView<IslandView>`), not the hosted *model* — so a future
    /// reassignment here would silently keep stale hosting bound to the old
    /// object, with `panel.contentView is NSHostingView<IslandView>` still
    /// true and nothing failing. `let` makes that reassignment impossible
    /// rather than merely untested.
    public let model: IslandModel

    /// The app-level model — named `appModel` rather than `model` (the
    /// external label on both initialisers below stays `model:` for call-site
    /// compatibility, but the *stored* property cannot share that name)
    /// specifically so nothing in this file can silently read the wrong
    /// `model` after the `IslandModel` above was introduced: the two are
    /// different types with overlapping vocabulary (`state`, `sessionCount`),
    /// so a stray unqualified `model` would still compile against either one.
    private let appModel: AppModel
    private let metrics: @MainActor () -> ScreenMetrics?
    /// Plan 6.4 Task 4's own addition: the single source of truth for
    /// `Preferences.soundEnabled`, which `model.muted` is the negation of.
    /// Defaulted to a fresh `InMemoryPreferenceStore()` at every call site
    /// that doesn't pass one (every existing test), so nothing outside
    /// main.swift ever touches the user's real `UserDefaults` just by
    /// constructing a controller.
    private let preferences: PreferenceStoring
    private var panel: NotchPanel?
    private var hover: HoverMonitor?
    private var bloomEnd: Task<Void, Never>?
    private var observer: NSObjectProtocol?
    /// The live Reduce Motion observer. Installed by `present()`, removed by
    /// `dismiss()` (and so by `deinit`), for the reason spelled out on
    /// `observer` above: a block-based observer outlives the object it captures
    /// unless something removes it, and this one is registered on
    /// `NSWorkspace`'s own centre rather than the default one.
    private var motionObserver: NSObjectProtocol?
    /// Task 9's own hardware question (can a `.nonactivatingPanel` become key
    /// without stealing focus?) is still open — see `KeyDownProbe` — so this
    /// is the only keyboard wiring this round. A *local* monitor, never
    /// `NSEvent.addGlobalMonitorForEvents`: a global monitor needs
    /// Accessibility, which this app does not otherwise require, and trading
    /// a whole-input-stream grant for one keystroke is a bad deal the plan
    /// already rejected. This never calls `makeKey`/activates anything
    /// itself, so it changes nothing about the unmeasured question either
    /// way — it only reacts to a `keyDown` AppKit was already going to hand
    /// this app. See `dismissOnEscape`'s own doc comment for why Escape,
    /// specifically, is safe to wire before that question is answered, when
    /// number keys are not.
    private var escapeMonitor: Any?
    private let sampler = BackdropSampler()
    private var backdropSample: Task<Void, Never>?
    /// Cancel-and-reschedule, the same shape as `bloomEnd` and for the same
    /// reason: a question's expiry mirrors the hook's own deadline (see
    /// `PendingQuestion.expiry`), and once it passes with nobody answering,
    /// the drawer has to close itself rather than keep showing a question
    /// the hook has already abandoned — see `setQuestion`.
    private var lapseCheck: Task<Void, Never>?
    /// Whichever `PendingQuestion` the most recent `setQuestion(_:)` call was
    /// actually told about — `lapseCheck`'s own closure compares against
    /// this, not `appModel.pending`, so the guard is self-contained to what
    /// `setQuestion` itself just did rather than depending on `AppModel`
    /// being wired up at all. That distinction matters here specifically:
    /// this file's own tests drive the state machine through `setQuestion(_:)`
    /// directly, deliberately bypassing `AppModel` (see `aQuestion`'s own
    /// comment in NotchControllerTests.swift), so `appModel.pending` would
    /// stay `nil` throughout every one of them regardless of what
    /// `setQuestion` was actually told — reading it here would make the
    /// guard permanently false under test, not merely under a real socket.
    /// `weak`: this file does not need to keep a `PendingQuestion` alive any
    /// longer than whoever actually owns it (`AppModel.pending`, in
    /// production) already does.
    private weak var currentPending: PendingQuestion?

    /// Fires with the freshly-persisted `Preferences.soundEnabled` value
    /// right after a mute toggle is saved — main.swift wires this to
    /// `SoundPlayer.settings.enabled`, so the engine's own render gate
    /// (`CueRenderer.render`'s `guard settings.enabled`) and what
    /// `Preferences` says on disk never disagree. `SoundPlayer` itself is
    /// deliberately not known to this file — it is owned by main.swift for
    /// the reason given right next to where it's constructed there (keeps
    /// `AppModel`/`NotchController` free of `AVFoundation`) — so this is the
    /// seam that lets a UI-level tap reach it without this file importing
    /// sound at all.
    public var onSoundEnabledChanged: (@MainActor (Bool) -> Void)?

    /// The surface the aura has to be seen against: the menu bar strip the
    /// island sits in, as wide as the panel so it covers where the glow
    /// spreads sideways.
    ///
    /// The panel's own height is deliberately *not* used. It runs
    /// `auraMargin` past the bottom of the island, into whatever window
    /// happens to be below the menu bar — measured here, a bright one at 236
    /// against a menu bar at 27. That is 41% of the panel's height, and it
    /// pulled the mean over the threshold: the first version of this sampled
    /// the full panel and confidently reported `.light` while the bar behind
    /// the island was black.
    ///
    /// The glow does spill below the bar, so this is a choice rather than a
    /// correction — a mixed backdrop has no single right answer, and the bar
    /// is the surface §9.2 is written about and the one the island lives on.
    ///
    /// Our own window is excluded from the capture by `BackdropSampler`, so
    /// what comes back is what is behind the island rather than the island.
    /// Internal rather than private so `theBackdropRegionStopsAtTheMenuBar`
    /// can pin the height mistake this comment describes.
    ///
    /// Deliberately recomputed at a fixed `.rest` tier rather than read off
    /// `model.frames`, which now grows downward while the drawer is open (see
    /// `IslandModel.tier`). The aura only ever traces `IslandBody`'s own
    /// silhouette — `DrawerView` has no shadow of its own — so letting this
    /// region grow with the drawer would resurrect the exact bug the rest of
    /// this comment describes, just triggered by a question instead of by
    /// the panel's aura margin.
    func backdropRegion() -> CGRect {
        let frames = model.geometry.frames(rightFlank: model.layout.rightFlankWidth, tier: .rest)
        guard let screen = metrics()?.frame else { return frames.body }
        // ScreenCaptureKit's sourceRect has a top-left origin; AppKit's is
        // bottom-left.
        return CGRect(x: frames.panel.minX, y: screen.maxY - frames.body.maxY,
                      width: frames.panel.width, height: frames.body.height)
    }

    public init(model appModel: AppModel, metrics: @escaping @MainActor () -> ScreenMetrics?,
                preferences: PreferenceStoring = InMemoryPreferenceStore()) {
        self.appModel = appModel
        self.metrics = metrics
        self.preferences = preferences
        let geometry = IslandGeometry(screen: metrics() ?? .zeroFallback)
        self.model = IslandModel(geometry: geometry, motion: MotionPreference.current())
        // Read once, here, rather than left at IslandModel's own `false`
        // default — a relaunch with sound already muted must show muted
        // immediately, not flip visibly once something else happens to
        // touch `model.muted` first.
        self.model.muted = !preferences.load().soundEnabled
    }

    public convenience init(model: AppModel, preferences: PreferenceStoring = InMemoryPreferenceStore()) {
        self.init(model: model, metrics: { ScreenMetrics.current() }, preferences: preferences)
    }

    /// The live panel, for `NotchControllerTests` only — deliberately not
    /// `public`, so a normal `import VibeCatUI` never sees it and only
    /// `@testable import` does. `present()` already constructs a real
    /// `NSPanel` in the test process; this is what lets a test observe both
    /// that it stays fixed at its maximum collapsed size (Task 9) and that
    /// `appModel.onChange` really reaches `model` rather than merely being
    /// non-nil.
    var panelForTesting: NotchPanel? { panel }

    /// The live hover monitor, for `NotchControllerTests` only — same
    /// visibility reasoning as `panelForTesting`. Final whole-branch review,
    /// finding 3: `reflow()`'s `hover?.frame = model.frames.body` is the one
    /// line that makes the drawer clickable at all — pinning that rect to a
    /// `.rest`-tiered frame instead left every test green, because nothing
    /// before this read the hover monitor's own frame once a drawer was
    /// open. Without this accessor there is no way for a test to see that
    /// rect at all.
    var hoverForTesting: HoverMonitor? { hover }

    /// The live local Escape monitor, for `NotchControllerTests` only — same
    /// visibility reasoning as `panelForTesting`. Final whole-branch review,
    /// finding 4: Escape is the only user-initiated dismiss this app has, and
    /// nothing before this test read `escapeMonitor` at all — deleting the
    /// whole installation block in `present()` failed no test, because every
    /// behavioural Escape test in this file drives `dismissOnEscape(_:)`
    /// directly rather than through a real, delivered `NSEvent` (there is no
    /// window server in `swift test` to deliver one). This closes the gap one
    /// level down from that: not "does Escape dismiss," which those tests
    /// already cover, but "is the monitor that would ever receive a real
    /// Escape actually installed at all."
    var escapeMonitorForTesting: Any? { escapeMonitor }

    /// The live Reduce Motion observer, for `MotionBypassTests` only — the same
    /// visibility reasoning as `escapeMonitorForTesting`, and installed for
    /// exactly the reason that accessor records. Every behavioural test of this
    /// drives `refreshMotion()`/`apply(motion:)` directly, because a test process
    /// cannot toggle a system accessibility switch — so without this, deleting
    /// the whole installation block in `present()` would fail no test at all,
    /// which is the defect Plan 6.4's review found here once already.
    var motionObserverForTesting: NSObjectProtocol? { motionObserver }

    public func refreshGeometry() {
        geometry = metrics().map(IslandGeometry.init(screen:))
        guard let geometry else { return }
        // Updates the existing model's geometry in place rather than
        // replacing the object — a fresh IslandModel would break the
        // observation SwiftUI already established with this one.
        model.geometry = geometry
        // model.tier, not a bare .rest: a display change while a drawer
        // happens to be open must not silently shrink the panel back to its
        // collapsed size.
        panel?.apply(geometry.maxCollapsedFrames(tier: model.tier))
        hover?.frame = model.frames.body
    }

    public func present() {
        guard let geometry else { return }
        // The panel is sized once, at the widest the collapsed island can
        // ever be, and never resized again while collapsed — measured,
        // animating the silhouette inside a fixed window beats animating the
        // window itself (p95 10.34ms vs 15.16ms). Growth from here on is the
        // body's job, inside IslandBody, for width, and — since the drawer —
        // reflow()'s own panel resize, for height.
        let frames = geometry.maxCollapsedFrames(tier: model.tier)
        let panel = self.panel ?? NotchPanel(frames: frames)
        self.panel = panel
        panel.apply(frames)
        // Assigned once. present() may run again without an intervening
        // dismiss() (see the observer note below), so this only builds the
        // hosting view the first time a given panel exists — every
        // subsequent state change mutates `model` instead, which is the
        // entire point of Task 9's restructure.
        //
        // Deliberately a type check, not `panel.contentView == nil`: a
        // freshly constructed NSPanel already has a non-nil `contentView` —
        // AppKit assigns a default NSView of its own during
        // `init(contentRect:styleMask:backing:defer:)`, confirmed directly
        // against `NotchPanel`, so `== nil` is never true and the assignment
        // below would never run at all. The pre-Task-9 code never hit this,
        // because its own guard already asked the right question — `panel
        // .contentView as? NSHostingView<IslandView>` — which is what this
        // restores, just without the `else` branch that used to mutate
        // `.rootView` on every render.
        //
        // IslandHostingView, not a bare NSHostingView: `is NSHostingView
        // <IslandView>` still recognises it (a subclass instance satisfies an
        // `is` check for its superclass), so the guard and
        // `theHostingRootIsAssignedOnceAndSurvivesStateChanges`'s own check
        // are both unaffected — the only difference is `acceptsFirstMouse`,
        // see that type's own doc comment.
        if !(panel.contentView is NSHostingView<IslandView>) {
            panel.contentView = IslandHostingView(rootView: IslandView(model: model))
        }

        let hover = self.hover ?? HoverMonitor()
        hover.frame = model.frames.body
        hover.onChange = { [weak self] hovering in self?.setHovering(hovering) }
        hover.start()
        self.hover = hover

        // Deterministic and race-free, unlike the withObservationTracking
        // bridge this replaced: every ingest or store-changing prune notifies
        // directly, with no one-shot registration to fall through between a
        // fire and a re-arm. See AppModel.onChange.
        appModel.onChange = { [weak self] in self?.reflow() }
        // A question arriving or clearing is not the same event as a session
        // changing state — AppModel fires each independently (see
        // AppModel.present/clearQuestion) — so it gets its own callback
        // rather than being folded into onChange above.
        appModel.onQuestion = { [weak self] pending in self?.setQuestion(pending) }
        // The click that opens the drawer, and the answer that closes it —
        // see IslandModel.onIslandClick/.onAnswer's own doc comments. Both
        // set unconditionally on every present(), the same as onChange/
        // onQuestion above, so a second present() without an intervening
        // dismiss() re-wires them rather than leaving stale closures.
        model.onIslandClick = { [weak self] in self?.click() }
        model.onAnswer = { [weak self] reply in self?.appModel.answer(reply) }
        // The footer's mute button — see `toggleMute()` and
        // `onSoundEnabledChanged`'s own doc comments.
        model.onToggleMute = { [weak self] in self?.toggleMute() }

        // Escape while the drawer is open dismisses without answering — see
        // dismissOnEscape's own doc comment. Torn down and rebuilt the same
        // way the screen-parameters observer below is, so a second present()
        // without an intervening dismiss() re-installs rather than leaking a
        // second monitor.
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.dismissOnEscape(charactersIgnoringModifiers: event.charactersIgnoringModifiers)
                ? nil : event
        }

        render()
        // Never makeKeyAndOrderFront — the app must not steal focus.
        panel.orderFrontRegardless()

        // present() may run again without an intervening dismiss() (there is
        // no current caller that does, but nothing prevents it either), so
        // the old observer is torn down first rather than merely overwritten
        // — otherwise it would keep firing forever with no reference left to
        // remove it by.
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshGeometry() }
            }

        // §9.3's Reduce Motion is a live system switch, and it was read exactly
        // once — in `init` below — so toggling it did nothing whatsoever until
        // the app was relaunched. Torn down and re-installed on every
        // `present()` for the same reason the observer above is.
        //
        // `NSWorkspace.shared.notificationCenter`, not `NotificationCenter
        // .default`: this notification is posted only on the workspace's own
        // centre, and an observer on the default centre installs happily and
        // then never fires. `queue: .main` because a workspace notification is
        // not guaranteed to be posted on the main thread, and everything the
        // handler touches is `@MainActor`.
        if let motionObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(motionObserver)
        }
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: MotionPreference.systemMotionSettingDidChange,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshMotion() }
            }
    }

    /// Re-resolves §9.3 against the system's current Reduce Motion setting,
    /// keeping whatever level the user themselves chose — see
    /// `MotionPreference.refreshed()` for why that is not `current()`.
    ///
    /// The handler `present()` installs, and callable directly, which is how
    /// this is tested: a test process cannot toggle a system accessibility
    /// switch, so the seam has to be here rather than in the notification.
    func refreshMotion() {
        apply(motion: model.motion.refreshed())
    }

    /// The write itself, split out so a test can drive a change in both
    /// directions that it cannot make the system perform.
    ///
    /// **Guarded.** `accessibilityDisplayOptionsDidChangeNotification` fires for
    /// *every* accessibility display option — increased contrast, reduced
    /// transparency, differentiate-without-colour — so the overwhelmingly common
    /// case in this handler is a value identical to the one already there, which
    /// is exactly the shape that cost Plan 4 a live 8fps timeline and 3.3% of a
    /// core permanently. `@Observable`'s generated setter already skips
    /// notifying on an equal write to an `Equatable` property on this toolchain
    /// (`anEqualWriteToAnObservablePropertyDoesNotNotify`), and
    /// `MotionPreference` is `Equatable` — so this guard is belt over braces
    /// rather than the only thing standing between the app and that bug, and a
    /// test of the guard *alone* would be vacuous for that reason. What it buys
    /// is that the no-op is local and legible, and that it survives
    /// `MotionPreference` ever losing that conformance.
    ///
    /// No `render()`/`reflow()` afterwards, deliberately: motion changes nothing
    /// about state, geometry or tier. `IslandView` reads `model.motion` through
    /// `needsTimeline`, `activeProfile` and the two phases, so the observation
    /// this write triggers is the entire mechanism by which a timeline starts or
    /// stops.
    func apply(motion fresh: MotionPreference) {
        guard fresh != model.motion else { return }
        model.motion = fresh
    }

    public func dismiss() {
        appModel.onChange = nil
        appModel.onQuestion = nil
        model.onIslandClick = nil
        model.onAnswer = nil
        model.onToggleMute = nil
        bloomEnd?.cancel()
        bloomEnd = nil
        lapseCheck?.cancel()
        lapseCheck = nil
        hover?.stop()
        hover = nil
        panel?.orderOut(nil)
        panel = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        if let motionObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(motionObserver)
        }
        motionObserver = nil
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
    }

    /// `NotificationCenter` holds the `didChangeScreenParametersNotification`
    /// registration for as long as it is not explicitly removed, regardless
    /// of what happens to this instance — so without this, a controller
    /// dropped after `present()` with no intervening `dismiss()` would leak
    /// that observer, plus the panel and the hover monitor's timer, for the
    /// rest of the process. Same defect class already hardened on
    /// `HoverMonitor` and `AppModel` via `isolated deinit`; this is the third
    /// of the three owners. `dismiss()` already does exactly the cleanup
    /// needed here, `bloomEnd` and `lapseCheck` included, so deinit just
    /// calls it.
    isolated deinit {
        dismiss()
    }

    /// Syncs the hover monitor's own hit-test frame, re-renders, then keeps the
    /// panel in step with the model's tier.
    ///
    /// It used to also set `model.hovering` from a second `tier` property on this
    /// class — but that property only ever held `.hover` or `.rest`, never
    /// `.drawer`, so it was a `Bool` wearing an `IslandTier`: `setHovering(_:)`
    /// took a `Bool`, stored it as a tier, and this line converted it straight
    /// back. `IslandModel.tier` is the real one, and it is computed rather than
    /// stored, so there is nothing here to keep in step with it. `setHovering`
    /// now writes `model.hovering` directly.
    ///
    /// The handler for the hover monitor's edge (a tier change),
    /// `appModel.onChange` (a session-count or state change), and — via
    /// `setHovering`/`setQuestion`/`click` below — every way the drawer's own
    /// tier can change, all funnel through here rather than each repeating
    /// this same synchronisation.
    private func reflow() {
        hover?.frame = model.frames.body
        render()

        // Clicks are taken only where a click would do something. Everywhere
        // else the menu bar underneath stays clickable — which is what makes
        // Plan 3's oversized fixed panel safe (see maxCollapsedFrames).
        //
        // Plan 5: widened from `model.question != nil` alone. §6.1's own
        // table says a click opens "question, or session list" — gating
        // solely on a question left a click undeliverable whenever sessions
        // were pending with no question at all, which made this plan's own
        // routing dead code: `model.face`/`.tier` would correctly compute
        // `.sessionList`/`.drawer`, but the panel stayed click-through and
        // nothing could ever set `drawerOpen` to reveal it. With sessions
        // present a click *would* do something (open the list), so this
        // follows the comment above rather than bending it.
        //
        // model.question, not appModel.pending: the two always agree in
        // production (present() sets pending immediately before the
        // onQuestion callback that reaches model.question here), but only
        // the model is reachable from a direct setQuestion(_:) call — which
        // is exactly how this file's own tests drive the state machine,
        // deliberately bypassing AppModel entirely (see makeController()).
        // Reading appModel.pending here would make those tests unsatisfiable
        // regardless of anything else NotchController did.
        //
        // `|| model.drawerOpen` (final whole-branch review, F3): "is there
        // something to open" and "is there something open" are different
        // questions, and only the first was being asked. `setQuestion` resets
        // `drawerOpen` when a *question* disappears; nothing resets it when the
        // last *session* does. So the list could be opened with one idle session
        // in it and then have that session pruned out from under it by
        // `AppModel.prune`'s 20-minute TTL — probe-verified: `sessions.count ==
        // 0`, `drawerOpen == true`, `tier == .drawer(height: 420)`, panel 476pt
        // tall, `acceptsClicks == false`. A permanent empty 420pt black box
        // under the notch that could not be clicked away, with Escape the only
        // exit and Escape's own delivery still Task 9's unmeasured hardware
        // question. A drawer that is open can always be clicked shut.
        //
        // The `model.hovering` conjunct still governs all three terms, and that
        // is deliberate rather than incidental: this gate exists so the menu bar
        // underneath stays clickable, and hoisting `drawerOpen` out of it would
        // have the island swallowing clicks from anywhere on the screen for as
        // long as a drawer was up. Clicks are still refused when there is
        // genuinely nothing to open *and* nothing open —
        // `thePanelTakesClicksOnlyWhenHoveredWithAQuestionWaiting` pins that
        // half, and it passes unchanged either side of this term.
        panel?.acceptsClicks = model.hovering
            && (model.question != nil || !model.sessions.isEmpty || model.drawerOpen)

        // The panel is otherwise fixed at its widest collapsed size (Plan 3);
        // this is the one thing that grows it, and only when the tier it
        // needs to cover actually changed — compared against the panel's own
        // live frame rather than a cached "last tier", so this can't drift
        // out of step with what the panel is actually showing. See
        // IslandGeometry.maxCollapsedFrames's own comment on why the width
        // ceiling stays fixed regardless.
        if let geometry, let panel {
            let needed = geometry.maxCollapsedFrames(tier: model.tier)
            if panel.frame != needed.panel {
                panel.apply(needed)
            }
        }
    }

    /// The hover monitor's own edge callback routes here, and so does every
    /// test in `NotchControllerTests` that drives hover without a real
    /// cursor — one path, not two copies of the same two lines.
    func setHovering(_ hovering: Bool) {
        model.hovering = hovering
        reflow()
    }

    /// `appModel.onQuestion`'s handler — wired in `present()` — and also
    /// callable directly, which is how this file's own tests exercise it
    /// without a real socket thread behind it. Keeps `model.question` in
    /// step with whatever `AppModel` is actually parked on, and arms a lapse
    /// check at the question's own expiry (mirroring the hook's deadline —
    /// see `PendingQuestion.expiry`) so a question nobody answers closes the
    /// drawer instead of going on showing something the hook has already
    /// given up on. Cancel-and-reschedule, the same `Task` + `cancel()` shape
    /// `bloomEnd` uses and for the same reason: a displaced or cleared
    /// question must not leave a stale timer standing that could later fire
    /// against a different one.
    func setQuestion(_ pending: PendingQuestion?) {
        lapseCheck?.cancel()
        lapseCheck = nil
        currentPending = pending
        model.question = pending.map { QuestionModel(event: $0.event) }
        // A newly-arrived question must not inherit an older one's "clicked
        // open" (see IslandModel.drawerOpen's own doc comment), and a
        // cleared question must not leave a stale open drawer standing for
        // whatever arrives next — only ever reset here, never set true:
        // opening is exclusively click()'s job.
        if pending == nil {
            model.drawerOpen = false
        }
        if let pending {
            lapseCheck = Task { [weak self] in
                let remaining = max(0, pending.expiry.timeIntervalSinceNow)
                try? await Task.sleep(for: .seconds(remaining))
                guard !Task.isCancelled, let self else { return }
                // Whole-branch review minor: `self.currentPending === pending`,
                // not an unconditional dismiss. `lapseCheck?.cancel()` above
                // already retires this exact Task the instant a displacing
                // question arrives, so in the ordinary flow this guard should
                // never actually change anything — but without it, nothing
                // stops a Task that ever outlived its own cancellation (or a
                // future edit that drops the `cancel()` above) from calling
                // `dismissQuestion()` against whatever question happens to be
                // current by the time its sleep finishes, which after a
                // displacement is a completely different one — lapsing
                // question B roughly this Task's own `remaining` early.
                // `===`, not `==`: `PendingQuestion` has no `Equatable`
                // conformance, and this needs identity, not value equality,
                // regardless. `currentPending`, not `appModel.pending` — see
                // that property's own doc comment for why: this file's tests
                // drive `setQuestion(_:)` directly, bypassing `AppModel`
                // entirely, and `currentPending` is kept in step by
                // `setQuestion` itself regardless of whether `AppModel` is
                // involved at all, while `appModel.pending` would simply
                // never match under that same testing convention.
                guard self.currentPending === pending else { return }
                // Lapses the PendingQuestion — waking a socket thread still
                // parked on it, or a no-op if it already timed out on its
                // own — and clears appModel.pending, which reaches back here
                // via onQuestion(nil) above.
                self.appModel.dismissQuestion()
            }
        }
        reflow()
    }

    /// The island was clicked while it could take clicks (see
    /// `NotchPanel.acceptsClicks`) — opens the drawer on whichever question is
    /// currently showing, **or on §11's session list when there is no question**,
    /// or closes it again on the next click.
    ///
    /// It used to say "a no-op either way if there is no question:
    /// `model.tier`'s own guard also requires one, so toggling this with nothing
    /// pending leaves the tier at `.rest`/`.hover` regardless." That was true
    /// until Task 7 restructured `IslandModel.tier`, and false since: the guard
    /// now admits a question *or* a non-empty `sessions`, which is the whole
    /// point of this plan. A reader taking the old wording at face value would
    /// wrongly conclude the sessions-only-open path is unreachable — the same
    /// path `thePanelTakesClicksWithSessionsPendingEvenWithoutAQuestion` and
    /// `anOpenDrawerStaysClickableAfterItsLastSessionIsPruned` both drive. It is
    /// still a no-op when there is neither, and `acceptsClicks` will not deliver
    /// the click in that case anyway.
    ///
    /// `.toggle()`, not an unconditional `= true` (final whole-branch
    /// review, finding 4): Escape is otherwise the only way to back out of
    /// an opened drawer, and Escape's own delivery depends on the panel
    /// becoming key — Task 9's still-open hardware question. Without a
    /// second click closing it, a person who opens the drawer and changes
    /// their mind has no way to collapse it if that delivery never happens,
    /// short of answering or waiting out the lapse. This only flips the
    /// *drawer's* own visibility, deliberately — it does not touch
    /// `appModel`'s pending question at all, unlike `dismissOnEscape`'s
    /// deliberate, fail-open dismiss below: a second click closing the
    /// drawer must not silently abandon a question the hook is still
    /// waiting on. The question stays parked, still running its own
    /// deadline, and a third click reopens the same one.
    func click() {
        model.drawerOpen.toggle()
        reflow()
    }

    /// `model.onToggleMute`'s handler, wired in `present()`. Flips the one
    /// setting `island-motion.html:1060` names as shared between the panel's
    /// mute button and the app's own sound toggle, persists it through
    /// whichever `PreferenceStoring` this controller was built with, updates
    /// `model.muted` so the footer redraws, and reports the fresh value
    /// outward through `onSoundEnabledChanged` so main.swift can keep the
    /// running `SoundPlayer` in step.
    ///
    /// `internal`, not `private`: mirrors `click()`/`setHovering(_:)` above —
    /// this file's own tests drive wiring entry points directly rather than
    /// only through a simulated tap. Calling this directly proves the store
    /// is written and `model.muted`/`onSoundEnabledChanged` follow; it
    /// cannot prove that `PanelBar`'s real `Button(action:)` is the thing
    /// that reaches `model.onToggleMute` in the first place — that half is
    /// the same permanent gap `PanelBarTests
    /// .tappingEachButtonCallsItsOwnClosureAndNotTheOther` already records,
    /// for the same reason: no ViewInspector-style dependency, and this
    /// project takes none.
    func toggleMute() {
        var prefs = preferences.load()
        prefs.soundEnabled.toggle()
        preferences.save(prefs)
        model.muted = !prefs.soundEnabled
        onSoundEnabledChanged?(prefs.soundEnabled)
    }

    /// The escape monitor's own decision, factored out so a test can drive it
    /// directly with a plain character string rather than a real `NSEvent`
    /// delivered through the window server — the same "testable without a
    /// window" split `KeyRouting.pick`'s own doc comment gives for the same
    /// reason. Returns whether the keystroke was consumed, mirroring the
    /// monitor's own `NSEvent?` return (`nil` swallows it, the event itself
    /// lets it fall through) — see `present()`'s own installation of it.
    ///
    /// Dismissing calls `appModel.dismissQuestion()` rather than touching
    /// `model` directly: that is the exact fail-open path a lapsed question
    /// already takes (see `setQuestion`'s own `lapseCheck`), already covered
    /// by Task 1/3's fail-open guarantees, and it reaches back into `model`
    /// through the same `onQuestion` wiring `setQuestion(_:)` already is —
    /// one path, not a second copy of "close the drawer" logic.
    ///
    /// Escape only, deliberately — not number keys. Both would need the same
    /// delivery (a `keyDown` this app actually receives), which is Task 9's
    /// own still-unmeasured hardware question — but the two have opposite
    /// risk if that measurement ever turns out to allow delivery at all:
    /// dismissing is always safe (worst case, a drawer closes a beat early,
    /// recoverable with one more click), while answering — even a
    /// non-destructive one — is not something this file does from a
    /// keystroke yet, and a destructive one is exactly what §10.3's second
    /// ask exists to gate. So this never calls `QuestionModel.pick`/`reply()`
    /// at all, regardless of what the keystroke was, unless it is Escape.
    @discardableResult
    func dismissOnEscape(charactersIgnoringModifiers: String?) -> Bool {
        // Pattern match, not `== .drawer`: `IslandTier.drawer(height:)` carries
        // an associated value, the same reason `IslandView`'s own drawer gate
        // uses `if case .drawer = model.tier` rather than `==`.
        guard case .drawer = model.tier, KeyRouting.isEscape(charactersIgnoringModifiers) else { return false }
        appModel.dismissQuestion()
        return true
    }

    /// `internal`, not `private`: `anIdenticalEventDoesNotRewriteTheModel` drives
    /// this directly, the same way this file's tests already drive `click()` and
    /// `setHovering(_:)` — there is no window server in `swift test`, so a render
    /// triggered any other way cannot be observed.
    func render() {
        let now = Date()
        model.state = appModel.islandState
        model.sessionCount = appModel.sessionCount
        // The reveal names the same session the island's own state summary is
        // about (§4.2) — see `SessionStore.mostUrgentSession`'s own doc
        // comment for why this isn't just `aggregate` plus a lookup.
        model.revealed = appModel.store.mostUrgentSession
        // §11's list, in the same "most urgent" ordering as `revealed` above
        // — one comparator, not two that could disagree about which session
        // matters. Plain and unguarded, the same as `state`/`sessionCount`/
        // `revealed`: `@Observable`'s generated setter already skips
        // notifying on an equal write to an `Equatable` property (`[Session]`
        // is), which is exactly what an earlier round of this task added an
        // explicit guard to duplicate — see
        // `anEqualWriteToAnObservablePropertyDoesNotNotify` in
        // NotchControllerTests.swift for the measurement that guard's
        // premise rested on, and which is why it was reverted rather than
        // extended here.
        model.sessions = appModel.store.mostUrgentFirst

        // AuraTrigger does its own change detection, so this is called
        // unconditionally and only reports true on an actual change.
        if model.aura.observe(model.state, now: now) {
            // Only the aura reads the backdrop, so only a bloom pays for
            // measuring it — ~35ms, which is nothing a few times a minute and
            // ruinous per frame. Detached rather than awaited: the bloom
            // starts now and peaks at 450ms, so a sample landing at 35ms is
            // in place well before the moment it matters, and a slow or
            // refused capture just leaves the previous answer standing.
            backdropSample?.cancel()
            backdropSample = Task { [weak self] in
                guard let self else { return }
                await sampler.refresh(region: backdropRegion())
                model.backdrop = sampler.current
            }
            // needsTimeline reads the aura, so the view is nudged once more
            // when the bloom ends, forcing IslandView.body to re-evaluate
            // and pick a `.never` schedule instead of the live one.
            // `endBloom()`, never `model.aura = model.aura` — see that
            // method's own comment. The distinction is a mutating call versus
            // an assignment, not whether the resulting value differs: an
            // assignment routes through the generated `set`, gated by
            // `shouldNotifyObservers` and confirmed to notify nothing on an
            // equal write on this toolchain
            // (`anEqualWriteToAnObservablePropertyDoesNotNotify`), while a
            // mutating call routes through `_modify`, which notifies
            // unconditionally regardless of whether anything changed
            // (`aMutatingCallThroughAnObservablePropertyNotifiesUnconditionally`).
            // Rewriting this line back into an assignment would silently
            // reintroduce the bug even if it still cleared `firedAt`.
            bloomEnd?.cancel()
            bloomEnd = Task { [weak self] in
                try? await Task.sleep(for: .seconds(AuraTrigger.duration))
                guard !Task.isCancelled else { return }
                self?.model.aura.endBloom()
            }
        }
    }
}
