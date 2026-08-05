import AppKit
import CoreGraphics
import SwiftUI
import Testing
@testable import VibeCatUI

private let mbp14 = ScreenMetrics(
    frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
    visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
    safeAreaTop: 32,
    auxLeft: CGRect(x: 0, y: 950, width: 663, height: 32),
    auxRight: CGRect(x: 848, y: 950, width: 664, height: 32))

@Test func drawerHeightsAreTheDesignsExactly() {
    #expect(DrawerFace.question.height == 288)
    #expect(DrawerFace.questionWithReply.height == 184)
    #expect(DrawerFace.questionMulti.height == 300)
}

/// §6.3: "the drawer follows its content — opening the reply field shrinks it
/// back rather than leaving dead space." Stated as a relation, so it survives
/// the numbers being retuned.
@Test func openingTheReplyFieldShrinksTheDrawer() {
    #expect(DrawerFace.questionWithReply.height < DrawerFace.question.height)
}

/// §5.3. The one invariant the whole layout is built on.
@Test func openingTheDrawerDoesNotMoveTheLeftEdge() {
    let g = IslandGeometry(screen: mbp14)
    let collapsed = g.frames(rightFlank: 35, tier: .rest)
    let open = g.frames(rightFlank: 35, tier: .drawer(face: .question))
    #expect(open.body.minX == collapsed.body.minX)
    #expect(open.panel.minX == collapsed.panel.minX)
}

/// §5.1, at the tier that could break it: the drawer hangs below the notch
/// line, so its own top edge starts at the cutout's bottom, never inside it.
///
/// The whole-branch review's minor: `open.body.maxY == g.notch.maxY` (this
/// test's own first assertion, before this fix) is a confirmed tautology —
/// `body` is always built as `y: screen.frame.maxY - height` (see
/// `IslandGeometry.frames`), so `body.maxY` reduces to `screen.frame.maxY`
/// for *any* height at all, and `notch.maxY` reduces to the same constant
/// the same way (`notch`'s own `y: frame.maxY - safeAreaTop`, `height:
/// safeAreaTop`). Confirmed directly: mutating `IslandTier.extraHeight` to
/// always return 0 — silently dropping the drawer's own requested height —
/// left that assertion green while only the second one (`body.height ==
/// notch.height + 288`, kept below unchanged) caught it. Replaced with the
/// actual claim: the gap between the notch's own top and the body's top is
/// exactly the drawer's requested height, which the same mutation does move
/// (to 0, against an expected 288).
@Test func theDrawerHangsBelowTheNotchLine() {
    let g = IslandGeometry(screen: mbp14)
    let open = g.frames(rightFlank: 35, tier: .drawer(face: .question))
    #expect(g.notch.minY - open.body.minY == 288)
    #expect(open.body.height == g.notch.height + 288)
}

/// Plan 3 sized the panel once and never resized it, which is safe only while
/// the island is click-through. The drawer is not, so the panel has to cover
/// exactly what takes clicks — no more.
///
/// The four equalities below mirror `IslandGeometryTests.thePanelIsInflatedForTheAuraOnThreeSidesOnly`'s
/// pattern at this tier (and give the brief's own `panel.maxY == body.maxY`
/// no-top-margin check), but by themselves they are not enough: `panel` is
/// *always* derived as `body` inflated by a constant `auraMargin` — see
/// `IslandGeometry.frames` — so these hold for whatever `body.height` turns
/// out to be, correct or not. Confirmed: mutating `IslandTier.extraHeight` to
/// always return `0` (the drawer silently contributing no height at all)
/// still satisfies all four. The first line below is the one that actually
/// depends on the drawer height reaching `body` in the first place: it
/// compares against an independently-tiered `collapsed`, rather than
/// restating `open`'s own (possibly wrong) arithmetic back at itself.
@Test func thePanelGrowsToHoldTheDrawer() {
    let g = IslandGeometry(screen: mbp14)
    let collapsed = g.frames(rightFlank: 35, tier: .rest)
    let open = g.frames(rightFlank: 35, tier: .drawer(face: .question))
    #expect(open.panel.height - collapsed.panel.height == 288,
            "the panel did not grow by the drawer's own requested height")
    #expect(open.panel.maxY == open.body.maxY)                       // no top margin
    #expect(open.panel.minX == open.body.minX - IslandGeometry.auraMargin)
    #expect(open.panel.maxX == open.body.maxX + IslandGeometry.auraMargin)
    #expect(open.panel.minY == open.body.minY - IslandGeometry.auraMargin)
}

