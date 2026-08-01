import AppKit
import SwiftUI

/// Owns the panel, the geometry and the hover monitor, and keeps them in step
/// with the model and with the display.
@MainActor public final class NotchController {
    public private(set) var geometry: IslandGeometry?
    public private(set) var tier: IslandTier = .rest

    private let model: AppModel
    private let metrics: @MainActor () -> ScreenMetrics?
    private var panel: NotchPanel?
    private var hover: HoverMonitor?
    private var aura = AuraTrigger()
    private var bloomEnd: Task<Void, Never>?
    private var observer: NSObjectProtocol?

    public init(model: AppModel, metrics: @escaping @MainActor () -> ScreenMetrics?) {
        self.model = model
        self.metrics = metrics
    }

    public convenience init(model: AppModel) {
        self.init(model: model, metrics: { ScreenMetrics.current() })
    }

    /// The live panel, for `NotchControllerTests` only — deliberately not
    /// `public`, so a normal `import VibeCatUI` never sees it and only
    /// `@testable import` does. `present()` already constructs a real
    /// `NSPanel` in the test process; this is what lets a test observe that
    /// `model.onChange` drives an actual frame change on it, rather than
    /// merely checking the closure is non-nil.
    var panelForTesting: NotchPanel? { panel }

    public func refreshGeometry() {
        geometry = metrics().map(IslandGeometry.init(screen:))
        reflow()
    }

    public func present() {
        guard let frames = currentFrames() else { return }

        let panel = self.panel ?? NotchPanel(frames: frames)
        self.panel = panel
        panel.apply(frames)

        let hover = self.hover ?? HoverMonitor()
        hover.frame = frames.body
        hover.onChange = { [weak self] hovering in
            self?.tier = hovering ? .hover : .rest
            // A hover edge is not a display change, so this reflows the
            // existing geometry rather than re-deriving it from
            // NSScreen.screens the way refreshGeometry() does. reflow()
            // still updates hover.frame (from currentFrames().body), so the
            // hover monitor's own frame stays correct across the tier change.
            self?.reflow()
        }
        hover.start()
        self.hover = hover

        // Deterministic and race-free, unlike the withObservationTracking
        // bridge this replaced: every ingest or store-changing prune notifies
        // directly, with no one-shot registration to fall through between a
        // fire and a re-arm. See AppModel.onChange.
        model.onChange = { [weak self] in self?.reflow() }

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
        model.onChange = nil
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

    private var layout: CollapsedLayout {
        let hovering = tier == .hover
        let count = model.sessionCount
        return CollapsedLayout(right: count > 0 ? .sessionCount(count) : .nothing,
                               hovering: hovering)
    }

    private func currentFrames() -> IslandFrames? {
        geometry?.frames(rightFlank: layout.rightFlankWidth, tier: tier)
    }

    /// Re-applies the current frames to the panel and hover monitor, then
    /// renders. Shared by `refreshGeometry()` (a real geometry change) and
    /// `model.onChange` (a layout change driven by the model, e.g. the
    /// session count changing the right flank's width) — both need the panel
    /// resized, not just repainted.
    private func reflow() {
        guard let frames = currentFrames() else { return }
        panel?.apply(frames)
        hover?.frame = frames.body
        render()
    }

    private func render() {
        guard let geometry, let frames = currentFrames(), let panel else { return }
        let now = Date()
        let state = model.islandState

        // AuraTrigger does its own change detection, so this is called
        // unconditionally and only reports true on an actual change.
        if aura.observe(state, now: now) {
            // TimelineView fixes its paused flag when the view is built, so
            // one more render is needed to stop it ticking after the bloom.
            bloomEnd?.cancel()
            bloomEnd = Task { [weak self] in
                try? await Task.sleep(for: .seconds(AuraTrigger.duration))
                guard !Task.isCancelled else { return }
                self?.render()
            }
        }

        let view = IslandView(state: state, layout: layout, aura: aura,
                              now: now, geometry: geometry, frames: frames)
        if let hosting = panel.contentView as? NSHostingView<IslandView> {
            hosting.rootView = view
        } else {
            panel.contentView = NSHostingView(rootView: view)
        }
    }
}
