import CoreGraphics
import Foundation
import SwiftUI
import Testing
import VibeCatCore
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
///
/// **The fillets came back on 2026-08-05 and this test did not change, which is
/// the point.** The 2026-08-01 spelling put the weld *inside* `rect` and moved the
/// island's own edge to `rect.minX + fillet`, which is what that measurement is of;
/// the prototype's puts it outside, so the edge stays flush and this still holds
/// with `filletRadius:` set. See `IslandShape`'s doc comment and
/// `IslandFilletTests`.
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

/// Square where it meets the screen edge — of the *body*, which is what this
/// shape's own rect is. Production adds a concave weld **outside** each of these
/// two corners (`IslandShape.filletRadius`, restored 2026-08-05), and that changes
/// nothing here: the weld is ink beyond `rect`, so the corner at `rect.minX`
/// remains a right angle and both of the points below stay inside the path. The
/// welds have their own suite.
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

// MARK: - Plan 6.3 Task 5: the radius the island actually draws

/// The radius is `animatableData`, so a 15 → 20 change interpolates.
///
/// **This is compile-time protection first and a behaviour check second, and the
/// distinction matters because a weaker version of it would prove nothing.**
/// `Shape` supplies a default `animatableData` of `EmptyAnimatableData`, so a
/// version of `IslandShape` with the override deleted still *has* the property —
/// it just cannot be transitioned by any animation, and every radius change
/// becomes a hard cut. Nothing rendered can see that: one frame of a hard cut and
/// one frame of a completed interpolation are the same picture, and this suite has
/// no way to sample intermediate frames of a SwiftUI animation. What *can* be
/// pinned is the type: writing a `CGFloat` into `animatableData` does not compile
/// against `EmptyAnimatableData`, so deleting the override fails the build here.
///
/// The round-trip below is the second half — that the override is wired to the
/// radius the path reads and not to some other stored property, which is the way a
/// present-but-useless override could still be wrong.
@Test func theRadiusIsTheShapesAnimatableData() {
    var shape = IslandShape()
    #expect(shape.animatableData == IslandGeometry.bottomRadius)

    shape.animatableData = IslandGeometry.openBottomRadius
    #expect(shape.bottomRadius == IslandGeometry.openBottomRadius)

    // And the path follows it. Sampled at a point that is *inside* a 15pt corner
    // and *outside* a 20pt one, derived rather than hunted for: the quadratic
    // corner's boundary satisfies √u + √v = 1 in units of the radius (see
    // `IslandCornerRadius.measured`), so (0.25r, 0.25r) from the corner is on the
    // curve exactly — a point 0.2r in on both axes is therefore outside the shape
    // and 0.3r in is inside, at whatever radius.
    let tall = CGRect(x: 0, y: 0, width: 520, height: 320)
    let justInsideOf15 = CGPoint(x: 0.3 * 15, y: tall.maxY - 0.3 * 15)
    #expect(IslandShape().path(in: tall).contains(justInsideOf15),
            "(\(justInsideOf15)) is 0.3r in on both axes from a 15pt corner and must be inside it")
    #expect(!IslandShape(bottomRadius: 20).path(in: tall).contains(justInsideOf15),
            "the same point is only 0.225r in from a 20pt corner and must be outside it — the path is ignoring `bottomRadius`")
}

