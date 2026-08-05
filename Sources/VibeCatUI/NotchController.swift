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
    ///
    /// Since Plan 6.1 Task 6 it is also the source of the two preferences §9.3
    /// and §6.2 describe — `motion` and `rightFlank` — read in `init` below.
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
    /// The one local `keyDown` monitor: Escape (`dismissOnEscape`) and §10.1's
    /// number keys (`answerOnNumberKey`), dispatched by `handleKeyDown`.
    ///
    /// A *local* monitor, never `NSEvent.addGlobalMonitorForEvents`: a global
    /// monitor needs Accessibility, which this app does not otherwise require,
    /// and trading a whole-input-stream grant for a handful of keystrokes is a
    /// bad deal the plan already rejected. A local monitor only ever sees a
    /// `keyDown` AppKit was already going to hand this app — which, for a
    /// `.nonactivatingPanel`, means only while the panel holds key status; see
    /// `takeKeyStatusIfADrawerIsOpen()` for the one window in which it does.
    ///
    /// **Named `escapeMonitor` until Plan 6.1 Task 4**, when the key-input spike
    /// (`docs/superpowers/spikes/2026-08-03-notch-panel-key-input.md`) settled
    /// the hardware question the old name's own comment was waiting on — Path A,
    /// key without focus — and the number keys were wired through this same
    /// monitor. The rename is not cosmetic: a reader who trusted the old name
    /// would conclude a digit cannot reach this app at all.
    private var keyMonitor: Any?
    /// Whether the panel is currently holding key status, tracked here rather
    /// than read back off `panel.isKeyWindow` — there is no window server in
    /// `swift test`, so `isKeyWindow` is permanently `false` under test and an
    /// assertion on it could not tell a working implementation from one that
    /// never called `makeKeyAndOrderFront` at all. This is the state the tests
    /// assert on; the AppKit calls it guards are what step 5's hardware check
    /// exists to confirm.
    ///
    /// The spike's own hazard is why this exists at all: delivery to a key
    /// `.nonactivatingPanel` is **exclusive** and `frontmostApplication` does
    /// not change, so a panel left key at rest silently swallows everything the
    /// person types into a terminal that still shows every sign of having
    /// focus. Key status is therefore held only while a drawer is actually on
    /// screen — see `takeKeyStatusIfADrawerIsOpen()`, and Plan 6.1 Task 6's own
    /// decision block there for why that is wider than Task 4 left it — and
    /// given back at each of the three ways a question ends, plus each of the
    /// two ways a drawer closes without one.
    private(set) var holdsKeyStatus = false
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
        // One `load()`, not three. `Preferences` is a value read whole (see
        // `UserDefaultsPreferenceStore.load()`), so three reads could in
        // principle straddle a concurrent `save(_:)` and start the island from
        // two different plists.
        let prefs = preferences.load()
        // **`chosen: prefs.motion`, not the parameter's `.full` default.** This
        // is the launch seam for §9.3, and it is the whole reason `chosen`
        // exists: `MotionPreference.current()` reads the *system's* Reduce
        // Motion switch, and the user's own level is the other half of §9.3's
        // rule ("the system asking for less beats a user asking for more; it
        // never drags a user who chose `off` back into motion"). Dropped, the
        // preference would be persisted by `save(_:)`, read by `load()`, and
        // then thrown away here — which is Plan 6.4's "persisted but never
        // read" defect (three fields, six task reviews) and Plan 6.5's fourth
        // instance of it, in the one place no test can watch, because
        // `main.swift` cannot be `@testable import`ed. The mapping therefore
        // lives *here* rather than in `main.swift`, exactly as
        // `SoundSettings(_:)` does for the sound half, so that
        // `LaunchWiringTests` can drive it with an `InMemoryPreferenceStore`.
        self.model = IslandModel(geometry: geometry,
                                 motion: MotionPreference.current(
                                     chosen: prefs.motion,
                                     followsSystem: prefs.followsSystemReduceMotion))
        // §6.2's flank, same seam and same reasoning. Assigned after `init`
        // rather than passed in: `IslandModel.rightFlank` has a default that
        // ~40 test call sites depend on, and adding a parameter here would not
        // make this line any more likely to be written.
        self.model.rightFlank = prefs.rightFlank
        // §7.3's coat, same seam again: `IslandModel.coat` has carried a
        // constructor parameter since Plan 3, but nothing before Plan 6.6's
        // Task 1 read `Preferences.coat` into it — the field did not exist.
        // Assigned post-init for the same reason `rightFlank` is: existing
        // call sites depend on the constructor's `.tabby` default.
        self.model.coat = prefs.coat
        // §11's nine session-card switches, same seam and same reasoning again.
        // `SessionRow.Options(_:)` is the conversion that view's own doc comment
        // (and `IslandModel.cardOptions`'s) name as living on this side of the
        // `VibeCatCore`/`VibeCatUI` seam — this is where it actually runs for a
        // real launch, which is what `aStoredCardOptionsReachesARenderedRow`
        // (`LaunchWiringTests`) drives end to end.
        self.model.cardOptions = SessionRow.Options(prefs.cardOptions)
        // Read once, here, rather than left at IslandModel's own `false`
        // default — a relaunch with sound already muted must show muted
        // immediately, not flip visibly once something else happens to
        // touch `model.muted` first.
        self.model.muted = !prefs.soundEnabled
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

    /// The live local `keyDown` monitor, for `NotchControllerTests` only — same
    /// visibility reasoning as `panelForTesting`. Final whole-branch review,
    /// finding 4: Escape is the only user-initiated dismiss this app has, and
    /// nothing before this test read the monitor at all — deleting the whole
    /// installation block in `present()` failed no test, because every
    /// behavioural Escape test in this file drives `dismissOnEscape(_:)`
    /// directly rather than through a real, delivered `NSEvent` (there is no
    /// window server in `swift test` to deliver one). This closes the gap one
    /// level down from that: not "does Escape dismiss," which those tests
    /// already cover, but "is the monitor that would ever receive a real
    /// Escape actually installed at all."
    ///
    /// Plan 6.1 Task 4 inherits exactly the same gap for the number keys, and
    /// the same accessor closes it — plus `handleKeyDown(_:)`, which is what the
    /// monitor's closure now consists of, so that a *digit* branch deleted from
    /// the dispatch fails a test rather than only the whole block failing one.
    var keyMonitorForTesting: Any? { keyMonitor }

    /// The live Reduce Motion observer, for `MotionBypassTests` only — the same
    /// visibility reasoning as `keyMonitorForTesting`, and installed for
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
        // `answer(_:)`, not `appModel.answer(reply)` directly: answering is one
        // of the three ways a question ends, and every one of them has to give
        // key status back (see `holdsKeyStatus`). A mouse tap on a row and a
        // number key are the same ending, so they go through the same method
        // rather than each remembering to release on its own.
        model.onAnswer = { [weak self] reply in self?.answer(reply) }
        // The footer's mute button — see `toggleMute()` and
        // `onSoundEnabledChanged`'s own doc comments.
        model.onToggleMute = { [weak self] in self?.toggleMute() }

        // Escape dismisses without answering; a digit picks the row its badge
        // names (§10.1) — see `handleKeyDown(charactersIgnoringModifiers:)`,
        // which is the whole of this closure's decision so that both branches
        // are reachable from a test. Torn down and rebuilt the same way the
        // screen-parameters observer below is, so a second present() without an
        // intervening dismiss() re-installs rather than leaking a second
        // monitor.
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(charactersIgnoringModifiers: event.charactersIgnoringModifiers)
                ? nil : event
        }

        render()
        // Never makeKeyAndOrderFront *here* — presenting the island must not
        // take key status, because at this point there is nothing to answer and
        // a key panel swallows every keystroke the person aims at their terminal
        // (the spike's own hazard; see `holdsKeyStatus`). Key is taken only while
        // a drawer the person clicked open is on screen —
        // `takeKeyStatusIfADrawerIsOpen` — and that call does use
        // `makeKeyAndOrderFront`, which the spike measured as *not* activating
        // this app.
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
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        // Teardown is not one of the three question endings, but it ends the
        // window in which key status is legitimate just as finally: the panel is
        // ordered out immediately above, so AppKit has already resigned key —
        // this only stops this object from believing otherwise. Ordering
        // matters: `releaseKeyStatus()` reads `panel`, so it runs before the
        // `panel = nil` above would make it a no-op — which is why the release
        // is expressed as a plain flag reset here rather than a call.
        holdsKeyStatus = false
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
        // out of step with what the panel is actually showing.
        //
        // Plan 6.3 Task 1: this now grows the panel **sideways as well as down**,
        // because the open tier has a width of its own (560pt against a widest
        // collapsed 423.1pt). No code change was needed for that — `tier` was
        // already threaded through — but the comment that used to end here said
        // the width ceiling stayed fixed regardless, and it no longer does. See
        // IslandGeometry.maxCollapsedFrames.
        if let geometry, let panel {
            let needed = geometry.maxCollapsedFrames(tier: model.tier)
            if panel.frame != needed.panel {
                panel.apply(needed)
            }
        }

        // Last, after the panel is at the size the open drawer needs: a panel
        // that becomes key and *then* resizes is the same end state, but this
        // way the window the person's keystrokes are being routed to is never
        // momentarily the collapsed one. Idempotent — see its own guard.
        takeKeyStatusIfADrawerIsOpen()
    }

    /// Takes key status when — and only when — a drawer is actually on screen.
    ///
    /// **Widened in Plan 6.1 Task 6, from "an open drawer showing a question" to
    /// "an open drawer", and the widening is a decision rather than a
    /// simplification.** Task 4 gated on the question for a reason it measured: a
    /// question that has arrived but whose drawer nobody opened shows no badge,
    /// so a digit typed into a terminal would answer something invisible. That
    /// reason is untouched — this still requires `.drawer`, which requires
    /// `drawerOpen`, which only `click()` ever sets. What it changes is the
    /// *other* drawer: §11's session list is a drawer with no question, so it
    /// never took key, so **Escape — the only keyboard exit this app has — was
    /// never delivered to it at all** (Task 4's report, concern 2). A 420pt panel
    /// under the notch that could only be dismissed by clicking it again.
    ///
    /// The spike's constraint still binds, and this is where it is honoured: it
    /// forbids a panel holding key **at rest**, because then the person sees no
    /// sign that anything but their terminal is receiving keystrokes. An open
    /// drawer is the opposite of at rest — it is a black panel the person opened
    /// themselves with a deliberate click, and it is what they are looking at.
    /// The cost is real and worth stating: while it is open, delivery is
    /// exclusive, so typing into a terminal that still looks focused is
    /// swallowed. That cost buys the dismissal, it is bounded by the drawer being
    /// visibly open, and both of the ways to close it (Escape now, a second click
    /// as before) release key.
    ///
    /// A digit with no question is inert — `answerOnNumberKey` already guards on
    /// `model.question` — so widening this cannot answer anything: the session
    /// list has no rows to pick and no `Reply` to make.
    ///
    /// Called from `reflow()`, which every path that can open a drawer already
    /// funnels through (`click()`, `setQuestion(_:)`, `setHovering(_:)`), so
    /// there is one condition rather than one call per opener. It only ever
    /// *takes*; the releases are explicit at each ending below, because each
    /// ending must be separately breakable — a single shared release would let a
    /// missing one hide behind another.
    ///
    /// The gate is `case .drawer = model.tier`, not `model.drawerOpen`, matching
    /// `dismissOnEscape` and `answerOnNumberKey` — one reading of "a drawer is on
    /// screen" shared by the taker and both handlers, rather than three that
    /// could drift.
    ///
    /// `makeKeyAndOrderFront(nil)`, not `makeKey()`: it is the exact call the
    /// spike measured as taking key without changing `frontmostApplication`, and
    /// the panel is already ordered front, so the `orderFront` half is a no-op.
    /// Reaching for a call the measurement did not cover would be trading a
    /// verified behaviour for an assumed one. Note this contradicts `present()`'s
    /// own "never makeKeyAndOrderFront" comment as it stood before Plan 6.1: that
    /// comment was written while the hardware question was open, and the answer
    /// is that becoming key does *not* activate this app (Path A).
    private func takeKeyStatusIfADrawerIsOpen() {
        guard !holdsKeyStatus, case .drawer = model.tier, let panel else { return }
        holdsKeyStatus = true
        panel.makeKeyAndOrderFront(nil)
    }

    /// Gives key status back, so whatever the person types next reaches the app
    /// that has looked focused the whole time.
    ///
    /// `orderOut` then `orderFrontRegardless()`, rather than `resignKey()`:
    /// `resignKey()` is AppKit's *notification* that key status was lost, not a
    /// way to give it up (Apple's own documentation says it is invoked by the
    /// window system), while a window that is not on screen cannot be key at
    /// all — so ordering out is the one relinquishment that does not depend on
    /// some other window being available to take over, which for a
    /// single-panel, non-activating app there may not be. Both calls are in the
    /// same main-actor turn, so nothing is presented in between; the panel is
    /// borderless and transparent regardless. Verified on hardware in Task 4
    /// step 5 — see this task's own report — because "did key status actually go
    /// back" is not observable in a test process with no window server.
    private func releaseKeyStatus() {
        guard holdsKeyStatus else { return }
        holdsKeyStatus = false
        guard let panel else { return }
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    /// The first of the three ways a question ends. Wired to `model.onAnswer` in
    /// `present()` (a tap on a row or on Send) and called by
    /// `answerOnNumberKey` (§10.1's digit), so both finish the same way rather
    /// than each half-remembering what finishing involves.
    ///
    /// `internal`, not `private`: this file's own tests drive wiring entry points
    /// directly, the same as `click()`/`setHovering(_:)`/`toggleMute()`.
    func answer(_ reply: Reply) {
        appModel.answer(reply)
        releaseKeyStatus()
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
                // The third of the three endings. Deliberately here rather than
                // folded into `setQuestion(nil)` — which `dismissQuestion()`
                // above does reach — because a lapse, an answer and an Escape
                // must each be separately breakable: one shared release in
                // `setQuestion(nil)` would keep every test green with two of the
                // three paths deleted, which is the exact defect shape this
                // repo keeps finding. The audit that makes that safe is that
                // `AppModel.clearQuestion` has exactly two callers — `answer`
                // and `dismissQuestion` — and `dismissQuestion` has exactly two
                // of its own, this line and `dismissOnEscape`.
                self.releaseKeyStatus()
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
    /// becoming key — Task 9's then-open hardware question, settled by the
    /// key-input spike and confirmed for *both* drawer faces in Plan 6.1 Task 6.
    /// Without a second click closing it, a person who opens the drawer and
    /// changes their mind has no way to collapse it if that delivery never
    /// happens, short of answering or waiting out the lapse. Kept as a toggle
    /// even now that Escape does arrive: two independent exits from a panel that
    /// holds key exclusively is the right number, not redundancy.
    ///
    /// This only flips the
    /// *drawer's* own visibility, deliberately — it does not touch
    /// `appModel`'s pending question at all, unlike `dismissOnEscape`'s
    /// deliberate, fail-open dismiss below: a second click closing the
    /// drawer must not silently abandon a question the hook is still
    /// waiting on. The question stays parked, still running its own
    /// deadline, and a third click reopens the same one.
    /// A fourth release site, and deliberately not one of the three endings:
    /// clicking the drawer shut leaves the question parked (see the paragraph
    /// above), so the *question* has not ended — but the badges are off screen,
    /// and holding key past that is precisely the spike's hazard with nothing
    /// gained. `reflow()` will take it again if the drawer is clicked back open.
    /// Since Task 6 this is also how a clicked-shut **session list** gives key
    /// back, which is why the release is unconditional on there being a question.
    func click() {
        model.drawerOpen.toggle()
        if !model.drawerOpen { releaseKeyStatus() }
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
    /// Dismissing a *question* calls `appModel.dismissQuestion()` rather than
    /// touching `model` directly: that is the exact fail-open path a lapsed
    /// question already takes (see `setQuestion`'s own `lapseCheck`), already
    /// covered by Task 1/3's fail-open guarantees, and it reaches back into
    /// `model` through the same `onQuestion` wiring `setQuestion(_:)` already is —
    /// one path, not a second copy of "close the drawer" logic. Dismissing §11's
    /// **session list** cannot go that way, because there is no question to
    /// dismiss; see the body.
    ///
    /// Escape only, still — a digit is `answerOnNumberKey` below, not this. The
    /// two are separate functions rather than one switch because they carry
    /// different risk and are gated on different things: dismissing is safe
    /// under any outcome (worst case a drawer closes a beat early, recoverable
    /// with one more click), while answering has to route through
    /// `QuestionModel.pick`/`.reply()` so §10.3's second ask still binds. This
    /// one never calls either, regardless of what the keystroke was.
    ///
    /// **Correction, Plan 6.1 Task 4 (2026-08-04):** this comment used to say
    /// number keys could not be wired because delivery was "Task 9's own
    /// still-unmeasured hardware question." That question is answered — Path A,
    /// key without focus, measured three times with a witness document (see
    /// `docs/superpowers/spikes/2026-08-03-notch-panel-key-input.md`) — and the
    /// number keys are wired now. What the spike added instead is the *key
    /// status* constraint, which is why the dismiss below releases it.
    @discardableResult
    func dismissOnEscape(charactersIgnoringModifiers: String?) -> Bool {
        // Pattern match, not `== .drawer`: `IslandTier.drawer(face:)` carries
        // an associated value, the same reason `IslandView`'s own drawer gate
        // uses `if case .drawer = model.tier` rather than `==`.
        guard case .drawer = model.tier, KeyRouting.isEscape(charactersIgnoringModifiers) else { return false }
        // **This one line closes both faces of the drawer, including §11's
        // session list, which has no question to dismiss at all** — and that is
        // worth spelling out because Plan 6.1 Task 6 started by adding an explicit
        // `model.drawerOpen = false` here for the list, on the assumption that a
        // question-less Escape had to be a second, separate mechanism. It does
        // not, and the added block was dead code: deleting it again failed no
        // test, checked directly.
        //
        // Why one line suffices: `dismissQuestion()` is `pending?.lapse()` — a
        // no-op with nothing pending — followed by `clearQuestion()`, which fires
        // `onQuestion?(nil)` **unconditionally**, whether or not a question was
        // there. `present()` wires that to `setQuestion(_:)`, which resets
        // `model.drawerOpen` on a `nil` and reflows. So the list closes through
        // exactly the path a question takes, with no branch here.
        //
        // That makes this method depend on `clearQuestion` notifying even when it
        // changed nothing — the opposite of the guarded-write rule the rest of
        // this file follows, and an obvious future "optimisation" (`guard pending
        // != nil`) would silently make Escape stop closing the list. The coupling
        // is deliberate rather than accidental, and it is pinned:
        // `theSessionListTakesKeyStatusSoEscapeCanCloseIt` fails on that mutation.
        // A local `drawerOpen = false` here would have hidden the dependency
        // instead of naming it, and been untestable padding besides.
        //
        // What Task 6 actually had to change was one thing, not two: nothing made
        // the panel key without a question, so a real Escape was never delivered
        // to the list at all. See `takeKeyStatusIfADrawerIsOpen`.
        appModel.dismissQuestion()
        // The second of the three endings — see the lapse `Task`'s own comment
        // on why this is not folded into `setQuestion(nil)`. Since Task 6 it is
        // also the release for a closed session list, which is not one of the
        // three: no question ended, but the drawer is gone, so holding key past
        // this would be the spike's hazard with nothing on screen to justify it.
        releaseKeyStatus()
        return true
    }

    /// §10.1: "A number badge marks each row and the matching number key picks
    /// it." The whole of the keyboard's answering path, and every line of it is
    /// a guard for a reason:
    ///
    /// - **The drawer has to be open.** The digit a person presses is the one
    ///   printed on a badge, and a badge only exists inside an open drawer.
    ///   Without this, `1` typed anywhere would answer a question whose choices
    ///   are not on screen. Same pattern match, and for the same reason, as
    ///   `dismissOnEscape` above.
    /// - **Single select only.** §10.2 draws the distinction in the control: a
    ///   number badge means the click is the answer, a checkbox means it is not,
    ///   and a multi-select row shows a checkbox. So there is no digit on screen
    ///   to press, and this reports the keystroke unhandled rather than eating
    ///   it. `QuestionModel.pick` would already refuse (it guards `!isMulti`),
    ///   so this is legibility over a silent no-op, not the only thing standing
    ///   between a digit and a multi-select answer.
    /// - **Not while `Other…`'s field is up.** `isWritingOther` means the person
    ///   is typing free text (Plan 6.1 Task 5 restores the row), and `2` in
    ///   "port 8082" is a character, not a choice. Consuming it here would make
    ///   the field silently undigitable.
    /// - **`KeyRouting.pick`, then `QuestionModel.pick`, then `reply()`.** The
    ///   order is the point. `KeyRouting.pick` only *reads* which row a digit
    ///   names — its own doc comment is explicit that this must then go through
    ///   the model, "never fabricate a `Reply` directly from a raw id," because a
    ///   fabricated `Reply` would walk straight around §10.3's second ask for a
    ///   destructive command. `reply()` returning `nil` while confirmation is
    ///   outstanding is what makes the second press, not the first, the answer.
    ///
    /// The body below is `QuestionFace.tapped(_:)`'s single-select branch,
    /// deliberately: a digit is the same gesture as a tap on the row that digit
    /// names, including "pressing the same one again is the confirmation" —
    /// §10.3's banner says *tap the highlighted choice again*, and the number key
    /// is how that choice is reachable from the keyboard. It is duplicated rather
    /// than shared because `QuestionFace` is a SwiftUI `View` in the drawer and
    /// this is the controller; the coupling is pinned by
    /// `theNumberKeyAndTheTapAgreeOnWhatASecondPressMeans`.
    @discardableResult
    func answerOnNumberKey(charactersIgnoringModifiers: String?) -> Bool {
        guard case .drawer = model.tier, let question = model.question else { return false }
        guard !question.isMulti, !question.isWritingOther else { return false }
        guard let characters = charactersIgnoringModifiers, characters.count == 1,
              let digit = characters.first,
              let id = KeyRouting.pick(character: digit, in: question) else { return false }

        if question.selected.contains(id) && question.needsConfirmation {
            question.confirm()
        } else {
            question.pick(id)
        }
        if let reply = question.reply() { answer(reply) }
        return true
    }

    /// The whole of the local `keyDown` monitor's decision, factored out for the
    /// same reason `dismissOnEscape` itself was: there is no window server in
    /// `swift test`, so the only way a test can exercise what the monitor *does*
    /// is to call what the monitor calls. Escape first — dismissing must stay
    /// reachable even if a question's own state somehow made the digit path
    /// throw a guard — then §10.1's digits. Returns whether the keystroke was
    /// consumed, which the monitor turns into `nil` (swallow) or the event
    /// itself (fall through).
    ///
    /// This exists as its own function rather than as two calls inside the
    /// closure because a closure body is unreachable from a test: with the
    /// dispatch inline, deleting the digit branch would fail nothing, which is
    /// exactly the gap `keyMonitorForTesting`'s own comment records for the
    /// installation block one level up.
    @discardableResult
    func handleKeyDown(charactersIgnoringModifiers: String?) -> Bool {
        if dismissOnEscape(charactersIgnoringModifiers: charactersIgnoringModifiers) { return true }
        return answerOnNumberKey(charactersIgnoringModifiers: charactersIgnoringModifiers)
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