@MainActor @Test func thePanelOnlyTakesClicksWhenAskedTo() {
    let frame = CGRect(x: 0, y: 0, width: 100, height: 40)
    let panel = NotchPanel(frames: IslandFrames(body: frame, panel: frame))
    #expect(panel.ignoresMouseEvents, "a collapsed island must stay click-through")
    panel.acceptsClicks = true
    #expect(panel.ignoresMouseEvents == false)
    panel.acceptsClicks = false
    #expect(panel.ignoresMouseEvents)
    #expect(panel.level == .statusBar, "toggling clicks moved the window level")
}

/// §5.1, at the tier that could newly break it: the drawer hangs below the
/// notch line, and this is the rule the whole layout exists to obey.
///
/// Modelled on `IslandGoldenTests.nothingIsDrawnInsideTheCutout` — same
/// ground-colour comparison, same panel-relative column arithmetic — but that
/// test renders through `IslandModel`/`IslandBody`, and neither can reach the
/// drawer tier yet: `IslandModel.frames`/`.panelFrames` are hardcoded to
/// `.rest` and stay that way here, since wiring a tier into the live model is
/// not one of this task's files (`IslandGeometry.swift` and `NotchPanel.swift`
/// only). So this renders the same production silhouette — `IslandShape`,
/// filled with the same ground colour, positioned by the same
/// `IslandFrames.bodyInPanel` — at the frames `IslandGeometry` itself now
/// produces for `.drawer`.
///
/// **What this does not prove, stated plainly so it isn't mistaken for more:**
/// the scene contains exactly one possible non-transparent colour — the
/// ground fill itself — so the `p == ground` check below cannot be violated
/// by any geometry bug that doesn't paint a genuinely different colour into
/// these columns, which nothing here does. It is not a proof that the
/// silhouette "clears" the cutout in any general sense; ground spanning the
/// cutout is correct by §5.1 ("the cutout is a hole... the black shape may
/// span it"). Concretely: the one mutation found that reddens this test
/// (`IslandGeometry.bottomRadius` 15→200, which `IslandShape`'s own `min`
/// clamps to 139 at this body's proportions) did so through a partially
/// transparent antialiasing artifact at the shape's boundary falling inside
/// the checked rows — not by demonstrating that distinct "content" entered
/// the hole. What this test actually establishes is narrower: that
/// `ImageRenderer` renders `IslandShape` + `IslandGeometry.frames(tier: .drawer)`
/// at a size never rendered before without error, and that the ground colour
/// and panel-relative column arithmetic agree at that size. It cannot yet
/// prove the cat/badge/session-count content stays clear of the cutout at
/// this height too — that needs real content in the scene, which needs
/// `IslandModel` to have a tier; that closes once a later task gives it one.
@MainActor @Test func nothingIsDrawnInsideTheCutoutWithTheDrawerOpen() throws {
    let ground = Raster.Pixel(islandGroundColour)   // derived, never restated — see Raster.Pixel(_:)
    let g = IslandGeometry(screen: mbp14)
    let open = g.frames(rightFlank: 35, tier: .drawer(face: .question))
    let origin = open.bodyInPanel.origin

    let scene = ZStack(alignment: .topLeading) {
        Color.clear
        IslandShape()
            .fill(Color(islandGroundColour))   // derived, so `ground` above cannot disagree with the scene
            .frame(width: open.body.width, height: open.body.height)
            .offset(x: origin.x, y: origin.y)
    }
    .frame(width: open.panel.width, height: open.panel.height, alignment: .topLeading)

    let raster = try rasterise(scene)
    let from = Int(g.notch.minX - open.panel.minX)
    let to = Int(g.notch.maxX - open.panel.minX)
    for x in from..<to {
        for y in 0..<raster.height {
            let p = raster[x, y]
            guard p.isTransparent == false else { continue }
            #expect(p == ground,
                    "drawer open: \(p) at panel column \(x) is inside the cutout — content has slid under the hole")
        }
    }
}
