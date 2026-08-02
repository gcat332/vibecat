import AppKit
import SwiftUI
import Testing
import CoreGraphics
@testable import VibeCatUI

private let mbp14 = ScreenMetrics(
    frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
    visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
    safeAreaTop: 32,
    auxLeft: CGRect(x: 0, y: 950, width: 663, height: 32),
    auxRight: CGRect(x: 848, y: 950, width: 664, height: 32))

@MainActor private func panel(rightFlank: CGFloat = 35) -> (NotchPanel, IslandFrames) {
    let frames = IslandGeometry(screen: mbp14).frames(rightFlank: rightFlank, tier: .rest)
    return (NotchPanel(frames: frames), frames)
}

/// Spike §2 (and its correction). At `.statusBar` (25), AppKit's own
/// `constrainFrameRect` already leaves the frame alone — the clamp to
/// `visibleFrame` only bites at level 23 and below. The override here is a
/// backstop, not what puts the island in the notch: the earlier y=917
/// measurement was taken on a panel accidentally left at level 3 by the
/// `isFloatingPanel` ordering trap, not on this panel at its real level.
@MainActor @Test func constrainFrameRectReturnsTheRequestedFrameUntouched() {
    let (p, frames) = panel()
    let asked = frames.panel
    #expect(p.constrainFrameRect(asked, to: nil) == asked)
    #expect(p.constrainFrameRect(asked, to: NSScreen.main) == asked)
}

@MainActor @Test func theFrameSurvivesBeingSet() {
    let (p, frames) = panel()
    p.setFrame(frames.panel, display: false)
    #expect(p.frame == frames.panel)
}

/// Spike §3. The menu bar is layer 24; 25 is the lowest level that clears it.
@MainActor @Test func theLevelIsStatusBar() {
    let (p, _) = panel()
    #expect(p.level == .statusBar)
    #expect(p.level.rawValue == 25)
}

@MainActor @Test func itSurvivesSpacesAndFullscreen() {
    let (p, _) = panel()
    #expect(p.collectionBehavior.contains(.canJoinAllSpaces))
    #expect(p.collectionBehavior.contains(.fullScreenAuxiliary))
    #expect(p.collectionBehavior.contains(.stationary))
    #expect(p.hidesOnDeactivate == false)
}

@MainActor @Test func itIsTransparentAndUnadorned() {
    let (p, _) = panel()
    #expect(p.isOpaque == false)
    #expect(p.backgroundColor == .clear)
    #expect(p.hasShadow == false)
    #expect(p.isMovable == false)
}

/// Spike §5. A menu title can reach within ~30pt of the island's left edge,
/// so at rest the island must not be able to swallow a click.
@MainActor @Test func itIsClickThroughUntilMadeToAcceptClicks() {
    let (p, _) = panel()
    #expect(p.ignoresMouseEvents == true)
    #expect(p.acceptsClicks == false)

    p.acceptsClicks = true
    #expect(p.ignoresMouseEvents == false)

    p.acceptsClicks = false
    #expect(p.ignoresMouseEvents == true)
}

@MainActor @Test func applyMovesThePanelToTheNewFrames() {
    let (p, _) = panel(rightFlank: 0)
    let grown = IslandGeometry(screen: mbp14).frames(rightFlank: 120, tier: .rest)
    p.apply(grown)
    #expect(p.frame == grown.panel)
}

// MARK: - Fix round 1: wiring the click

/// AppKit's own default for any `NSView` is "the first click while the
/// window is not key wakes the window up; the view only sees a second one" —
/// exactly wrong for a click-to-open gesture on a panel that is deliberately
/// `.nonactivatingPanel` + `becomesKeyOnlyIfNeeded` and should never need a
/// wake-up tap at all. This is a plain AppKit method call, the same way
/// `constrainFrameRectReturnsTheRequestedFrameUntouched` above calls
/// `constrainFrameRect` directly rather than through a real event — the one
/// piece of the click-wiring that *is* testable this way, since
/// `acceptsFirstMouse` is an ordinary override, not a SwiftUI gesture.
@MainActor @Test func theHostingViewAcceptsFirstMouse() {
    let model = IslandModel(geometry: IslandGeometry(screen: mbp14),
                            motion: MotionPreference(chosen: .full, systemWantsReduced: false))
    let view = IslandHostingView(rootView: IslandView(model: model))
    #expect(view.acceptsFirstMouse(for: nil),
            "the first click after this app is not frontmost would be swallowed as a wake-up tap instead of opening the drawer")
}

/// `isFloatingPanel`'s setter reassigns `level` as a side effect (see
/// `NotchPanel.init`'s own comment) — confirming that assigning the new
/// `IslandHostingView` as the panel's `contentView` afterwards does not
/// somehow revisit that ordering and clobber it. Nothing about assigning a
/// content view should touch window level at all; this pins that it does
/// not, rather than assuming it.
@MainActor @Test func assigningTheHostingViewDoesNotMoveTheLevel() {
    let (p, _) = panel()
    #expect(p.level == .statusBar)
    let model = IslandModel(geometry: IslandGeometry(screen: mbp14),
                            motion: MotionPreference(chosen: .full, systemWantsReduced: false))
    p.contentView = IslandHostingView(rootView: IslandView(model: model))
    #expect(p.level == .statusBar, "assigning the hosting view moved the panel off .statusBar")
}
