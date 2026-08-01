import SwiftUI
import Testing
import CoreGraphics
@testable import VibeCatUI

private let box = CGRect(x: 0, y: 0, width: 300, height: 32)
private let r = IslandGeometry.bottomRadius    // 15

@Test func theShapeFillsItsBoxAtTheTopEdge() {
    let path = IslandShape().path(in: box)
    #expect(path.boundingRect.minY == 0)
    #expect(path.boundingRect.maxY == box.maxY)
    #expect(path.boundingRect.minX == 0)
    #expect(path.boundingRect.maxX == box.maxX)
}

/// The sides are straight — no flare, no inset. This is the property the
/// concave-fillet version got wrong: measured on hardware, its left edge
/// climbed 599.5 → 605.0 over six rows while the right sat dead straight at
/// 847.5, so the dormant island was visibly lopsided against the cutout.
@Test func bothSidesAreStraightAndReachTheBoxEdges() {
    let path = IslandShape().path(in: box)
    for y in stride(from: 0.5, through: 16.0, by: 1.5) {
        #expect(path.contains(CGPoint(x: 0.5, y: y)), "left edge not flush at y=\(y)")
        #expect(path.contains(CGPoint(x: box.maxX - 0.5, y: y)),
                "right edge not flush at y=\(y)")
    }
}

/// Left and right must be mirror images. A single asymmetric corner is exactly
/// what the earlier shape shipped.
///
/// Measured as the inset of the filled span on each side, per row, rather than
/// by mirroring individual sample points: `Path.contains` flattens curves, and
/// the two corners are traversed in opposite directions, so points within a
/// fraction of a point of the boundary legitimately disagree. The inset is the
/// quantity the eye actually reads.
@Test func theTwoEndsAreMirrorImages() {
    let path = IslandShape().path(in: box)
    let step = 0.05

    for y in stride(from: 0.5, through: 31.5, by: 1.0) {
        var leftInset: Double?, rightInset: Double?
        var x = box.minX
        while x <= box.maxX {
            if path.contains(CGPoint(x: x, y: y)) { leftInset = x - box.minX; break }
            x += step
        }
        x = box.maxX
        while x >= box.minX {
            if path.contains(CGPoint(x: x, y: y)) { rightInset = box.maxX - x; break }
            x -= step
        }
        let l = try! #require(leftInset), r = try! #require(rightInset)
        #expect(abs(l - r) <= 2 * step, "row \(y): left inset \(l), right inset \(r)")
    }
}

/// Square where it meets the screen edge, because the real cutout is.
@Test func theTopCornersAreSquare() {
    let path = IslandShape().path(in: box)
    #expect(path.contains(CGPoint(x: 0.5, y: 0.5)))
    #expect(path.contains(CGPoint(x: box.maxX - 0.5, y: 0.5)))
}

@Test func theBottomCornersAreRounded() {
    let path = IslandShape().path(in: box)
    #expect(!path.contains(CGPoint(x: 0.5, y: box.maxY - 0.5)))
    #expect(!path.contains(CGPoint(x: box.maxX - 0.5, y: box.maxY - 0.5)))
    #expect(path.contains(CGPoint(x: r, y: box.maxY - 1)))
    #expect(path.contains(CGPoint(x: box.maxX - r, y: box.maxY - 1)))
}

/// A drawer-height box must not distort the corners.
@Test func aTallBoxKeepsTheSameCornerRadii() {
    let tall = CGRect(x: 0, y: 0, width: 520, height: 320)
    let path = IslandShape().path(in: tall)
    #expect(path.boundingRect.height == 320)
    #expect(path.contains(CGPoint(x: tall.midX, y: tall.maxY - 1)))
    #expect(!path.contains(CGPoint(x: 0.5, y: tall.maxY - 0.5)))
    #expect(path.contains(CGPoint(x: 0.5, y: tall.maxY - r - 1)))
}

/// The radius shrinks to fit rather than folding the contour back on itself.
@Test func aShortBoxShrinksTheRadiusRatherThanFolding() {
    let short = CGRect(x: 0, y: 0, width: 300, height: 10)
    let path = IslandShape().path(in: short)
    #expect(path.boundingRect.height <= 10.001)
    #expect(path.contains(CGPoint(x: short.midX, y: 5)))
    #expect(!path.contains(CGPoint(x: 0.5, y: 9.5)))    // corner still cut
}

@Test func aNarrowBoxShrinksTheRadiusRatherThanFolding() {
    let narrow = CGRect(x: 0, y: 0, width: 20, height: 32)
    let path = IslandShape().path(in: narrow)
    #expect(path.boundingRect.width <= 20.001)
    #expect(path.contains(CGPoint(x: 10, y: 16)))
    #expect(!path.contains(CGPoint(x: 0.5, y: 31.5)))
}
