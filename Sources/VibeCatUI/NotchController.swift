import AppKit
import SwiftUI
import Observation

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
    /// Guards the model-observation callback below against firing after
    /// `dismiss()` — the tracked closure can still be in flight at that point.
    private var isPresented = false

    public init(model: AppModel, metrics: @escaping @MainActor () -> ScreenMetrics?) {
        self.model = model
        self.metrics = metrics
    }

    public convenience init(model: AppModel) {
        self.init(model: model, metrics: { ScreenMetrics.current() })
    }

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
        hover.frame = frames.shape
        hover.onChange = { [weak self] hovering in
            self?.tier = hovering ? .hover : .rest
            self?.refreshGeometry()
        }
        hover.start()
        self.hover = hover

        render()
        // Never makeKeyAndOrderFront — the app must not steal focus.
        panel.orderFrontRegardless()

        isPresented = true
        observeModel()

        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshGeometry() }
            }
    }

    public func dismiss() {
        isPresented = false
        bloomEnd?.cancel()
        bloomEnd = nil
        hover?.stop()
        hover = nil
        panel?.orderOut(nil)
        panel = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    /// `AppModel` is `@Observable`, but nothing in `AppKit`'s notification-driven
    /// world reads it as a SwiftUI view would — hover and screen-change events
    /// both call back into the controller directly, but an event arriving over
    /// the socket updates `model` with no callback at all. Without this, the
    /// panel would freeze on whatever it last rendered until the next hover
    /// transition or display change happened to redraw it. `withObservationTracking`
    /// is the imperative-code equivalent of a SwiftUI view reading the model:
    /// it fires once on the next change to anything read inside the tracked
    /// closure, then has to be re-armed — which is what `reflow()` triggering
    /// another call to this function does.
    private func observeModel() {
        withObservationTracking {
            _ = model.islandState
            _ = model.sessionCount
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isPresented else { return }
                self.reflow()
                self.observeModel()
            }
        }
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
    /// `observeModel()` (a layout change driven by the model, e.g. the
    /// session count changing the right flank's width) — both need the panel
    /// resized, not just repainted.
    private func reflow() {
        guard let frames = currentFrames() else { return }
        panel?.apply(frames)
        hover?.frame = frames.shape
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
