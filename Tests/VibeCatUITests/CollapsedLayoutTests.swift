import Testing
import CoreGraphics
import AppKit
@testable import VibeCatUI

@Test func nothingOnTheRightMeansNoRightFlankAndNoContent() {
    let l = CollapsedLayout(right: .nothing, hovering: false)
    #expect(l.rightFlankWidth == 0)
    #expect(l.hasRightContent == false)
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
    #expect(one.hasRightContent)
}

/// A count of zero is dormant — show nothing rather than a bare "0".
@Test func aZeroCountCollapsesToNothing() {
    let l = CollapsedLayout(right: .sessionCount(0), hovering: false)
    #expect(l.rightFlankWidth == 0)
    #expect(l.hasRightContent == false)
}

/// Design §6.1: hover widens the flanks to reveal name and elapsed time.
@Test func hoverWidensTheRightFlank() {
    let rest = CollapsedLayout(right: .sessionCount(2), hovering: false, metrics: fixedMetrics)
    let hover = CollapsedLayout(right: .sessionCount(2), hovering: true, metrics: fixedMetrics)
    #expect(hover.rightFlankWidth > rest.rightFlankWidth)
}

/// Builds the right flank's font the same way `RightFlankFont` in
/// IslandView.swift does, but independently, purely to measure a whole
/// rendered string in this test. Deliberately does not read
/// `CollapsedLayout.Metrics.standard` or multiply a single digit's width by
/// a count — either shortcut would make this test compare the
/// implementation to itself (or to an assumption of its own) instead of to
/// an independent measurement, which is the one thing the test exists to
/// avoid. See `rightFlankWidthNeverClipsTheGenuinelyRenderedText` below.
private func measuredWidth(of text: String) -> CGFloat {
    let monospaced = NSFont.monospacedDigitSystemFont(ofSize: RightFlankFont.size, weight: .semibold)
    let font = monospaced.fontDescriptor.withDesign(.rounded)
        .flatMap { NSFont(descriptor: $0, size: RightFlankFont.size) } ?? monospaced
    return (text as NSString).size(withAttributes: [.font: font]).width
}

/// Design §5.4: "measured from actual content," not guessed — the estimate
/// must never be narrower than the padding plus the genuinely rendered text
/// width, for a range of digit counts.
///
/// Measures the *whole* string here (`"12"`, not `"1"` counted twice) so
/// this also catches a tabular-spacing regression, not only a
/// too-small-constant one: per-digit multiplication only predicts the real
/// width while digits are genuinely monospaced, and a future font resolving
/// without that feature would make the two silently diverge.
@Test func rightFlankWidthNeverClipsTheGenuinelyRenderedText() {
    for n in [1, 12, 999] {
        let l = CollapsedLayout(right: .sessionCount(n), hovering: false)
        let measuredStringWidth = measuredWidth(of: String(n))
        // `>=` rather than `==` because this is a no-clipping guarantee, not
        // a width pin — but as of today it holds with exactly zero slack:
        // `l.rightFlankWidth` is built from a single digit's advance times
        // the digit count (`CollapsedLayout.Metrics.standard`), and
        // `measuredStringWidth` is the whole rendered string measured
        // independently, and the two are bit-identical because the font's
        // tabular-figure feature makes every digit genuinely the same width.
        // A one-ULP font change would flip this red for no real reason; that
        // is expected, not a sign the test is broken.
        #expect(l.rightFlankWidth >= CollapsedLayout.padding + measuredStringWidth)
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
