import Testing
import CoreGraphics
import AppKit
@testable import VibeCatUI

/// An empty right flank is the corner minimum wide and holds nothing.
///
/// Not zero: at zero the island's right edge lands exactly on `notch.maxX` and
/// its bottom-right corner is drawn into the same fifteen points as the
/// hardware's, which left a visible seam on a real screen. See
/// `IslandGeometry.minimumRightFlank`. Width and content are separate
/// questions now, which is the whole point of the split.
@Test func anEmptyRightFlankIsTheCornerMinimumAndHoldsNothing() {
    let l = CollapsedLayout(right: .nothing, hovering: false)
    #expect(l.rightFlankWidth == IslandGeometry.minimumRightFlank)
    #expect(l.hasRightContent == false)
}

/// The floor is exactly one corner radius, and that is not decoration: below
/// it the hardware's corner curve is exposed again, because our own curve
/// spans `bottomRadius` and has to start at or beyond `notch.maxX`.
@Test func theCornerMinimumIsOneCornerRadius() {
    #expect(IslandGeometry.minimumRightFlank == IslandGeometry.bottomRadius)
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

/// A count of zero is dormant — show nothing rather than a bare "0". It is
/// indistinguishable from `.nothing`, corner minimum included.
@Test func aZeroCountCollapsesToNothing() {
    let l = CollapsedLayout(right: .sessionCount(0), hovering: false)
    #expect(l.rightFlankWidth == IslandGeometry.minimumRightFlank)
    #expect(l.hasRightContent == false)
}

/// Design §6.1: hover widens the flanks to reveal name and elapsed time.
@Test func hoverWidensTheRightFlank() {
    let rest = CollapsedLayout(right: .sessionCount(2), hovering: false, metrics: fixedMetrics)
    let hover = CollapsedLayout(right: .sessionCount(2), hovering: true, metrics: fixedMetrics)
    #expect(hover.rightFlankWidth > rest.rightFlankWidth)
}

/// Measured on the running app: hover was a guaranteed no-op while dormant,
/// because rightFlankWidth returned before it looked at `hovering`.
@Test func hoveringOpensTheRevealEvenWithNoRightContent() {
    let rest = CollapsedLayout(right: .nothing, hovering: false)
    let hovered = CollapsedLayout(right: .nothing, hovering: true)
    #expect(rest.rightFlankWidth == IslandGeometry.minimumRightFlank)
    #expect(hovered.rightFlankWidth
            == IslandGeometry.minimumRightFlank + CollapsedLayout.hoverReveal)
}

@Test func hoveringStillAddsTheRevealOnTopOfRealContent() {
    let rest = CollapsedLayout(right: .sessionCount(2), hovering: false)
    let hovered = CollapsedLayout(right: .sessionCount(2), hovering: true)
    #expect(hovered.rightFlankWidth == rest.rightFlankWidth + CollapsedLayout.hoverReveal)
}

@Test func aZeroCountStillShowsNothingAtRest() {
    let l = CollapsedLayout(right: .sessionCount(0), hovering: false)
    #expect(l.rightFlankWidth == IslandGeometry.minimumRightFlank)
    #expect(l.sessionCountText == nil)
}

/// Design §9.1: the hover reveal (`280ms`, `easeOut`) must be a distinct
/// animation from the width spring, not the same curve wearing two hats.
/// `IslandBody` achieves that by splitting the body's width into a resting
/// half (springs) and the reveal's own contribution (eases) and animating
/// each independently — which only works if hover's contribution is a
/// constant, content-independent `+150`. If a later change made the reveal
/// scale with (or vanish for) some particular content, the split could no
/// longer be pulled apart like this, and the two animations would collapse
/// back into one.
@Test func theHoverRevealIsAConstantAdditionRegardlessOfContent() {
    let contents: [CollapsedLayout.RightContent] = [
        .nothing, .agentIcon, .sessionCount(0), .sessionCount(1),
        .sessionCount(42), .sessionCount(999),
    ]
    for right in contents {
        let rest = CollapsedLayout(right: right, hovering: false)
        let hovered = CollapsedLayout(right: right, hovering: true)
        #expect(hovered.rightFlankWidth - rest.rightFlankWidth == CollapsedLayout.hoverReveal,
                "hover's contribution should be exactly hoverReveal for \(right), independent of content")
    }
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

/// Fix round 2: `sessionCountText` is the one place a count is clamped for
/// display — `IslandView` reads it instead of formatting `n` itself, so it
/// can never render more digits than `rightFlankWidth` reserved room for.
@Test func sessionCountTextIsNilWhenThereIsNothingToDraw() {
    #expect(CollapsedLayout(right: .nothing, hovering: false).sessionCountText == nil)
    #expect(CollapsedLayout(right: .agentIcon, hovering: false).sessionCountText == nil)
    #expect(CollapsedLayout(right: .sessionCount(0), hovering: false).sessionCountText == nil)
}

@Test func sessionCountTextIsThePlainDigitsWithinTheLimit() {
    let l = CollapsedLayout(right: .sessionCount(42), hovering: false)
    #expect(l.sessionCountText == "42")
}

/// The regression this fix round exists for: a count of 1234 used to render
/// as `"1234"` — four glyphs in a three-digit-wide reservation — clipping
/// against the silhouette. Clamped, it must render as exactly
/// `maxDisplayedSessions`, not merely "some 3-character string".
@Test func sessionCountTextClampsBeyondTheDisplayLimit() {
    for n in [1_000, 999_999, Int.max] {
        let l = CollapsedLayout(right: .sessionCount(n), hovering: false)
        #expect(l.sessionCountText == String(CollapsedLayout.maxDisplayedSessions),
                "sessionCount(\(n)) should render as the clamp, not \(n)'s own digits")
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