/// A rendered corner radius, recovered from the painted alpha.
///
/// **The straight side is fully opaque until exactly `bottom − r`, and that is the
/// measurement.** `IslandShape` runs its outermost column straight down from the
/// screen edge and starts the quadratic corner at `bottom − r` (`path(in:)`), so
/// the first row at which the last column of the body stops being *fully* opaque
/// names the radius with no arithmetic and no curve-fitting.
///
/// **Why not the obvious alternative.** The first version of this integrated the
/// alpha *deficit* over a corner box and inverted the quadratic corner's own area,
/// `r²/6` (the boundary is `√u + √v = 1`, so the missing area is
/// `∫₀¹(1−√u)² du = 1/6`). It works — a bare `IslandShape` at radius 15 measures
/// 15.06 and at 20 measures 20.08 — but on the real island it reads **15.43**
/// collapsed and **19.88** open, because the deficit is contaminated by
/// compositing: `IslandBody` fills the shape *and* re-clips the composite to the
/// same shape, so a boundary pixel at coverage α ends at α² and the corner loses
/// area it never lost geometrically, while an open drawer has `DrawerView`'s fill
/// unioned on top of the silhouette's and gains some back. A measurement whose
/// error changes sign with the tier is not a measurement of the tier. The opaque
/// run has neither problem: α² is still < 1, so the first non-opaque row is the
/// same row.
///
/// Scanned at scale 2, so the answer has half-point resolution, and the panel's own
/// `auraMargin` rows below the body are excluded by construction (the scan stops at
/// `bodyInPanel.maxY`).
enum IslandCornerRadius {
    /// The radius painted at the bottom-right of `body` inside `raster`, or `nil`
    /// if that column is opaque all the way down — which is itself a failure worth
    /// distinguishing from "measured 0".
    static func measured(_ raster: Raster, body: CGRect, scale: CGFloat,
                         side: Side) -> CGFloat? {
        let column = switch side {
        case .right: Int((body.maxX * scale).rounded()) - 1
        case .left:  Int((body.minX * scale).rounded())
        }
        let lastRow = Int((body.maxY * scale).rounded())
        for row in 0..<lastRow where raster[column, row].a < 255 {
            return body.maxY - CGFloat(row) / scale
        }
        return nil
    }

    enum Side { case left, right }
}

/// **The open island's bottom corner is the prototype's 20pt and the collapsed
/// one is still the measured 15** — `island-motion.html:82` against `:162`/`:164`,
/// measured off pixels rather than read off `IslandGeometry`.
///
/// Rendered through `IslandView`, not `IslandBody`, and that is the point of the
/// test rather than an incidental choice: **three shapes draw a bottom corner** —
/// the two halves of `IslandBody`'s silhouette and `DrawerView`'s own fill/clip
/// pair — they are stacked in the same ground colour, and the visible corner is the
/// *union* of their coverage, so the shallowest of them wins. Only `IslandView`
/// has all three in one tree. Measured: with `DrawerView` left at the collapsed
/// 15 while both silhouette halves carry 20, this reads **15.0** on the open
/// island; rendering `IslandBody` alone reads 20.0 and misses it entirely.
///
/// Both ends of both islands, because a single asymmetric corner is exactly what
/// this shape has shipped once before (see `theTwoEndsAreMirrorImages`).
///
/// Would fail if: the two radii were equalised in either direction — 20 collapsed
/// fails the first pair, 15 open fails the second, which is the guard on the
/// written 15pt hardware decision; if `IslandTier.bottomRadius` stopped keying on
/// `openFace`; if `DrawerView` or either silhouette half stopped taking the radius;
/// or if `IslandShape.path` ignored `bottomRadius`.
@MainActor @Test func theOpenIslandsBottomCornerIsThePrototypes20ptAndTheCollapsedOneIsStill15() throws {
    let scale: CGFloat = 2
    let geometry = IslandGeometry(screen: IslandGoldenTests.mbp14)

    @MainActor func radii(open: Bool) throws -> (left: CGFloat, right: CGFloat) {
        let m = IslandModel(geometry: geometry,
                            motion: MotionPreference(chosen: .full, systemWantsReduced: false))
        m.state = .waiting
        m.sessionCount = 0
        if open {
            m.question = QuestionModel(event: VibeEvent(
                id: "q", cli: "claude-code", kind: .permission, session: "s",
                cwd: "/tmp/proj", title: "Bash command", body: "pnpm install",
                choices: [Choice(id: "allow", label: "Allow once")], wantsReply: true))
            m.drawerOpen = true
            guard case .drawer = m.tier else {
                throw MeasurementFailure("the open fixture never reached the drawer tier — this test proves nothing")
            }
        }
        let raster = try rasterise(IslandView(model: m), scale: scale)
        let inPanel = IslandFrames(body: m.frames.body,
                                   panel: m.panelFrames.panel).bodyInPanel
        guard let l = IslandCornerRadius.measured(raster, body: inPanel, scale: scale, side: .left),
              let rr = IslandCornerRadius.measured(raster, body: inPanel, scale: scale, side: .right)
        else {
            throw MeasurementFailure("open=\(open): a side stayed fully opaque to the bottom of the body — the corner is not being rounded at all, so nothing here is a radius")
        }
        return (l, rr)
    }

    // Half a point is the resolution of a scale-2 scan, so this is as tight as the
    // measurement can be and still be about the radius rather than about rounding.
    let tolerance: CGFloat = 0.5

    let collapsed = try radii(open: false)
    #expect(abs(collapsed.right - IslandGeometry.bottomRadius) <= tolerance,
            "the collapsed island paints a \(collapsed.right)pt bottom-right corner against IslandGeometry.bottomRadius's \(IslandGeometry.bottomRadius) — that 15 matches measured hardware and its divergence from the prototype's 9px is a written decision, not something to correct")
    #expect(abs(collapsed.left - IslandGeometry.bottomRadius) <= tolerance,
            "the collapsed island paints a \(collapsed.left)pt bottom-left corner against \(IslandGeometry.bottomRadius)")

    let open = try radii(open: true)
    #expect(abs(open.right - IslandGeometry.openBottomRadius) <= tolerance,
            "the open island paints a \(open.right)pt bottom-right corner against island-motion.html:162/:164's 20px — either a shape stopped taking IslandTier.bottomRadius, or DrawerView's shallower corner is painting over the silhouette's")
    #expect(abs(open.left - IslandGeometry.openBottomRadius) <= tolerance,
            "the open island paints a \(open.left)pt bottom-left corner against 20px")

    // The difference, stated as a difference: this is what fails if a later change
    // moves both radii together, which either of the two pairs above would sail
    // through as long as each still matched its own constant.
    #expect(open.right - collapsed.right > 0,
            "the open corner (\(open.right)pt) is no rounder than the collapsed one (\(collapsed.right)pt) — the prototype's whole radius transition is that it grows")
    #expect(abs((open.right - collapsed.right) - 5) <= 2 * tolerance,
            "the rendered corners differ by \(open.right - collapsed.right)pt where the prototype's 20px against our measured 15 is 5")
}

