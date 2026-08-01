import SwiftUI

/// The island's silhouette.
///
/// The top corners are *concave* fillets: the island welds to the screen edge
/// rather than meeting it at a right angle, so the shape flares outward at the
/// very top. The flare lives in a `fillet`-wide margin on each side, which
/// means the body proper is `rect.insetBy(dx: fillet, dy: 0)`.
public struct IslandShape: Shape, Sendable {
    /// Dormant has no right-hand content. A weld with nothing to weld to reads
    /// as a beak poking out past the notch, so it is dropped. Design §5.5.
    public let rightFilletSuppressed: Bool

    public init(rightFilletSuppressed: Bool = false) {
        self.rightFilletSuppressed = rightFilletSuppressed
    }

    public func path(in rect: CGRect) -> Path {
        let f = IslandGeometry.fillet
        let r = min(IslandGeometry.bottomRadius, rect.height / 2)
        let rightF = rightFilletSuppressed ? 0 : f

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
