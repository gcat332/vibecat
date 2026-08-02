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

    /// The strip the aura blooms into, which is what has to be measured — not
    /// the island itself, which is our own ground colour and would always read
    /// dark. The panel rect is exactly that region plus the island, and
    /// `BackdropSampler` excludes our own window from the capture, so what
    /// comes back is whatever is behind both.
    private func backdropRegion() -> CGRect {
        let panel = model.frames.panel
        guard let screen = metrics()?.frame else { return panel }
        // ScreenCaptureKit's sourceRect has a top-left origin; ours is
        // bottom-left, as AppKit's is.
        return CGRect(x: panel.minX, y: screen.maxY - panel.maxY,
                      width: panel.width, height: panel.height)
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
        panel?.apply(geometry.maxCollapsedFrames())
        hover?.frame = model.frames.body
    }

    public func present() {
        guard let geometry else { return }
        // The panel is sized once, at the widest the collapsed island can
        // ever be, and never resized again while collapsed — measured,
        // animating the silhouette inside a fixed window beats animating the
        // window itself (p95 10.34ms vs 15.16ms). Growth from here on is the
        // body's job, inside IslandBody, not the panel's.
        let frames = geometry.maxCollapsedFrames()
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
        hover.onChange = { [weak self] hovering in
            self?.tier = hovering ? .hover : .rest
            // A hover edge is not a display change, so this reflows the
            // existing geometry rather than re-deriving it from
            // NSScreen.screens the way refreshGeometry() does.
            self?.reflow()
        }
        hover.start()
        self.hover = hover

        // Deterministic and race-free, unlike the withObservationTracking
        // bridge this replaced: every ingest or store-changing prune notifies
        // directly, with no one-shot registration to fall through between a
        // fire and a re-arm. See AppModel.onChange.
        appModel.onChange = { [weak self] in self?.reflow() }

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
        bloomEnd?.cancel()
        bloomEnd = nil
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
    /// needed here, `bloomEnd` included, so deinit just calls it.
    isolated deinit {
        dismiss()
    }

    /// Updates the model's hover flag and the hover monitor's own hit-test
    /// frame, then re-renders. The handler for both the hover monitor's edge
    /// (a tier change) and `appModel.onChange` (a session-count or state
    /// change) — both need the model resynced. Neither needs the panel
    /// touched: it never resizes while the island is collapsed, so unlike
    /// the pre-Task-9 version of this method, there is no frame to re-apply.
    private func reflow() {
        model.hovering = (tier == .hover)
        hover?.frame = model.frames.body
        render()
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
