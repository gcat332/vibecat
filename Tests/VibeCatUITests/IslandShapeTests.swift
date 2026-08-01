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
