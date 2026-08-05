import CoreGraphics
import Foundation
import SwiftUI
import Testing
import VibeCatCore
@testable import VibeCatUI

/// **The concave welds where the island meets the bezel** — `--fillet: 9px`,
/// `island-motion.html:31` and `:94–100`. Removed on 2026-08-01, restored on
/// 2026-08-05 by the owner; `IslandShape`'s own doc comment carries that history
/// and why neither reason for the removal survives the prototype's spelling.
///
/// Everything here is measured off pixels. The welds are the one part of the
/// silhouette that is drawn *outside* the shape's own rect, which makes them
/// exactly the kind of thing a property read cannot see: `IslandShape.path(in:)`
/// returns them whether or not any enclosing clip lets them survive to the
/// screen, and `theWeldSurvivesItsOwnClip` below is that trap demonstrated
/// rather than described.
@Suite("Island fillets")
struct IslandFilletTests {
    /// One `IslandShape` alone on a transparent stage wide enough to hold its
    /// welds, filled white so the alpha channel *is* the coverage.
    ///
    /// White, and premultiplied: `rasterise` renders into
    /// `premultipliedLast`, so a coverage-α pixel of white reads
    /// `(255α, 255α, 255α, 255α)` and the alpha channel alone gives α. That is
    /// what makes an area integral legitimate here where
    /// `IslandCornerRadius.measured`'s own doc comment rejects one for the
    /// *bottom* corner: there the fill is re-clipped to the same shape, so a
    /// boundary pixel ends at α² and the corner loses area it never lost
    /// geometrically. There is exactly one fill and no clip in this stage.
    @MainActor
    static func stage(fillet: CGFloat, width: CGFloat = 200, height: CGFloat = 32,
                      bottomRadius: CGFloat = IslandGeometry.bottomRadius,
                      pad: CGFloat = 30, scale: CGFloat = 4) throws -> Measured {
        let view = ZStack(alignment: .topLeading) {
            // A stage the welds cannot outgrow. `.frame` affects layout where
            // `.offset` does not, so the shape can hang ink into the padding
            // without changing the raster's size.
            Color.clear.frame(width: width + 2 * pad, height: height)
            IslandShape(bottomRadius: bottomRadius, filletRadius: fillet)
                .fill(Color.white)
                .frame(width: width, height: height)
                .offset(x: pad)
        }
        return Measured(raster: try rasterise(view, scale: scale), pad: pad,
                        width: width, height: height, scale: scale)
    }

    /// The measurements a rendered weld can actually answer.
    struct Measured {
        let raster: Raster
        let pad: CGFloat, width: CGFloat, height: CGFloat, scale: CGFloat

        private var bodyFirstColumn: Int { Int((pad * scale).rounded()) }
        private var bodyLastColumn: Int { Int(((pad + width) * scale).rounded()) - 1 }

        /// Ink strictly outside the body's own columns, on the named side, in
        /// square points. A weld of radius `f` drawn as a quarter circle is
        /// `f²(1 − π/4)`; drawn as the quadratic the bottom corners use it is
        /// `5f²/6`, nearly four times as much.
        func weldArea(_ side: Side) -> Double {
            let columns = switch side {
            case .left:  0..<bodyFirstColumn
            case .right: (bodyLastColumn + 1)..<raster.width
            }
            var sum = 0.0
            for x in columns where x >= 0 && x < raster.width {
                for y in 0..<raster.height { sum += Double(raster[x, y].a) / 255 }
            }
            return sum / Double(scale * scale)
        }

        /// How far past the body's own edge the weld reaches, in points: the
        /// outermost column holding any ink at all.
        func weldReach(_ side: Side) -> CGFloat {
            switch side {
            case .left:
                for x in 0..<bodyFirstColumn where columnHasInk(x) {
                    return (CGFloat(bodyFirstColumn - x)) / scale
                }
            case .right:
                for x in stride(from: raster.width - 1, through: bodyLastColumn + 1, by: -1)
                where columnHasInk(x) {
                    return (CGFloat(x - bodyLastColumn)) / scale
                }
            }
            return 0
        }

