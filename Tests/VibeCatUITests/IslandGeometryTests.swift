import Testing
import CoreGraphics
@testable import VibeCatUI

private let mbp14 = ScreenMetrics(
    frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
    visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
    safeAreaTop: 32,
    auxLeft: CGRect(x: 0, y: 950, width: 663, height: 32),
    auxRight: CGRect(x: 848, y: 950, width: 664, height: 32))

private let externalDisplay = ScreenMetrics(
    frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
    visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1415),
    safeAreaTop: 0, auxLeft: nil, auxRight: nil)

/// Design §5.3. This is the whole reason LW is a constant.
@Test func theLeftEdgeDoesNotMoveWhenTheRightFlankGrows() {
    let g = IslandGeometry(screen: mbp14)
    let widths: [CGFloat] = [0, 35, 51, 120, 400]
    let edges = widths.map { g.frames(rightFlank: $0, tier: .rest).body.minX }
    #expect(Set(edges).count == 1)
    // The `as CGFloat` anchors the literal arithmetic's type explicitly: on
    // this toolchain (swift-testing under Swift 6.3.2), `#expect` mis-resolves
    // a bare Int-literal expression compared against a CGFloat property,
    // reporting a spurious failure even though both sides are exactly 605.0.
    // Confirmed with %.20f precision printing; Double does not exhibit this.
    #expect(edges[0] == (663 - 58 as CGFloat))
}

@Test func restBodySpansLeftFlankPlusNotchPlusRightFlank() {
    let g = IslandGeometry(screen: mbp14)
    let dormant = g.frames(rightFlank: 0, tier: .rest).body
    #expect(dormant.width == (58 + 185 as CGFloat))
    #expect(dormant.height == 32)
    #expect(dormant.maxY == 982)

    let running = g.frames(rightFlank: 35, tier: .rest).body
    #expect(running.width == (58 + 185 + 35 as CGFloat))
}

/// The aura blooms outside the shape, and never above the notch.
@Test func thePanelIsInflatedForTheAuraOnThreeSidesOnly() {
    let g = IslandGeometry(screen: mbp14)
    let f = g.frames(rightFlank: 35, tier: .rest)
    #expect(f.panel.maxY == f.body.maxY)                       // no top margin
    #expect(f.panel.minX == f.body.minX - IslandGeometry.auraMargin)
    #expect(f.panel.maxX == f.body.maxX + IslandGeometry.auraMargin)
    #expect(f.panel.minY == f.body.minY - IslandGeometry.auraMargin)
}

/// Panel-local coordinates are flipped (SwiftUI y grows downward) and there
/// is no top margin, so the shape starts flush with the panel's top edge.
@Test func bodyInPanelIsTheBodyExpressedInPanelLocalCoordinates() {
    let g = IslandGeometry(screen: mbp14)
    let f = g.frames(rightFlank: 35, tier: .rest)
    #expect(f.bodyInPanel.origin == CGPoint(x: IslandGeometry.auraMargin, y: 0))
    #expect(f.bodyInPanel.size == f.body.size)
}

@Test func theDrawerGrowsDownwardAndKeepsItsTopAtTheScreenEdge() {
    let g = IslandGeometry(screen: mbp14)
    let f = g.frames(rightFlank: 35, tier: .drawer(height: 288))
    #expect(f.body.height == (32 + 288 as CGFloat))
    #expect(f.body.maxY == 982)
    #expect(f.body.minX == (663 - 58 as CGFloat))   // still pinned
}

/// A notchless display gets a floating pill in the same place, with no
/// dead zone to route content around. Design §5.1.
@Test func aNotchlessDisplayGetsAFallbackPill() {
    let g = IslandGeometry(screen: externalDisplay)
    #expect(g.isFallbackPill)
    #expect(g.notch.width == 0)
    let f = g.frames(rightFlank: 40, tier: .rest)
    #expect(f.body.width == (58 + 40 as CGFloat))
    #expect(f.body.midX == externalDisplay.frame.midX)
    #expect(f.body.maxY == externalDisplay.frame.maxY)
}

