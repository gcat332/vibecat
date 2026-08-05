import SwiftUI

/// The island's silhouette: straight sides hanging from the screen edge, with
/// rounded bottom corners, and — since Plan 6.3 Task 6 — a small concave weld
/// at each top corner where it meets the bezel.
///
/// On a rect too small to hold the bottom radius at full size, the radius
/// shrinks to fit rather than folding the contour back on itself.
///
/// ## The fillets: removed 2026-08-01, restored 2026-08-05
///
/// This drew concave fillets at the top from the start, on §5.5's claim that
/// "Apple's own cutout does not meet the bezel at a right angle". They were
/// removed in `b55809c` on two measurements off a running app, and **the owner
/// reversed that decision on 2026-08-05** having looked at the real thing again:
/// *"the rounded part at the top of the notch is missing — please make it meet
/// the screen with the same radius as the bottom."* The prototype has them
/// (`island-motion.html:90–101`, `--fillet: 9px` at `:31`), so this is a
/// fidelity item, not a new invention.
///
/// **The two measurements behind the removal were both real, and neither
/// survives contact with what the prototype actually draws.** Keeping them here
/// because they are the evidence, and because a comment that only records the
/// reversal would lose why the first attempt failed:
///
/// 1. *"The left edge climbed 599.5 → 605.0 over six rows while the right sat
///    dead straight at 847.5."* That is a measurement of the **old spelling**,
///    which is not the prototype's. `b55809c`'s diff is explicit: the body's own
///    left edge was `rect.minX + fillet` and the weld flared *outward from
///    inside the rect* to `rect.minX`. So the flare ate 9pt off the top of the
///    island's straight side, and the side was what moved. The prototype puts the
///    weld **outside** the element — `::before{left:-9px}`, a pseudo-element that
///    cannot affect its parent's box — so the island's own edge is untouched and
///    the weld is strictly additive ink beyond it. Here that is a subpath outside
///    `rect`, and `bothSidesAreStraightAndReachTheBoxEdges` still holds unchanged.
/// 2. *"The dormant island was visibly lopsided."* That one is about the
///    prototype's suppression rule (`.island[data-state="dormant"]::after
///    {display:none}`), and it stands. **We do not copy it**, and the reason is
///    that its premise is false for us: the prototype suppresses the right weld
///    because dormant sets `--rw: 0` (measured in the browser), so the island's
///    right edge lands exactly on the cutout's and a weld there would poke past
///    it — the mockup's own words, "a weld with nothing to weld to just pokes out
///    past the notch as a beak". Our right flank has a **floor of
///    `IslandGeometry.minimumRightFlank` (15pt)** that the prototype has no
///    equivalent of, so our right edge is never nearer the cutout than 15pt and
///    the weld always has something to weld to. Both welds are therefore always
///    drawn, both ends are identical by construction, and
///    `bothFlanksWeldToTheScreenEdgeSymmetricallyInEveryState` is the guard.
///
/// **Why 9pt and not the owner's literal "same radius as the bottom" (15/20)** is
/// in `IslandGeometry.filletRadius`.
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

    /// How far the two **top** corners weld to the screen edge —
    /// `IslandGeometry.filletRadius` (9) in production, `island-motion.html:94–100`.
    /// **`0` means no weld, and that is the default.**
    ///
    /// **Zero by default, and that is not timidity about the feature.** The welds
    /// live *outside* `rect`, so they belong only to the shape that is actually
    /// touching the bezel — the collapsed half of the silhouette. The drawer half
    /// hangs below the notch line and has no top corner to weld; `DrawerView`'s
    /// own fill/clip pair is the same; `IslandBody`'s `.contentShape` is a hit
    /// region and a 9pt sliver at the screen edge is not clickable anyway. Four
    /// call sites want none and one wants the weld, so none is the default and the
    /// one that differs says so.
    ///
    /// A plain number rather than a `Bool` reading the constant, for the reason
    /// `bottomRadius` gives for the same choice: `IslandGeometry.filletRadius` is
    /// the one place production's value is written, and the shape stays usable for
    /// a weld that is something else — which is not hypothetical, it is how
    /// `theWeldIsAHintOfACurveAndNotAScoop` measures 9 against the 15 and 20 the
    /// owner's literal reading would have given.
    ///
    /// **The `.fill` and the `.clipShape` of that half must agree.** `.clipShape`
    /// masks everything below it in the modifier chain, the fill included, so a
    /// fill with welds under a clip without them paints no welds at all — the
    /// clip erases exactly the ink this parameter adds. `theWeldSurvivesItsOwnClip`
    /// pins that pair.
    ///
    /// Deliberately **not** part of `animatableData`: `--fillet` appears in no
    /// `transition` in the prototype and is one constant across every state, so
    /// there is nothing here to interpolate. See `IslandGeometry.filletRadius`.
    public let filletRadius: CGFloat

    public init(roundsBottom: Bool = true,
                bottomRadius: CGFloat = IslandGeometry.bottomRadius,
                filletRadius: CGFloat = 0) {
        self.roundsBottom = roundsBottom
        self.bottomRadius = bottomRadius
        self.filletRadius = filletRadius
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

        addFillets(to: &p, rect: rect)
        return p
    }

    /// The two welds, as **subpaths of the same path** rather than a separate
    /// overlay view.
    ///
    /// Two reasons, one of them a rendering fact worth keeping written down:
    ///
    /// - **A single `fill` of one path has no seam.** The weld shares a 9pt edge
    ///   with the body (`x = left`, `y = top…top + f`). Two adjacent shapes drawn
    ///   by two draw calls composite twice at that edge and leave an antialiased
    ///   hairline; two subpaths of one path are one coverage calculation and
    ///   cannot.
    /// - The aura is a `.shadow` over the assembled silhouette, and §9.2's own
    ///   note says it has to trace the rendered alpha *including the fillets*
    ///   (`island-motion.html:139–142`: "a box-shadow only knows about the
    ///   rectangle, so it cut the corners and missed the notch edge"). Ink that is
    ///   part of the shape is traced for free.
    ///
    /// **A true circular arc, not the quadratic the bottom corners use.** The
    /// prototype's weld is a `radial-gradient(circle 9px …)`, i.e. exactly a
    /// quarter circle. `addArc(tangent1End:tangent2End:radius:)` is the primitive
    /// for that and needs no angle bookkeeping in a y-down space. It matters
    /// which: for a corner of side `f` the quadratic's boundary passes `0.354f`
    /// from the concave centre against the circle's `f`, so a quad weld would
    /// paint `0.833f²` where the prototype paints `0.215f²` — nearly four times
    /// the ink, which is precisely the "scoop, not a hint" the mockup's own
    /// comment warns about. Measured, not reasoned: see
    /// `theWeldIsAQuarterCircleAndNotTheQuadTheBottomCornersUse`.
    ///
    /// **`tangent1End` is the *inner* corner, not the outer one, and getting that
    /// backwards silently draws the weld inside out.** `addArc(tangent1End:
    /// tangent2End:radius:)` inscribes its circle in the corner at `tangent1End`,
    /// so naming the outer corner there centres the circle on the island's own
    /// corner and the subpath encloses the quarter *disc* — a convex bulge poking
    /// out past the bezel instead of a weld hollowing into it. It is the first
    /// thing this function was written as, and it looks plausible in source:
    /// measured, it painted **63.6pt² where a concave weld is 17.4** (πf²/4
    /// exactly, which is how it was identified). The assertion on the area is what
    /// caught it; nothing about the path's endpoints differs between the two.
    private func addFillets(to p: inout Path, rect: CGRect) {
        // Never taller than the rect it hangs off, for the same reason the bottom
        // radius clamps: a weld deeper than the shape would reach below the body's
        // own bottom edge. It never binds in production (32pt notch against 9).
        let f = min(filletRadius, rect.height)
        guard f > 0 else { return }
        let top = rect.minY

        // Left: out to the bezel along the screen edge, down the island's own
        // edge, then the concave quarter circle back up to where it started.
        p.move(to: CGPoint(x: rect.minX - f, y: top))
        p.addLine(to: CGPoint(x: rect.minX, y: top))
        p.addLine(to: CGPoint(x: rect.minX, y: top + f))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: top),
                 tangent2End: CGPoint(x: rect.minX - f, y: top), radius: f)
        p.closeSubpath()

        // Right: the mirror image, unconditionally. The prototype suppresses this
        // one while dormant and we deliberately do not — see this type's own doc
        // comment for why its premise (`--rw: 0`) has no equivalent here.
        p.move(to: CGPoint(x: rect.maxX + f, y: top))
        p.addLine(to: CGPoint(x: rect.maxX, y: top))
        p.addLine(to: CGPoint(x: rect.maxX, y: top + f))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: top),
                 tangent2End: CGPoint(x: rect.maxX + f, y: top), radius: f)
        p.closeSubpath()
    }
}