        /// How many rows deep the weld goes: rows in which the body's own
        /// outermost column is not the leftmost (or rightmost) ink in the row.
        func weldDepth(_ side: Side) -> CGFloat {
            var rows = 0
            for y in 0..<raster.height where outerInk(side, row: y) != nil {
                let edge = switch side {
                case .left:  bodyFirstColumn
                case .right: bodyLastColumn
                }
                let ink = outerInk(side, row: y)!
                if side == .left ? ink < edge : ink > edge { rows += 1 }
            }
            return CGFloat(rows) / scale
        }

        /// **The flush edge: how many points of the island's own side are drawn
        /// dead straight, welded at neither end.** Rows whose outermost ink *is*
        /// the body's own outermost column, to the device pixel.
        ///
        /// This is the number the 9-against-15-against-20 decision turns on, and
        /// it is a rendered quantity rather than `height − fillet − radius`
        /// arithmetic: at a fillet of 20 against a bottom radius of 15 on a 32pt
        /// bar the two curves overlap, and the arithmetic would report −3pt of
        /// side where what is drawn is one continuous S.
        ///
        /// **It reads ~3.7pt longer than the arithmetic, and that is antialiasing
        /// rather than an error.** Both curves leave the straight edge
        /// *tangentially*, so their inset grows as `v²/2r`: over the last ~2.1pt
        /// of the weld and the first ~1.6pt of the bottom corner the inset is
        /// under one device pixel at scale 4 and the row's outermost ink is still
        /// the edge column. Measured 11.75pt against an arithmetic 8 at a 9pt
        /// fillet. The offset is the same at every radius, which is why the three
        /// values are compared **with each other** and never against a computed
        /// figure.
        func straightSide(_ side: Side) -> CGFloat {
            let edge = switch side {
            case .left:  bodyFirstColumn
            case .right: bodyLastColumn
            }
            var rows = 0
            for y in 0..<raster.height where outerInk(side, row: y) == edge { rows += 1 }
            return CGFloat(rows) / scale
        }

        /// The outermost column holding ink in `row`, on `side`.
        func outerInk(_ side: Side, row y: Int) -> Int? {
            switch side {
            case .left:
                for x in 0..<raster.width where raster[x, y].a > 0 { return x }
            case .right:
                for x in stride(from: raster.width - 1, through: 0, by: -1)
                where raster[x, y].a > 0 { return x }
            }
            return nil
        }

        private func columnHasInk(_ x: Int) -> Bool {
            (0..<raster.height).contains { raster[x, $0].a > 0 }
        }

        enum Side { case left, right }
    }

    // MARK: - The radius

