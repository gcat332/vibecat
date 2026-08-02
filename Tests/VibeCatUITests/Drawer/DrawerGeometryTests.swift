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
    let open = g.frames(rightFlank: 35, tier: .drawer(height: DrawerFace.question.height))
    #expect(open.body.minX == collapsed.body.minX)
    #expect(open.panel.minX == collapsed.panel.minX)
}

/// §5.1, at the tier that could break it: the drawer hangs below the notch
/// line, so its own top edge starts at the cutout's bottom, never inside it.
@Test func theDrawerHangsBelowTheNotchLine() {
    let g = IslandGeometry(screen: mbp14)
    let open = g.frames(rightFlank: 35, tier: .drawer(height: 288))
    #expect(open.body.maxY == g.notch.maxY)
    #expect(open.body.height == g.notch.height + 288)
}

/// Plan 3 sized the panel once and never resized it, which is safe only while
/// the island is click-through. The drawer is not, so the panel has to cover
/// exactly what takes clicks — no more.
@Test func thePanelGrowsToHoldTheDrawer() {
    let g = IslandGeometry(screen: mbp14)
    let open = g.frames(rightFlank: 35, tier: .drawer(height: 288))
    #expect(open.panel.height >= open.body.height)
    #expect(open.panel.minY <= open.body.minY)
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
/// produces for `.drawer`, which is exactly what this task changed. It cannot
/// yet prove the cat/badge/session-count content stays clear of the cutout at
/// this height too; that closes once a later task gives the model a tier.
@MainActor @Test func nothingIsDrawnInsideTheCutoutWithTheDrawerOpen() throws {
    let ground = Raster.Pixel(r: 5, g: 7, b: 11, a: 255)     // islandGroundColour, §7.1
    let g = IslandGeometry(screen: mbp14)
    let open = g.frames(rightFlank: 35, tier: .drawer(height: DrawerFace.question.height))
    let origin = open.bodyInPanel.origin

    let scene = ZStack(alignment: .topLeading) {
        Color.clear
        IslandShape()
            .fill(Color(RGBA(hex: "#05070B")!))
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
