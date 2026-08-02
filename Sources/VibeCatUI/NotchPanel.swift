import AppKit

/// The window that sits in the notch.
///
/// Two of its settings are load-bearing and were measured, not assumed —
/// see docs/superpowers/spikes/2026-08-01-notch-shell-spike.md. The third,
/// `constrainFrameRect`, is a backstop rather than load-bearing at the level
/// this panel actually ships at (see the override's own doc comment below).
@MainActor public final class NotchPanel: NSPanel {

    public init(frames: IslandFrames) {
        super.init(contentRect: frames.panel,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        // NSPanel's isFloatingPanel setter reassigns the window level as a
        // side effect (to .floating, raw 3) — measured on this machine. It
        // must be set before `level`, never after, or it silently undoes the
        // load-bearing .statusBar assignment below.
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        worksWhenModal = true
        collectionBehavior = [.canJoinAllSpaces, .stationary,
                              .fullScreenAuxiliary, .ignoresCycle]

        // Above the menu bar (layer 24). The lowest level that clears it;
        // going higher only starts fighting menus and alerts. Must be set
        // after isFloatingPanel, see note above.
        level = .statusBar

        // At rest the island is click-through: a menu title can reach within
        // about 30pt of its left edge, and an opaque flank would eat the click.
        ignoresMouseEvents = true

        setFrame(frames.panel, display: false)
    }

    /// At `.statusBar` (25), AppKit's own `constrainFrameRect` already leaves the
    /// frame alone — the clamp to `visibleFrame` only bites below level 24, and
    /// this panel never runs at that level. So this override changes nothing
    /// while the level is correct; it is a backstop, not what puts the island
    /// in the notch. Keep it anyway: we have already watched the level get
    /// clobbered once by a non-obvious setter side effect (see `isFloatingPanel`
    /// above), and if that happens again this turns "wrong level *and* silently
    /// displaced 33pt" into just "wrong level". See spike §2 (and its
    /// correction) for the measurements behind this.
    public override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    /// Borderless panels refuse key status by default, and the reply field in
    /// Plan 4 needs it.
    public override var canBecomeKey: Bool { true }

    /// Whether a click lands on the island or passes through to the menu bar.
    ///
    /// False at rest, always: an oversized transparent panel that intercepts
    /// nothing is what makes Plan 3's fixed-size panel safe. The drawer needs
    /// clicks, so this is turned on exactly while the pointer is over the
    /// island *and* there is something a click would do — see
    /// `NotchController.reflow`.
    public var acceptsClicks: Bool {
        get { !ignoresMouseEvents }
        set { ignoresMouseEvents = !newValue }
    }

    public func apply(_ frames: IslandFrames) {
        setFrame(frames.panel, display: true)
    }
}
