import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import VibeCatUI

/// What the island actually paints.
///
/// Everything else in this suite reasons about `IslandBody` through its
/// properties: what `restingWidth` returns, whether `body` read it. Three
/// `#if DEBUG` counters exist because an `@escaping` closure never runs during
/// `.body` access, and `IslandViewTests` says of one of them that going
/// further "would need a snapshot or view-inspection dependency, which this
/// project does not take."
///
/// `ImageRenderer` is that snapshot capability, in the standard library, with
/// no dependency to take. It renders offscreen with no window server, so it
/// works on a locked machine — which two plans wrongly recorded as blocking
/// visual verification. A counter proves a property was *touched*; these tests
/// prove it reached the pixels.
@Suite("Island golden images")
struct IslandGoldenTests {
    static let mbp14 = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
        safeAreaTop: 32,
        auxLeft: CGRect(x: 0, y: 950, width: 663, height: 32),
        auxRight: CGRect(x: 848, y: 950, width: 664, height: 32))

    @MainActor
    static func model(_ state: IslandState, count: Int, hovering: Bool = false,
                      coat: Coat = .tabby) -> IslandModel {
        let m = IslandModel(geometry: IslandGeometry(screen: mbp14),
                            motion: MotionPreference(chosen: .full, systemWantsReduced: false))
        m.state = state
        m.sessionCount = count
        m.hovering = hovering
        m.coat = coat
        return m
    }

    /// Columns holding at least one non-transparent pixel. The island is the
    /// only thing drawn, so this is the painted silhouette's extent — measured
    /// off the render rather than recomputed from the same constants the view
    /// used, which would just be the implementation agreeing with itself.
    static func paintedColumns(_ r: Raster) -> (first: Int, last: Int, count: Int)? {
        var first = -1, last = -1
        for x in 0..<r.width {
            let painted = (0..<r.height).contains { r[x, $0].isTransparent == false }
            if painted {
                if first < 0 { first = x }
                last = x
            }
        }
        guard first >= 0 else { return nil }
        return (first, last, last - first + 1)
    }

    @MainActor
    static func silhouette(_ m: IslandModel, scale: CGFloat = 1) throws -> (first: Int, last: Int, count: Int) {
        let raster = try rasterise(IslandBody(model: m, now: Date(timeIntervalSince1970: 1_000_000)),
                                   scale: scale)
        return try #require(paintedColumns(raster), "the island painted nothing at all")
    }

    /// The width split reaches the pixels.
    ///
    /// `bodyActuallyRoutesThroughBothHalvesOfTheWidthSplit` proves the two
    /// properties are read while `body` is built. It cannot prove the sum
    /// reached a `.frame`, and says so. This can: hovering has to widen the
    /// painted silhouette by exactly `hoverReveal` and by nothing else.
    @MainActor @Test func hoveringWidensThePaintedIslandByExactlyTheReveal() throws {
        for count in [0, 3] {
            let rest = try Self.silhouette(Self.model(.running, count: count))
            let hovered = try Self.silhouette(Self.model(.running, count: count, hovering: true))
            #expect(hovered.count - rest.count == Int(CollapsedLayout.hoverReveal),
                    "count=\(count): hover changed the painted width by \(hovered.count - rest.count)pt, not \(Int(CollapsedLayout.hoverReveal)) — the reveal is not reaching the frame")
        }
    }

    /// `IslandView` — the real top-level view, both branches of it — paints a
    /// visible island in every state.
    ///
    /// This is the shape of the worst bug this project has shipped: a guard
    /// that could never fire left `IslandView` unhosted and the island blank,
    /// and nothing noticed until a review added a build counter. A counter
    /// answers "was it built"; this answers "is anything there", which is the
    /// question that was actually wrong.
    ///
    /// It covers the `TimelineView` branch too. That closure is `@escaping`
    /// and does not run for `.body` access — but it does run for a render,
    /// which is the whole reason this file exists.
    @MainActor @Test func everyStateRendersAVisibleIsland() throws {
        for state in IslandState.allCases {
            let m = Self.model(state, count: state == .dormant ? 0 : 4)
            let raster = try rasterise(IslandView(model: m))
            let painted = try #require(Self.paintedColumns(raster),
                                       "\(state): IslandView painted nothing — the island is blank")
            #expect(painted.count >= Int(IslandGeometry.leftFlank),
                    "\(state): only \(painted.count)pt of island was painted")

            // Blank-but-for-the-ground is the other half of the failure, and
            // counting distinct colours does not catch it: with the cat's
            // `Canvas` emptied, this render still produced eighty-odd colours
            // from the badge and the antialiased session count, and a
            // colour-count assertion passed while the cat was missing.
            //
            // The fixed facial tones are the discriminator. `innerEar` and
            // `nose` are the only two colours in the palette that no accent
            // derives — they are the same pink in every state, precisely so a
            // nose reads as a nose at any hue — and nothing else on the island
            // draws in them. Finding them is proof the sprite drew.
            let palette = CatPalette(accent: state.accent)
            for tone in [Tone.innerEar, .nose] {
                #expect(raster.pixelCount(near: palette[tone]) > 0,
                        "\(state): no \(tone) pixel anywhere — the cat sprite did not draw")
            }
        }
    }

    /// Design §5.3: the left edge is fixed, so the cat never walks sideways.
    /// Asserted on the render, so it covers the layout as well as the geometry
    /// — `IslandGeometryTests` pins `body.minX`, which is a different claim
    /// from "the leftmost painted pixel does not move".
    @MainActor @Test func thePaintedLeftEdgeNeverMoves() throws {
        let edges = try [
            Self.silhouette(Self.model(.dormant, count: 0)).first,
            Self.silhouette(Self.model(.running, count: 3)).first,
            Self.silhouette(Self.model(.running, count: 999)).first,
            Self.silhouette(Self.model(.running, count: 3, hovering: true)).first,
            Self.silhouette(Self.model(.waiting, count: 1)).first,
        ]
        #expect(Set(edges).count == 1,
                "the island's painted left edge moved between states: \(edges)")
    }

    /// The reason the minimum right flank exists, checked where it has to be
    /// true: on a dormant island the painted silhouette must extend a full
    /// corner radius past the cutout, so our corner covers the hardware's
    /// instead of being drawn into the same points as it.
    @MainActor @Test func theDormantIslandPaintsPastTheCutout() throws {
        let m = Self.model(.dormant, count: 0)
        let painted = try Self.silhouette(m)
        // The render is panel-sized; convert the panel-local last column back
        // to screen coordinates before comparing with the cutout.
        let lastX = m.frames.panel.minX + CGFloat(painted.last) + 1
        let notch = IslandGeometry(screen: Self.mbp14).notch
        #expect(lastX >= notch.maxX + IslandGeometry.bottomRadius,
                "the dormant island stops \(lastX - notch.maxX)pt past the cutout, inside its own \(IslandGeometry.bottomRadius)pt corner — the hardware's corner is left showing")
    }

    /// Design §5.1, the rule the whole layout exists to obey: the cutout is a
    /// hole and nothing may be drawn in it.
    ///
    /// Checked against the *content*, not the silhouette — the island's ground
    /// spans the cutout by design; what must not appear there is a cat, a
    /// badge or a digit. Any pixel differing from the island's own ground
    /// colour inside the cutout's columns is content that has slid under it.
    @MainActor @Test func nothingIsDrawnInsideTheCutout() throws {
        let ground = Raster.Pixel(r: 5, g: 7, b: 11, a: 255)     // islandGroundColour
        for (state, count) in [(IslandState.running, 999), (.waiting, 3), (.dormant, 0)] {
            let m = Self.model(state, count: count)
            let raster = try rasterise(IslandBody(model: m, now: Date(timeIntervalSince1970: 1_000_000)))
            let notch = IslandGeometry(screen: Self.mbp14).notch
            let from = Int(notch.minX - m.frames.panel.minX)
            let to = Int(notch.maxX - m.frames.panel.minX)
            for x in from..<to {
                for y in 0..<raster.height {
                    let p = raster[x, y]
                    guard p.isTransparent == false else { continue }
                    #expect(p == ground,
                            "\(state) count=\(count): \(p) at panel column \(x) is inside the cutout — content has slid under the hole")
                }
            }
        }
    }
}
