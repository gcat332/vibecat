import Testing
import CoreGraphics
@testable import VibeCatUI

@Test func nothingOnTheRightMeansNoRightFlankAndNoFillet() {
    let l = CollapsedLayout(right: .nothing, hovering: false)
    #expect(l.rightFlankWidth == 0)
    #expect(l.showsRightFillet == false)
}

/// This is about the *shape* of the width function (more digits, more
/// width) rather than any particular font, so it pins a fixed, readable
/// metric rather than depending on the host's real font.
private let fixedMetrics = CollapsedLayout.Metrics(digitWidth: 9)

@Test func aSessionCountReservesRoomForItsDigits() {
    let one = CollapsedLayout(right: .sessionCount(1), hovering: false, metrics: fixedMetrics)
    let twelve = CollapsedLayout(right: .sessionCount(12), hovering: false, metrics: fixedMetrics)
    let many = CollapsedLayout(right: .sessionCount(999), hovering: false, metrics: fixedMetrics)
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
    let rest = CollapsedLayout(right: .sessionCount(2), hovering: false, metrics: fixedMetrics)
    let hover = CollapsedLayout(right: .sessionCount(2), hovering: true, metrics: fixedMetrics)
    #expect(hover.rightFlankWidth > rest.rightFlankWidth)
}

/// Design §5.4: "measured from actual content," not guessed — the estimate
/// must never be narrower than the padding plus the genuinely rendered text
/// width, for a range of digit counts. This pins the no-clipping invariant
/// directly, using the real measured font (`.standard`), rather than a
/// magic per-digit constant that a font or type-size change could
/// silently invalidate.
@Test func rightFlankWidthNeverClipsTheGenuinelyRenderedText() {
    let digitWidth = CollapsedLayout.Metrics.standard.digitWidth
    for n in [1, 12, 999] {
        let l = CollapsedLayout(right: .sessionCount(n), hovering: false)
        let renderedContentWidth = CGFloat(String(n).count) * digitWidth
        #expect(l.rightFlankWidth >= CollapsedLayout.padding + renderedContentWidth)
    }
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
