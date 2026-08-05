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

    /// How round the bottom corners are: `IslandGeometry.bottomRadius` (15)
    /// collapsed, `.openBottomRadius` (20) while a drawer is open. Plan 6.3 Task 5;
    /// before it this was a direct read of `IslandGeometry.bottomRadius` and the
    /// island was 15 at every tier, where `island-motion.html:162`/`:164` give the
    /// open states 20.
    ///
    /// A `var`, and the shape's `animatableData`, so a change to it **interpolates**
    /// rather than jumping. `island-motion.html:86` transitions `border-radius` over
    /// `var(--t-shape)` on `var(--ease)` — the one shape property in that rule that
    /// is not on a spring — and a `Shape` whose `animatableData` is
    /// `EmptyAnimatableData` (the default) cannot be transitioned at all, whatever
    /// animation encloses it.
    ///
    /// `IslandTier.bottomRadius` is the one place the 15-or-20 choice is made; this
    /// is a plain number so the shape stays usable for a corner that is neither
    /// (`min` below still shrinks it to fit a short or narrow rect).
    public var bottomRadius: CGFloat

    public init(roundsBottom: Bool = true,
                bottomRadius: CGFloat = IslandGeometry.bottomRadius) {
        self.roundsBottom = roundsBottom
        self.bottomRadius = bottomRadius
    }

    /// The radius, so a 15 → 20 change is interpolated by whatever `.animation`
    /// encloses the shape. `Shape`'s default is `EmptyAnimatableData`, which
    /// silently makes every radius change a hard cut — including a cut nothing in
    /// this suite could have seen, since a single frame of a hard cut and a single
    /// frame of a finished interpolation are the same picture.
    public var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    public func path(in rect: CGRect) -> Path {
        let r0 = roundsBottom ? bottomRadius : 0
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
