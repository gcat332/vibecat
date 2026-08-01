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

/// The fillets flare outside the core, so the shape is wider than the body.
/// With an empty right flank the right fillet is suppressed and only the
/// left flare is added.
@Test func theShapeAddsAFlareOnEachSideThatHasAFillet() {
    let g = IslandGeometry(screen: mbp14)
    let f = IslandGeometry.fillet

    let running = g.frames(rightFlank: 35, tier: .rest)
    #expect(running.shape.width == running.body.width + f * 2)
    #expect(running.shape.minX == running.body.minX - f)

    let dormant = g.frames(rightFlank: 0, tier: .rest)
    #expect(dormant.shape.width == dormant.body.width + f)
    #expect(dormant.shape.maxX == dormant.body.maxX)   // no right flare
}

/// The aura blooms outside the shape, and never above the notch.
@Test func thePanelIsInflatedForTheAuraOnThreeSidesOnly() {
    let g = IslandGeometry(screen: mbp14)
    let f = g.frames(rightFlank: 35, tier: .rest)
    #expect(f.panel.maxY == f.shape.maxY)                       // no top margin
    #expect(f.panel.minX == f.shape.minX - IslandGeometry.auraMargin)
    #expect(f.panel.maxX == f.shape.maxX + IslandGeometry.auraMargin)
    #expect(f.panel.minY == f.shape.minY - IslandGeometry.auraMargin)
}

/// Panel-local coordinates are flipped (SwiftUI y grows downward) and there
/// is no top margin, so the shape starts flush with the panel's top edge.
@Test func shapeInPanelIsTheShapeExpressedInPanelLocalCoordinates() {
    let g = IslandGeometry(screen: mbp14)
    let f = g.frames(rightFlank: 35, tier: .rest)
    #expect(f.shapeInPanel.origin == CGPoint(x: IslandGeometry.auraMargin, y: 0))
    #expect(f.shapeInPanel.size == f.shape.size)
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
