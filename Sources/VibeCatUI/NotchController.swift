import AppKit
import SwiftUI

/// Owns the panel, the geometry and the hover monitor, and keeps the
/// `IslandModel` in step with the app model and with the display.
@MainActor public final class NotchController {
    public private(set) var geometry: IslandGeometry?
    public private(set) var tier: IslandTier = .rest

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
    private var panel: NotchPanel?
    private var hover: HoverMonitor?
    private var bloomEnd: Task<Void, Never>?
    private var observer: NSObjectProtocol?
    private let sampler = BackdropSampler()
    private var backdropSample: Task<Void, Never>?
    /// Cancel-and-reschedule, the same shape as `bloomEnd` and for the same
    /// reason: a question's expiry mirrors the hook's own deadline (see
    /// `PendingQuestion.expiry`), and once it passes with nobody answering,
    /// the drawer has to close itself rather than keep showing a question
    /// the hook has already abandoned — see `setQuestion`.
    private var lapseCheck: Task<Void, Never>?

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

    public init(model appModel: AppModel, metrics: @escaping @MainActor () -> ScreenMetrics?) {
        self.appModel = appModel
        self.metrics = metrics
        let geometry = IslandGeometry(screen: metrics() ?? .zeroFallback)
        self.model = IslandModel(geometry: geometry, motion: MotionPreference.current())
    }

    public convenience init(model: AppModel) {
        self.init(model: model, metrics: { ScreenMetrics.current() })
    }

    /// The live panel, for `NotchControllerTests` only — deliberately not
    /// `public`, so a normal `import VibeCatUI` never sees it and only
    /// `@testable import` does. `present()` already constructs a real
    /// `NSPanel` in the test process; this is what lets a test observe both
    /// that it stays fixed at its maximum collapsed size (Task 9) and that
    /// `appModel.onChange` really reaches `model` rather than merely being
    /// non-nil.
    var panelForTesting: NotchPanel? { panel }

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
        if !(panel.contentView is NSHostingView<IslandView>) {
            panel.contentView = NSHostingView(rootView: IslandView(model: model))
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
    }

    public func dismiss() {
        appModel.onChange = nil
        appModel.onQuestion = nil
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

    /// Updates the model's hover flag and the hover monitor's own hit-test
    /// frame, re-renders, then keeps the panel in step with the model's own
    /// tier. The handler for the hover monitor's edge (a tier change),
    /// `appModel.onChange` (a session-count or state change), and — via
    /// `setHovering`/`setQuestion`/`click` below — every way the drawer's own
    /// tier can change, all funnel through here rather than each repeating
    /// this same synchronisation.
    private func reflow() {
        model.hovering = (tier == .hover)
        hover?.frame = model.frames.body
        render()

        // Clicks are taken only where a click would do something. Everywhere
        // else the menu bar underneath stays clickable — which is what makes
        // Plan 3's oversized fixed panel safe (see maxCollapsedFrames).
        //
        // model.question, not appModel.pending: the two always agree in
        // production (present() sets pending immediately before the
        // onQuestion callback that reaches model.question here), but only
        // the model is reachable from a direct setQuestion(_:) call — which
        // is exactly how this file's own tests drive the state machine,
        // deliberately bypassing AppModel entirely (see makeController()).
        // Reading appModel.pending here would make those tests unsatisfiable
        // regardless of anything else NotchController did.
        panel?.acceptsClicks = model.hovering && model.question != nil

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
        tier = hovering ? .hover : .rest
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
                guard !Task.isCancelled else { return }
                // Lapses the PendingQuestion — waking a socket thread still
                // parked on it, or a no-op if it already timed out on its
                // own — and clears appModel.pending, which reaches back here
                // via onQuestion(nil) above.
                self?.appModel.dismissQuestion()
            }
        }
        reflow()
    }

    /// The island was clicked while it could take clicks (see
    /// `NotchPanel.acceptsClicks`) — opens the drawer on whichever question
    /// is currently showing. A no-op if there is none: `model.tier`'s own
    /// guard also requires a question, so setting this with nothing pending
    /// leaves the tier at `.rest`/`.hover` regardless.
    func click() {
        model.drawerOpen = true
        reflow()
    }

    private func render() {
        let now = Date()
        model.state = appModel.islandState
        model.sessionCount = appModel.sessionCount

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
            // needsTimeline reads the aura, so the view must be nudged once
            // more when the bloom ends, or its TimelineView never stops —
            // reassigning model.aura is that nudge: @Observable notifies on
            // the write itself, regardless of whether the value it computes
            // back to is equal to what was already there.
            bloomEnd?.cancel()
            bloomEnd = Task { [weak self] in
                try? await Task.sleep(for: .seconds(AuraTrigger.duration))
                guard !Task.isCancelled else { return }
                self?.model.aura = self?.model.aura ?? AuraTrigger()
            }
        }
    }
}
