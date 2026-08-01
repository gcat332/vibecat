import SwiftUI

/// The island's silhouette.
///
/// The top corners are *concave* fillets: the island welds to the screen edge
/// rather than meeting it at a right angle, so the shape flares outward at the
/// very top. The flare lives in a `fillet`-wide margin on the left, and on the
/// right too unless `rightFilletSuppressed` drops it. The body's left edge is
/// always `rect.minX + fillet`; its right edge is `rect.maxX - fillet` when
/// the right fillet is drawn, or plain `rect.maxX` when it's suppressed.
///
/// On a rect too small to hold the fillet and bottom radius at full size,
/// both shrink together in proportion (see `path(in:)`) rather than one
/// collapsing to zero, or the fillet outrunning the radius and folding the
/// contour back on itself.
public struct IslandShape: Shape, Sendable {
    /// Dormant has no right-hand content. A weld with nothing to weld to reads
    /// as a beak poking out past the notch, so it is dropped. Design §5.5.
    public let rightFilletSuppressed: Bool

    public init(rightFilletSuppressed: Bool = false) {
        self.rightFilletSuppressed = rightFilletSuppressed
    }

    public func path(in rect: CGRect) -> Path {
        // Nominal sizes. The left side always carries a fillet; the right
        // carries one too unless suppressed.
        let f0 = IslandGeometry.fillet
        let r0 = IslandGeometry.bottomRadius
        let rightF0: CGFloat = rightFilletSuppressed ? 0 : f0

        // Two invariants keep the contour from folding back on itself:
        //   vertical:   f + r <= rect.height   (top curve must reach no lower
        //               than the bottom corner's start)
        //   horizontal: f + rightF + 2r <= rect.width   (the bottom edge
        //               between the two rounded corners can't have negative
        //               length, which also keeps the body's left edge at or
        //               left of its right edge)
        // A single shared scale keeps f and r in their nominal 9:15
        // proportion as they shrink, instead of clamping either one alone
        // and distorting the corner's shape.
        let heightBudget = f0 + r0
        let widthBudget = f0 + rightF0 + 2 * r0
        let scale = min(1, rect.height / heightBudget, rect.width / widthBudget)

        let f = f0 * scale
        let r = r0 * scale
        let rightF: CGFloat = rightFilletSuppressed ? 0 : f

        let left = rect.minX + f            // body's left edge
        let right = rect.maxX - rightF       // body's right edge
        let top = rect.minY
        let bottom = rect.maxY

        var p = Path()
        // Top-left: from the screen edge, curve down into the body's left side.
        p.move(to: CGPoint(x: rect.minX, y: top))
        p.addQuadCurve(to: CGPoint(x: left, y: top + f),
                       control: CGPoint(x: left, y: top))
        p.addLine(to: CGPoint(x: left, y: bottom - r))
        p.addQuadCurve(to: CGPoint(x: left + r, y: bottom),
                       control: CGPoint(x: left, y: bottom))
        p.addLine(to: CGPoint(x: right - r, y: bottom))
        p.addQuadCurve(to: CGPoint(x: right, y: bottom - r),
                       control: CGPoint(x: right, y: bottom))

        if rightFilletSuppressed {
            p.addLine(to: CGPoint(x: right, y: top))
        } else {
            p.addLine(to: CGPoint(x: right, y: top + f))
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: top),
                           control: CGPoint(x: right, y: top))
        }
        p.closeSubpath()   // back along the screen edge
        return p
    }
}
