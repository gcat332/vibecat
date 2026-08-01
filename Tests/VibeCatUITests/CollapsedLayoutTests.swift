import Testing
import CoreGraphics
@testable import VibeCatUI

@Test func nothingOnTheRightMeansNoRightFlankAndNoFillet() {
    let l = CollapsedLayout(right: .nothing, hovering: false)
    #expect(l.rightFlankWidth == 0)
    #expect(l.showsRightFillet == false)
}

@Test func aSessionCountReservesRoomForItsDigits() {
    let one = CollapsedLayout(right: .sessionCount(1), hovering: false)
    let twelve = CollapsedLayout(right: .sessionCount(12), hovering: false)
    let many = CollapsedLayout(right: .sessionCount(999), hovering: false)
    #expect(one.rightFlankWidth > 0)
    #expect(twelve.rightFlankWidth > one.rightFlankWidth)
    #expect(many.rightFlankWidth > twelve.rightFlankWidth)
    #expect(one.showsRightFillet)
}

/// A count of zero is dormant — show nothing rather than a bare "0".
@Test func aZeroCountCollapsesToNothing() {
    let l = CollapsedLayout(right: .sessionCount(0), hovering: false)
    #expect(l.rightFlankWidth == 0)
    #expect(l.showsRightFillet == false)
}

/// Design §6.1: hover widens the flanks to reveal name and elapsed time.
@Test func hoverWidensTheRightFlank() {
    let rest = CollapsedLayout(right: .sessionCount(2), hovering: false)
    let hover = CollapsedLayout(right: .sessionCount(2), hovering: true)
    #expect(hover.rightFlankWidth > rest.rightFlankWidth)
}

/// Whatever the right side does, the geometry keeps the left edge still.
@Test func noRightContentEverMovesTheLeftEdge() {
    let screen = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
        safeAreaTop: 32,
        auxLeft: CGRect(x: 0, y: 950, width: 663, height: 32),
        auxRight: CGRect(x: 848, y: 950, width: 664, height: 32))
    let g = IslandGeometry(screen: screen)
    let options: [CollapsedLayout] = [
        CollapsedLayout(right: .nothing, hovering: false),
        CollapsedLayout(right: .agentIcon, hovering: false),
        CollapsedLayout(right: .sessionCount(1), hovering: false),
        CollapsedLayout(right: .sessionCount(999), hovering: true),
    ]
    let edges = options.map {
        g.frames(rightFlank: $0.rightFlankWidth, tier: .rest).body.minX
    }
    #expect(Set(edges).count == 1)
}
