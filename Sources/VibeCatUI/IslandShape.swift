import SwiftUI

/// The island's silhouette: straight sides hanging from the screen edge, with
/// rounded bottom corners. The same shape the physical notch has.
///
/// This originally drew concave fillets at the top, on the design's claim that
/// "Apple's own cutout does not meet the bezel at a right angle" (§5.5). That
/// was checked against the real thing and is wrong — the flare read as a hook
/// on whichever side had it, and because the right one was suppressed when the
/// right flank was empty, the dormant island was visibly lopsided. Measured:
/// the left edge climbed 599.5 → 605.0 over six rows while the right sat dead
/// straight at 847.5. Straight sides make the two ends identical and match the
/// cutout they sit beside.
///
/// On a rect too small to hold the bottom radius at full size, the radius
/// shrinks to fit rather than folding the contour back on itself.
public struct IslandShape: Shape, Sendable {
    /// Whether to round the bottom corners at all.
    ///
    /// `true` for every caller until Plan 5, and still the default. The
    /// exception is the *collapsed* half of an open island: Plan 5 split the
    /// silhouette in two so the hover reveal could widen the collapsed part
    /// without dragging the hover-independent drawer with it, and two rounded
    /// shapes stacked would put a pair of corners across the middle of one
    /// body — a seam at the notch line, exactly where the island is supposed to
    /// read as continuous. So the top half rounds nothing while a drawer hangs
    /// below it, and the drawer's own bottom carries the radius for both.
    public let roundsBottom: Bool

    public init(roundsBottom: Bool = true) {
        self.roundsBottom = roundsBottom
    }

    public func path(in rect: CGRect) -> Path {
        let r0 = roundsBottom ? IslandGeometry.bottomRadius : 0
        // Two invariants keep the contour from folding back on itself: the two
        // corners cannot be taller than the rect, nor wider than it.
        let r = min(r0, rect.height, rect.width / 2)

        let left = rect.minX, right = rect.maxX
        let top = rect.minY, bottom = rect.maxY

        var p = Path()
        p.move(to: CGPoint(x: left, y: top))
        p.addLine(to: CGPoint(x: left, y: bottom - r))
        p.addQuadCurve(to: CGPoint(x: left + r, y: bottom),
                       control: CGPoint(x: left, y: bottom))
        p.addLine(to: CGPoint(x: right - r, y: bottom))
        p.addQuadCurve(to: CGPoint(x: right, y: bottom - r),
                       control: CGPoint(x: right, y: bottom))
        p.addLine(to: CGPoint(x: right, y: top))
        p.closeSubpath()   // back along the screen edge
        return p
    }
}
