import SwiftUI
import Testing
import CoreGraphics
@testable import VibeCatUI

private let box = CGRect(x: 0, y: 0, width: 300, height: 32)
private let f = IslandGeometry.fillet          // 9
private let r = IslandGeometry.bottomRadius    // 15

@Test func theShapeFillsItsBoxAtTheTopEdge() {
    let path = IslandShape(rightFilletSuppressed: false).path(in: box)
    #expect(path.boundingRect.minY == 0)
    #expect(path.boundingRect.maxY == box.maxY)
}

/// The flare is a thin wedge that widens as it approaches the screen edge.
/// At x = 8 the boundary curve sits at y = 4, so the wedge is 4pt deep there.
@Test func theFlareFillsTheWedgeBetweenTheScreenEdgeAndTheBody() {
    let path = IslandShape(rightFilletSuppressed: false).path(in: box)
    #expect(path.contains(CGPoint(x: 8, y: 2)))     // inside the wedge
    #expect(!path.contains(CGPoint(x: 8, y: 6)))    // below it, and left of the body
}

/// The body proper is inset by the fillet on each side.
@Test func theBodyIsInsetByTheFilletBelowTheFlare() {
    let path = IslandShape(rightFilletSuppressed: false).path(in: box)
    let mid = box.height / 2
    #expect(path.contains(CGPoint(x: f + 1, y: mid)))
    #expect(path.contains(CGPoint(x: box.maxX - f - 1, y: mid)))
    #expect(!path.contains(CGPoint(x: f - 3, y: mid)))
    #expect(!path.contains(CGPoint(x: box.maxX - f + 3, y: mid)))
}

/// Design §5.5: dormant has no right-hand content, so the weld has nothing to
/// weld to and would poke out past the notch as a beak. Suppressed, the right
/// edge runs straight to the box edge instead of insetting for a flare.
@Test func theRightFilletIsSuppressedWhenAsked() {
    let mid = box.height / 2
    let flared = IslandShape(rightFilletSuppressed: false).path(in: box)
    let plain = IslandShape(rightFilletSuppressed: true).path(in: box)

    #expect(!flared.contains(CGPoint(x: box.maxX - 1, y: mid)))  // inset for the flare
    #expect(plain.contains(CGPoint(x: box.maxX - 1, y: mid)))    // runs to the edge
    #expect(plain.contains(CGPoint(x: f + 1, y: mid)))           // left side unchanged
    #expect(plain.contains(CGPoint(x: 8, y: 2)))                 // left flare still there
}

/// The fillet is concave: the corner is cut away, not filled.
@Test func theTopCornerIsConcaveNotSquare() {
    let path = IslandShape(rightFilletSuppressed: false).path(in: box)
    // A square corner would make this point solid. The curve reaches only
    // y = 0.007 at x = 0.5, so a concave fillet leaves it empty.
    #expect(!path.contains(CGPoint(x: 0.5, y: f - 0.5)))
}

@Test func theBottomCornersAreRounded() {
    let path = IslandShape(rightFilletSuppressed: false).path(in: box)
    #expect(!path.contains(CGPoint(x: f + 0.5, y: box.maxY - 0.5)))
    #expect(path.contains(CGPoint(x: f + r, y: box.maxY - 1)))
}

/// A drawer-height box must not distort the corners.
@Test func aTallBoxKeepsTheSameCornerRadii() {
    let tall = CGRect(x: 0, y: 0, width: 520, height: 320)
    let path = IslandShape(rightFilletSuppressed: false).path(in: tall)
    #expect(path.boundingRect.height == 320)
    #expect(path.contains(CGPoint(x: tall.midX, y: tall.maxY - 1)))
    #expect(!path.contains(CGPoint(x: f + 0.5, y: tall.maxY - 0.5)))
}

/// Below `fillet + bottomRadius` (24pt) of height, the top curve (ending at
/// `y = fillet`) would reach lower than the bottom corner's start
/// (`y = height - bottomRadius`), so the left edge's connecting line would
/// run backward and the contour would fold on itself. `IslandShape` scales
/// `fillet` and `bottomRadius` down together to keep `fillet + bottomRadius
/// <= height`; at height 12 the shared scale is 0.5, so `fillet` becomes 4.5
/// and the body's left edge sits at x = 4.5 rather than the nominal x = 9.
@Test func aVeryShortRectScalesTheFilletAndTheRadiusTogether() {
    let short = CGRect(x: 0, y: 0, width: 300, height: 12)
    let path = IslandShape(rightFilletSuppressed: false).path(in: short)

    // x = 6 sits strictly between the scaled left edge (4.5) and the nominal,
    // unscaled one (9). If fillet weren't clamped here, the body wouldn't
    // start until x = 9 and this point would read as outside.
    #expect(path.contains(CGPoint(x: 6, y: 6)))
    // The top corner is still concave, not squared off by the clamp.
    #expect(!path.contains(CGPoint(x: 0.5, y: 4.0)))
    // The bottom corner is still rounded, at the smaller, scaled radius.
    #expect(!path.contains(CGPoint(x: 5, y: short.maxY - 0.5)))
    #expect(path.contains(CGPoint(x: 12, y: short.maxY - 1)))
}

/// A height inside `[18, 30)` is the band where the two corners' *unscaled*
/// budgets disagree — a naive clamp that shrinks `bottomRadius` to
/// `height / 2` while leaving `fillet` untouched (as this file's history
/// once did) still overshoots down to height 18, not 24. Scaling both
/// together avoids the discrepancy entirely: at height 20 the shared scale
/// is 20/24, so `fillet` is 7.5 (not the nominal 9) and `bottomRadius` is
/// 12.5 (not the nominal 15).
@Test func aMidRangeHeightScalesTheFilletAsWellAsTheRadius() {
    let mid = CGRect(x: 0, y: 0, width: 300, height: 20)
    let path = IslandShape(rightFilletSuppressed: false).path(in: mid)

    // x = 8 is strictly between the scaled left edge (7.5) and the nominal
    // one (9) — only reachable once fillet itself is scaled down too.
    #expect(path.contains(CGPoint(x: 8, y: 6)))
    #expect(!path.contains(CGPoint(x: 0.5, y: 7.0)))
    #expect(!path.contains(CGPoint(x: 8, y: mid.maxY - 0.5)))
    #expect(path.contains(CGPoint(x: 20, y: mid.maxY - 1)))
}

/// The same budget applies horizontally: `fillet + rightFillet + 2 *
/// bottomRadius <= width`, since the bottom edge runs between the two
/// rounded corners and can't have negative length. At width 20 (height 32,
/// unsuppressed, so `widthBudget = 9 + 9 + 30 = 48`) the shared scale is
/// 20/48, giving `fillet` = 3.75 and `bottomRadius` = 6.25.
@Test func aNarrowRectScalesForTheWidthBudgetToo() {
    let narrow = CGRect(x: 0, y: 0, width: 20, height: 32)
    let path = IslandShape(rightFilletSuppressed: false).path(in: narrow)

    // x = 5 sits strictly right of the scaled left edge (3.75) and left of
    // the nominal, unscaled one (9) — inside only once fillet is scaled.
    #expect(path.contains(CGPoint(x: 5, y: 16)))
    // Near the bottom-left corner, close to the box's left and bottom edges:
    // outside the (now much smaller) rounded corner, and unreachable at all
    // by an implementation that only clamps height and ignores width.
    #expect(!path.contains(CGPoint(x: 2, y: 31.5)))
}