    /// **9pt is a hint of a curve; 15 and 20 are the scoop the mockup's own
    /// comment warns about.** The owner's instruction was "the same radius as the
    /// bottom", which is 15 collapsed and 20 open; the prototype says 9. Six
    /// points apart, so it was measured rather than chosen.
    ///
    /// The collapsed bar is only `notch.height` = 32pt tall, and that is the whole
    /// argument: **the straight side that is left between the weld and the bottom
    /// corner.** At 9 the island keeps a real vertical edge; at 15 it keeps 2pt of
    /// one; at 20 the weld and the bottom corner meet and each end of the island
    /// becomes a single continuous S from bezel to bottom, which is not a rounded
    /// corner but the hook the 2026-08-01 removal was reacting to.
    ///
    /// Would fail if: `IslandGeometry.filletRadius` were retuned to either of the
    /// owner's literal readings (both are asserted against directly, so the test
    /// says *which* value was chosen and not merely that some value renders); if
    /// the weld stopped being drawn (0pt reach); or if the bar's own height
    /// changed enough to alter the trade-off, which is the case this is really
    /// guarding — the numbers below are only true for a 32pt bar.
    @MainActor @Test func theWeldIsAHintOfACurveAndNotAScoop() throws {
        let bar: CGFloat = 32          // `IslandGeometry` reads this off NSScreen; mbp14 is 32
        var rows: [(f: CGFloat, ink: Double, depth: CGFloat, flush: CGFloat)] = []
        for f in [IslandGeometry.filletRadius, IslandGeometry.bottomRadius,
                  IslandGeometry.openBottomRadius] {
            let m = try Self.stage(fillet: f, height: bar)
            rows.append((f, m.weldArea(.left), m.weldDepth(.left), m.straightSide(.left)))
        }
        print("""

          FILLET RADIUS — measured off a scale-4 render of a \(Int(bar))pt bar
          fillet   weld ink   spans of bar   flush edge left
        """)
        for r in rows {
            print(String(format: "  %5.0fpt   %6.2fpt²      %5.1f%%         %5.2fpt",
                         r.f, r.ink, Double(r.depth / bar * 100), r.flush))
        }

        let hint = rows[0], atBottom = rows[1], atOpen = rows[2]
        #expect(hint.f == 9, "the production fillet is \(hint.f)pt, not the prototype's --fillet: 9px")
        // Each weld spans exactly its own radius, which is what makes the three
        // rows above comparable at all.
        for r in rows {
            #expect(abs(r.depth - r.f) <= 0.5,
                    "a \(r.f)pt fillet spans \(r.depth)pt of the bar, so this row is not measuring the radius it claims to")
        }
        #expect(hint.flush >= 10,
                "at a \(hint.f)pt fillet the island keeps only \(hint.flush)pt of flush edge on a \(Int(bar))pt bar — the weld and the bottom corner have eaten the side between them")
        #expect(atBottom.flush <= 7,
                "a \(atBottom.f)pt fillet — the owner's literal 'same radius as the bottom', collapsed — left \(atBottom.flush)pt of flush edge where the recorded decision measured 5.75; re-derive the trade-off rather than trusting the table")
        #expect(atOpen.flush <= 1,
                "a \(atOpen.f)pt fillet left \(atOpen.flush)pt of flush edge; the recorded decision is that the weld and a 15pt bottom corner meet on a \(Int(bar))pt bar and leave the island no side at all")
        #expect(hint.flush > atBottom.flush * 2,
                "the \(hint.f)pt weld leaves \(hint.flush)pt of flush edge against the \(atBottom.f)pt weld's \(atBottom.flush)pt — if those are comparable, the argument that picked 9 over the owner's literal reading does not hold")
        #expect(atOpen.ink > hint.ink * 4,
                "a \(atOpen.f)pt weld paints \(atOpen.ink)pt² against \(hint.f)pt's \(hint.ink)pt² — the 'hint of a curve, not a scoop' distinction is an ink ratio and it has collapsed")
    }

    /// **The weld is a quarter circle, matching the prototype's
    /// `radial-gradient(circle 9px …)`, and not the quadratic the bottom corners
    /// are drawn with.**
    ///
    /// The distinction is four-fold in ink, not cosmetic. For a corner box of side
    /// `f`, a circular weld removes the quarter disc (`πf²/4`) and paints
    /// `f²(1 − π/4) = 0.2146f²`; the quadratic `IslandShape` uses for its bottom
    /// corners passes only `0.354f` from the concave centre and removes `f²/6`,
    /// painting `0.833f²`. At f = 9 that is 17.4pt² against 67.5pt² — so a weld
    /// drawn with the file's own existing corner primitive would be the scoop the
    /// mockup warns about even at the prototype's own radius.
    ///
    /// Would fail if: `addFillets` were rewritten with `addQuadCurve` "for
    /// consistency with the bottom corners" (67.5pt², nowhere near); if the arc
    /// were inverted into a convex bulge (`f²(1 + …)`, larger still); or if the
    /// tangent points were wrong, which shows up as an area between the two.
    @MainActor @Test func theWeldIsAQuarterCircleAndNotTheQuadTheBottomCornersUse() throws {
        let f = IslandGeometry.filletRadius
        let m = try Self.stage(fillet: f, scale: 8)
        let circular = Double(f * f) * (1 - Double.pi / 4)
        let quadratic = Double(f * f) * 5 / 6
        for side in [Measured.Side.left, .right] {
            let area = m.weldArea(side)
            #expect(abs(area - circular) < 0.6,
                    "the \(side) weld paints \(area)pt² against a quarter circle's \(circular)pt² (a quadratic corner would be \(quadratic)pt²)")
        }
        // Within half a point, and the shortfall is a known sub-pixel fact rather
        // than slop widened until it passed: the arc leaves the bezel with a
        // *horizontal* tangent, so its outermost quarter-point of reach is a sliver
        // of coverage 0.46% — alpha 1.2 of 255, which rounds away. Measured 8.75 of
        // 9.0 at scale 4, and 8.75 again at scale 8, so it does not converge.
        for side in [Measured.Side.left, .right] {
            #expect(abs(m.weldReach(side) - f) <= 0.5,
                    "the \(side) weld reaches \(m.weldReach(side))pt past the body's edge, not the \(f)pt of --fillet")
        }
    }

    /// **The trap the fill/clip pair sets, demonstrated.**
    ///
    /// `IslandBody` fills the silhouette *and* re-clips the composite to the same
    /// shape (so a row's rounded background cannot paint square into a rounded
    /// corner). `.clipShape` masks everything below it in the chain, the fill
    /// included — so a fill that carries the welds under a clip that does not
    /// paints **no welds at all**, and nothing about the fill looks wrong.
    ///
    /// This is the mutation as a test rather than as a source scan: it constructs
    /// the mismatched pair and measures 0.
    @MainActor @Test func theWeldSurvivesItsOwnClip() throws {
        let f = IslandGeometry.filletRadius
        let pad: CGFloat = 30, scale: CGFloat = 4

        @MainActor func weldInk(clipFillet: CGFloat) throws -> Double {
            let view = ZStack(alignment: .topLeading) {
                Color.clear.frame(width: 200 + 2 * pad, height: 32)
                IslandShape(filletRadius: f)
                    .fill(Color.white)
                    .clipShape(IslandShape(filletRadius: clipFillet))
                    .frame(width: 200, height: 32)
                    .offset(x: pad)
            }
            let m = Measured(raster: try rasterise(view, scale: scale), pad: pad,
                             width: 200, height: 32, scale: scale)
            return m.weldArea(.left) + m.weldArea(.right)
        }

        #expect(try weldInk(clipFillet: f) > 30,
                "a fill and clip that agree still painted no weld — the rest of this test proves nothing")
        #expect(try weldInk(clipFillet: 0) == 0,
                "a clip without the fillet left weld ink on screen, so the two do not have to agree and IslandBody's pairing is not load-bearing after all")
    }

    // MARK: - Symmetry, which is the whole guard

    /// **Both flanks weld identically, in every state.** This is the assertion the
    /// 2026-08-01 removal was owed and did not have.
    ///
    /// The prototype suppresses its right weld while dormant
    /// (`.island[data-state="dormant"]::after{display:none}`) and accepts the
    /// asymmetry; measured on real hardware, that read as lopsided, and it is half
    /// the reason the welds were deleted. **We suppress neither**, which is
    /// defensible only because our right flank has a 15pt floor
    /// (`IslandGeometry.minimumRightFlank`) that the prototype has no equivalent
    /// of — so the weld always has island to weld to. See `IslandShape`'s doc
    /// comment.
    ///
    /// Measured per row, as the *reach past the body's own edge on each side*, and
    /// compared left against right. Per row rather than as a total, because two
    /// welds of equal area and different shape would pass a total; and as a reach
    /// past the body edge rather than as an absolute column, because the body is
    /// not centred in the panel.
    ///
    /// **The presence half is not decoration.** Zero weld on both sides is
    /// perfectly symmetric, so a test that only compared the two would sail
    /// through the welds never being drawn at all — which is exactly the state
    /// this branch started in, and exactly what `theWeldSurvivesItsOwnClip`'s
    /// mismatched clip produces. So each side's reach is also pinned to
    /// `filletRadius`.
    ///
    /// Would fail if: either weld were suppressed in any state (the prototype's
    /// own dormant rule, copied); if the two took different radii; if a clip
    /// anywhere in `IslandView` stopped carrying the fillet; or if the welds were
    /// drawn on the drawer half as well, which would put a pair of them at the
    /// notch line where the island is meant to read as continuous.
    @MainActor @Test func bothFlanksWeldToTheScreenEdgeSymmetricallyInEveryState() throws {
        let f = IslandGeometry.filletRadius
        let scale: CGFloat = 4

        struct Case { let name: String; let state: IslandState; let count: Int
                      let hovering: Bool; let open: Bool }
        let cases = [
            // Dormant with no count is the narrowest island there is, and the one
            // the prototype leaves lopsided.
            Case(name: "dormant, empty flank", state: .dormant, count: 0, hovering: false, open: false),
            Case(name: "dormant, hovered", state: .dormant, count: 0, hovering: true, open: false),
            Case(name: "waiting, 3 sessions", state: .waiting, count: 3, hovering: false, open: false),
            Case(name: "waiting, 3, hovered", state: .waiting, count: 3, hovering: true, open: false),
            Case(name: "drawer open", state: .waiting, count: 3, hovering: true, open: true),
        ]

        for c in cases {
            let m = IslandGoldenTests.model(c.state, count: c.count, hovering: c.hovering)
            if c.open {
                m.sessions = [Session(event: VibeEvent(id: "e", cli: "claude-code", kind: .running,
                                                       session: "s", cwd: "/Users/dev/api"),
                                      now: Date(timeIntervalSince1970: 1_000_000))]
                m.drawerOpen = true
                guard case .drawer = m.tier else {
                    Issue.record("\(c.name): the fixture never reached the drawer tier")
                    continue
                }
            }
            let raster = try rasterise(IslandView(model: m), scale: scale)
            let inPanel = IslandFrames(body: m.frames.body,
                                       panel: m.panelFrames.panel).bodyInPanel
            let left = Int((inPanel.minX * scale).rounded())
            let right = Int((inPanel.maxX * scale).rounded()) - 1

            // Per row, over the weld's own depth plus a row either side of it.
            let rows = Int(((f + 2) * scale).rounded())
            var mismatches: [String] = []
            var deepestLeft = 0, deepestRight = 0
            for y in 0..<min(rows, raster.height) {
                var l = -1, r = -1
                for x in 0..<raster.width where raster[x, y].a > 0 { l = x; break }
                for x in stride(from: raster.width - 1, through: 0, by: -1)
                where raster[x, y].a > 0 { r = x; break }
                guard l >= 0, r >= 0 else { continue }
                let outLeft = left - l, outRight = r - right
                deepestLeft = max(deepestLeft, outLeft)
                deepestRight = max(deepestRight, outRight)
                if outLeft != outRight {
                    mismatches.append("row \(Double(y) / Double(scale)): left +\(Double(outLeft) / Double(scale))pt, right +\(Double(outRight) / Double(scale))pt")
                }
            }
            #expect(mismatches.isEmpty,
                    "\(c.name): the two ends weld differently — \(mismatches.prefix(4).joined(separator: "; "))")
            #expect(abs(CGFloat(deepestLeft) / scale - f) <= 0.5,
                    "\(c.name): the left weld reaches \(CGFloat(deepestLeft) / scale)pt past the body, not --fillet's \(f)pt — a symmetric absence is still symmetric, which is why this half exists")
            #expect(abs(CGFloat(deepestRight) / scale - f) <= 0.5,
                    "\(c.name): the right weld reaches \(CGFloat(deepestRight) / scale)pt past the body, not \(f)pt")
        }
    }

    /// **§5.1: the weld sits over the bezel, never over the cutout.** Task 5 had
    /// to add `minimumOpenWidth` because a 20pt bottom corner against a 15pt flank
    /// floor put 5pt of curve back inside the hole; a weld is ink outside the
    /// island's own edges and owes the same check.
    ///
    /// It passes structurally — the right weld starts at `body.maxX`, which
    /// `minimumRightFlank` keeps at least 15pt clear of `notch.maxX` — and the
    /// point of measuring it anyway is that the structural argument is exactly the
    /// one Task 5 found already broken once. The narrowest island there is
    /// (dormant, no count, not hovered) is the case that binds.
    @MainActor @Test func theWeldsStayOutsideTheCutout() throws {
        let scale: CGFloat = 4
        let m = IslandGoldenTests.model(.dormant, count: 0)
        let raster = try rasterise(IslandView(model: m), scale: scale)
        let notch = m.geometry.notch
        let panel = m.panelFrames.panel
        let body = IslandFrames(body: m.frames.body, panel: panel).bodyInPanel
        let cutout = (from: Int(((notch.minX - panel.minX) * scale).rounded()),
                      to: Int(((notch.maxX - panel.minX) * scale).rounded()))

        // The weld's own columns: everything painted outside the body's span.
        var weldColumns: [Int] = []
        for x in 0..<raster.width where (0..<raster.height).contains(where: { raster[x, $0].a > 0 }) {
            if x < Int((body.minX * scale).rounded()) || x >= Int((body.maxX * scale).rounded()) {
                weldColumns.append(x)
            }
        }
        #expect(!weldColumns.isEmpty, "nothing is painted outside the body at all — there is no weld here to check")
        let inside = weldColumns.filter { $0 > cutout.from && $0 < cutout.to }
        #expect(inside.isEmpty,
                "\(inside.count) weld columns land inside the cutout's own span — §5.1 says the hole gets no pixels")

        // And it fits in the window the panel actually is, which is the other way
        // a weld can be wrong: clipped by the panel edge on one side only.
        #expect(IslandGeometry.auraMargin >= IslandGeometry.filletRadius,
                "the panel reserves \(IslandGeometry.auraMargin)pt outside the body and the weld wants \(IslandGeometry.filletRadius)pt — one end of the island would be cut off by its own window")
    }

    /// The magnified visual, for a person to look at. Nothing is asserted here —
    /// `theWeldIsAHintOfACurveAndNotAScoop` is the assertion.
    ///
    ///     VIBECAT_FILLET_SHEET=/tmp/fillets.png swift test --filter filletSheet
    @MainActor
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAT_FILLET_SHEET"] != nil))
    func filletSheet() throws {
        let path = ProcessInfo.processInfo.environment["VIBECAT_FILLET_SHEET"]!
        let magnify: CGFloat = 10
        var tiles: [Raster] = []
        for f in [0, IslandGeometry.filletRadius, IslandGeometry.bottomRadius,
                  IslandGeometry.openBottomRadius] {
            // The island's own `--void` over the prototype's own stage tint, not
            // the white-on-clear the assertions above use: this one is for an eye,
            // and a white silhouette on transparency is invisible in most viewers.
            let view = ZStack(alignment: .topLeading) {
                Color(RGBA(hex: "#2C3A4A")!).frame(width: 46 + 24, height: 40)
                IslandShape(filletRadius: f)
                    .fill(Color(islandGroundColour))
                    .frame(width: 46, height: 32)
                    .offset(x: 12)
            }
            tiles.append(try rasterise(view, scale: magnify))
        }

        // And the same weld on the **real island**, both ends, cropped out of one
        // `IslandView` render so the two tiles are the same picture and can be
        // compared for the lopsidedness that got the fillets deleted in the first
        // place. The four tiles above are `IslandShape` alone, which says what the
        // profile is and nothing about what the island does with it.
        let m = IslandGoldenTests.model(.dormant, count: 0)
        let real = try rasterise(IslandView(model: m), scale: magnify)
        let body = IslandFrames(body: m.frames.body, panel: m.panelFrames.panel).bodyInPanel
        let crop = 30                                  // points of corner to keep
        let side = Int(CGFloat(crop) * magnify)
        for edge in [Int((body.minX * magnify).rounded()) - Int(IslandGeometry.filletRadius * magnify),
                     Int((body.maxX * magnify).rounded()) + Int(IslandGeometry.filletRadius * magnify) - side] {
            var bytes = [UInt8](repeating: 0, count: side * side * 4)
            for y in 0..<side {
                for x in 0..<side {
                    let sx = edge + x, sy = y
                    guard sx >= 0, sx < real.width, sy < real.height else { continue }
                    let p = real[sx, sy]
                    let i = (y * side + x) * 4
                    bytes[i] = p.r; bytes[i + 1] = p.g; bytes[i + 2] = p.b; bytes[i + 3] = p.a
                }
            }
            tiles.append(Raster(width: side, height: side, bytes: bytes))
        }
        let gutter = 20
        let w = tiles.reduce(0) { $0 + $1.width } + gutter * (tiles.count - 1)
        let h = tiles.map(\.height).max()!
        var sheet = [UInt8](repeating: 0, count: w * h * 4)
        var dx = 0
        for tile in tiles {
            for y in 0..<tile.height {
                for x in 0..<tile.width {
                    let p = tile[x, y]
                    let o = (y * w + dx + x) * 4
                    sheet[o] = p.r; sheet[o + 1] = p.g; sheet[o + 2] = p.b; sheet[o + 3] = p.a
                }
            }
            dx += tile.width + gutter
        }
        let ok = Raster(width: w, height: h, bytes: sheet).writePNG(to: path)
        print("""

          FILLETS AT \(Int(magnify))× — IslandShape alone at: none ·
          \(IslandGeometry.filletRadius)pt (--fillet, ours) · \(IslandGeometry.bottomRadius)pt ·
          \(IslandGeometry.openBottomRadius)pt — then the real dormant IslandView's
          top-left and top-right corners, which is the pair the lopsidedness
          complaint was about
          \(ok ? "wrote" : "FAILED to write") \(path)  \(w)×\(h)
        """)
    }
}
