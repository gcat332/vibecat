import AppKit
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

/// Spike §2. AppKit clamps a window out of the menu bar unless
/// constrainFrameRect refuses. Measured without the override: y=917, not 950.
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
@MainActor @Test func itIsClickThroughUntilMadeInteractive() {
    let (p, _) = panel()
    #expect(p.ignoresMouseEvents == true)
    #expect(p.isInteractive == false)

    p.isInteractive = true
    #expect(p.ignoresMouseEvents == false)

    p.isInteractive = false
    #expect(p.ignoresMouseEvents == true)
}

@MainActor @Test func applyMovesThePanelToTheNewFrames() {
    let (p, _) = panel(rightFlank: 0)
    let grown = IslandGeometry(screen: mbp14).frames(rightFlank: 120, tier: .rest)
    p.apply(grown)
    #expect(p.frame == grown.panel)
}