/// Thrown when a fixture never reached the state a measurement is about, so the
/// numbers below it would be a measurement of something else.
private struct MeasurementFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// **The two radii themselves, and which tier each belongs to.**
///
/// `theOpenIslandsBottomCornerIsThePrototypes20ptAndTheCollapsedOneIsStill15`
/// compares a *render* against `IslandGeometry.bottomRadius` and
/// `.openBottomRadius`, which makes it evidence that the constants reach the
/// pixels and **not** evidence about the constants: measured, moving
/// `bottomRadius` to 20 moves the render with it and both of that test's
/// collapsed expectations stay green (its two *difference* expectations are what
/// caught the mutation). `Raster.Pixel(_:)`'s own doc comment records the general
/// version of this trap — four tests once pinned an island colour precisely and
/// locked in the wrong value rather than catching it.
///
/// So the numbers are pinned here, once, against their reasons rather than against
/// each other:
///
/// - **15 is a hardware measurement, and it is also the prototype's own number.**
///   The real cutout's corner spans about 14pt and ours has to sit *over* it rather
///   than beside it, which is why `minimumRightFlank` derives from it.
///   **Corrected 2026-08-05, Plan 6.3 Task 6:** this used to read "that is why it is
///   not the prototype's `9px`", and four documents said the same. Read in a
///   browser, `island-motion.html:83` is `border-radius:0 0 15px 15px` and the
///   dormant island computes `0px 0px 15px 15px`. There is no divergence here at
///   all; the `9px` is `--fillet` (line 31), the *top* weld, and
///   `IslandGeometry.filletRadius` is where it now lives.
/// - **20 is the prototype's, verbatim** — `island-motion.html:162` and `:164`,
///   `border-radius: 0 0 20px 20px` on `ask`, `askmulti` and `list` alike. There is
///   no cutout beside a 288pt drawer, so nothing in the argument that produced 15
///   reaches the open corner and the design's number governs.
///
/// Would fail if: either constant were retuned; if `IslandTier.bottomRadius` were
/// keyed to something other than whether a face is open (a `.hover` tier reading 20
/// fails the loop, and that is the mistake `IslandBody.revealWidth` documents having
/// been made once with a height proxy); or if a fourth tier arrived without a
/// decision about its corner.
@Test func theOpenAndCollapsedRadiiAreTheTwoPrototypeValues() {
    #expect(IslandGeometry.bottomRadius == 15,
            "the collapsed bottom radius is \(IslandGeometry.bottomRadius)pt. island-motion.html:83 is `border-radius:0 0 15px 15px` and the measured hardware corner is ~14pt, so the design and the hardware agree on 15 — this is not a divergence in either direction")
    #expect(IslandGeometry.openBottomRadius == 20,
            "the open bottom radius is \(IslandGeometry.openBottomRadius)pt against island-motion.html:162/:164's 20px")
    #expect(IslandGeometry.openBottomRadius > IslandGeometry.bottomRadius,
            "opening the island does not make its corner rounder, which is the whole of the prototype's radius transition")

    // Every tier, so "which tier is 20" is stated rather than left to the two
    // call sites in `IslandView` and `DrawerView` to imply.
    #expect(IslandTier.rest.bottomRadius == IslandGeometry.bottomRadius)
    #expect(IslandTier.hover.bottomRadius == IslandGeometry.bottomRadius,
            "hovering rounds the corner further — the prototype's 20px is set by the expanded *states* and no `:hover` selector touches it")
    for face in DrawerFace.allCases {
        #expect(IslandTier.drawer(face: face).bottomRadius == IslandGeometry.openBottomRadius,
                "the \(face) drawer draws a \(IslandTier.drawer(face: face).bottomRadius)pt corner; island-motion.html gives ask, askmulti and list the same 20px, and :166 (our questionWithReply) changes only the height")
    }
}