/// The panel must never hang off the side of the display.
@Test func thePanelIsClampedToTheScreen() {
    let g = IslandGeometry(screen: mbp14)
    let f = g.frames(rightFlank: 5000, tier: .rest)
    #expect(f.panel.minX >= mbp14.frame.minX)
    #expect(f.panel.maxX <= mbp14.frame.maxX)
}

/// The spike: content animation beats window-frame animation (p95 10.34ms vs
/// 15.16ms). So the panel is created once at its widest and never resized.
@Test func theMaximumCollapsedPanelHoldsEveryCollapsedState() {
    let g = IslandGeometry(screen: mbp14)
    let maxFrames = g.maxCollapsedFrames()

    let states: [CollapsedLayout] = [
        CollapsedLayout(right: .nothing, hovering: false),
        CollapsedLayout(right: .nothing, hovering: true),
        CollapsedLayout(right: .agentIcon, hovering: true),
        CollapsedLayout(right: .sessionCount(1), hovering: true),
        CollapsedLayout(right: .sessionCount(999), hovering: true),
    ]
    for layout in states {
        let f = g.frames(rightFlank: layout.rightFlankWidth, tier: .rest)
        #expect(f.panel.width <= maxFrames.panel.width + 0.001,
                "\(layout.right) hovering=\(layout.hovering) exceeds the fixed panel")
        #expect(f.body.maxX <= maxFrames.body.maxX + 0.001,
                "\(layout.right) hovering=\(layout.hovering) exceeds the fixed panel")
    }
}

/// Fix round 1: `RightContent.sessionCount` takes an unbounded `Int` —
/// nothing enforced the "three digits" assumption `maxCollapsedFrames()` was
/// built on, so a four-digit-or-larger count (unpruned running/waiting
/// sessions have no upper bound) would overflow the fixed panel. This probes
/// the type's actual range rather than the assumption of a small count.
///
/// Fix round 2: pairs the width assertion with a rendered-text one, in the
/// same loop over the same counts — a width-only pass is exactly what let
/// the other half of this bug (`IslandView` drawing the unclamped count and
/// clipping it against the silhouette, even though the panel itself now
/// fit) read as a complete fix.
@Test func theMaximumCollapsedPanelHoldsAbsurdSessionCounts() {
    let g = IslandGeometry(screen: mbp14)
    let maxFrames = g.maxCollapsedFrames()

    for n in [1_000, 999_999, Int.max] {
        let layout = CollapsedLayout(right: .sessionCount(n), hovering: true)
        let f = g.frames(rightFlank: layout.rightFlankWidth, tier: .rest)
        #expect(f.panel.width <= maxFrames.panel.width + 0.001,
                "sessionCount(\(n)) hovering=true exceeds the fixed panel")
        #expect(f.body.maxX <= maxFrames.body.maxX + 0.001,
                "sessionCount(\(n)) hovering=true exceeds the fixed panel")
        #expect(layout.sessionCountText?.count == 3,
                "sessionCount(\(n)) hovering=true should render as three characters")
    }
}

/// Whatever the panel's width, the left edge is where it always was.
@Test func theFixedPanelDoesNotMoveTheLeftEdge() {
    let g = IslandGeometry(screen: mbp14)
    let dormant = g.frames(rightFlank: 0, tier: .rest)
    #expect(g.maxCollapsedFrames().panel.minX == dormant.panel.minX)
    #expect(g.maxCollapsedFrames().body.minX == dormant.body.minX)
}

@Test func theFixedPanelIsWideEnoughForTheHoverReveal() {
    let g = IslandGeometry(screen: mbp14)
    let rest = g.frames(rightFlank: CollapsedLayout(right: .sessionCount(999),
                                                    hovering: false).rightFlankWidth,
                        tier: .rest)
    #expect(g.maxCollapsedFrames().body.width - rest.body.width >= CollapsedLayout.hoverReveal)
}