/// **The radius clock is installed on the silhouette and it is installed
/// *inside* the width spring's frame.** A source-shape assertion, for the reason
/// `theRevealsTwoClocksSitOnTheirOwnProperties` in `HoverMotionTests` gives: SwiftUI
/// offers no way to ask a built view which curve sits on which modifier, and this
/// repo does not take a view-inspection dependency.
///
/// **This exists because of a mutation that stayed green.** Deleting the
/// `.animation(radiusMorph, value: bottomRadius)` line alone left all 727 tests
/// passing: `radiusMorph` is a `let` in `IslandBody.body`, so
/// `IslandMotion.ease(duration:)` is still called and `easeDurationsRead` still
/// contains `--t-shape` — `theEaseSitesAreReachedByARealRender` and
/// `theFiveEaseSitesAllRouteThroughIslandMotion` both count the *request* for the
/// curve, not its installation. The only symptom was an unused-variable warning,
/// and a warning is not a test.
///
/// The ordering half is the second claim, and it is not decoration. `.animation(_:
/// value:)` governs what is below it in the chain, so this line has to sit **above**
/// the collapsed half's own `.frame(width: restingWidth + revealWidth,` and below
/// nothing else that matters: hoisted outside that frame it would take the island's
/// width off §9.1's overshooting spring and onto a bezier on every click, because
/// `restingWidth` and `bottomRadius` both change on that one gesture.
///
/// Would fail if: the `.animation` line were deleted or renamed off `radiusMorph`;
/// if it were keyed to something other than `bottomRadius`; if it were moved below
/// the collapsed half's `.frame`; or if a second copy appeared, which is how the
/// two silhouette halves would drift onto separate radius clocks.
@Test func theRadiusClockIsInstalledAndSitsInsideTheWidthSpringsFrame() throws {
    let source = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()      // VibeCatUITests
        .deletingLastPathComponent()      // Tests
        .deletingLastPathComponent()      // repo root
        .appendingPathComponent("Sources/VibeCatUI/IslandView.swift")
    // Comments in this file quote modifiers at length; only live code counts.
    let lines = try String(contentsOf: source, encoding: .utf8)
        .components(separatedBy: "\n")
        .enumerated()
        .filter { !$0.element.trimmingCharacters(in: .whitespaces).hasPrefix("//") }

    func onlyLine(containing needle: String) throws -> Int {
        let hits = lines.filter { $0.element.contains(needle) }
        try #require(hits.count == 1,
                     "expected exactly one line of code in IslandView.swift containing `\(needle)`, found \(hits.count)")
        return hits[0].offset
    }

    let declared = try onlyLine(containing: "let radiusMorph = IslandMotion.gated(")
    let installed = try onlyLine(containing: ".animation(radiusMorph, value: bottomRadius)")
    let widthFrame = try onlyLine(containing: ".frame(width: restingWidth + revealWidth,")

    #expect(declared < installed,
            "the radius animation is used at line \(installed + 1) before it is declared at \(declared + 1), which cannot compile — this test's premise no longer holds")
    #expect(installed < widthFrame,
            "the radius clock (line \(installed + 1)) sits below the silhouette's own `.frame` (line \(widthFrame + 1)), so it governs the island's width too — every click would take its width off §9.1's overshooting spring and onto a bezier")
}
