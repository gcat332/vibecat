import Testing
import Foundation
import SwiftUI
@testable import VibeCatUI

/// `SettingsGroup`, `SettingsRow` and `SettingsSectionHeading`
/// (`SettingsRow.swift`) — the row primitives every remaining Settings page
/// assembles from.
///
/// **Helper names this plan's draft guessed at don't all exist.**
/// `Raster.measureHeight` is not a member of `Raster.swift` — `rasterise`
/// is a free function taking `(_:scale:)`, with no `size:` parameter, so a
/// caller applies `.frame(width:)` (no height, so the renderer reports the
/// view's own intrinsic height) the same way `PanelBarTests`'s own comment on
/// this exact gap describes. `measureHeight` below is a small test-file-local
/// wrapper over that, in the same spirit as `PanelBarTests.isBlank` and
/// `.fullyOpaquePixelCount`. `Raster.Pixel(_:)` and `pixelCount(near:tolerance:)`
/// **do** exist as the plan's draft used them.
@Suite("Settings row primitives")
struct SettingsRowTests {
    @MainActor
    static func measureHeight(_ view: some View, width: CGFloat) throws -> CGFloat {
        try CGFloat(rasterise(view.frame(width: width)).height)
    }

    @Test @MainActor func aRowWithADetailIsTallerThanOneWithout() throws {
        // Two renders differing in exactly one input — a measured height, not
        // a pixel count, because "more ink" is exactly the premise Plan 6.4
        // found false for a muted vs. unmuted speaker.
        let bare = try Self.measureHeight(SettingsRow("Fails") { EmptyView() }, width: 500)
        let full = try Self.measureHeight(SettingsRow("Stalls for 5 minutes",
                                                       detail: "Nothing has happened in the session and no question is pending.")
                                            { EmptyView() }, width: 500)
        #expect(full > bare + 10, "the detail line adds nothing: \(bare) vs \(full)")
    }

    @Test @MainActor func theNewBadgeIsGreenAndOnlyAppearsWhenAsked() throws {
        // `.new` is --idle green, the one legitimately state-coloured mark in
        // this sheet besides the two state pills. Counted inside the row's
        // own small render, never across a whole page — a mid-grey drew
        // 111/145/131 phantom hits off text antialiasing ramps when Plan 6.4
        // counted across a full pane instead.
        let plain = try rasterise(SettingsRow("Sound") { EmptyView() }.frame(width: 300, height: 44))
        let badged = try rasterise(SettingsRow("Sound", isNew: true) { EmptyView() }.frame(width: 300, height: 44))
        let green = SettingsPalette.newBadge
        #expect(badged.pixelCount(near: green, tolerance: 8) > 0, "isNew must draw the badge in --idle green")
        #expect(plain.pixelCount(near: green, tolerance: 8) == 0, "a plain row must not draw green at all")
    }

    /// The height of one `SettingsRow` inside a `SettingsGroup`, derived from two
    /// measurements rather than assumed: a one-row group is `row + 18` (the
    /// group's own `margin-bottom`), a two-row group is `2·row + 18`, so the
    /// difference is exactly one row and the boundary between rows one and two
    /// in the two-row render sits at that y.
    @MainActor
    static func rowHeightInAGroup(width: CGFloat) throws -> CGFloat {
        let one = try measureHeight(SettingsGroup { SettingsRow("Fails") { EmptyView() } },
                                    width: width)
        let two = try measureHeight(SettingsGroup {
            SettingsRow("Fails") { EmptyView() }
            SettingsRow("Fails") { EmptyView() }
        }, width: width)
        return two - one
    }

    @Test @MainActor func aRowsTopHairlineIsTheBlendOfThePrototypesEightPercent() throws {
        // Derived from settings.html:14's rgba(255,255,255,.08) over --card
        // #2A2A2D, not from SettingsPalette.hairlineOpacity itself — Plan 6.4
        // found the token-against-itself version of this passing at 0.30.
        let card = SettingsPalette.card
        let blend = RGBA(r: card.r + (1 - card.r) * 0.08,
                         g: card.g + (1 - card.g) * 0.08,
                         b: card.b + (1 - card.b) * 0.08)
        // **Read at the *second* row's top edge, because the first row no longer
        // draws one.** Task 7 implemented `settings.html:75`'s
        // `.group > .row:first-child{box-shadow:none}`, and this test used to
        // depend on its absence — a lone row wrapped in a group is that row's own
        // first-child case, and the old version expected the hairline anyway. The
        // two-row group below is what the prototype's rule is actually about, and
        // `theFirstRowInAGroupDrawsNoTopHairline` is the other half of it.
        //
        // `alignment: .top` on this outer frame is load-bearing, not cosmetic:
        // the group's natural height is a few points under the 80pt this
        // frame proposes, and the *default* `.center` alignment splits that
        // slack above and below — which quietly couples "is the hairline at
        // y≈0" to "does the content's height happen to match the frame I
        // picked". Measured directly: with `.center` (the default), inflating
        // `.row`'s own padding by 3pt a side grew the content just enough to
        // shift the centred row down and out of a `y:0..<3` window, so that
        // mutation looked caught for a reason that had nothing to do with
        // padding. Pinning to `.top` removes that coupling — the row's own
        // top, and therefore the hairline, sits at a fixed y regardless of
        // how tall the content below it is.
        let row = try rasterise(SettingsGroup {
            SettingsRow("Fails") { EmptyView() }
            SettingsRow("Fails") { EmptyView() }
        }.frame(width: 300, height: 120, alignment: .top))
        let secondRowTop = Int(try Self.rowHeightInAGroup(width: 300))
        // **Restricted to a box, not scanned across the whole render.**
        // `pixelCount(near:)` over the full image passed even after deleting
        // `hairlineOpacity` from the fill entirely: "Fails" is bone text
        // (#F2F2F5) antialiased over the card (#2A2A2D), and a low-coverage
        // edge of that ramp — bone at roughly 10% opacity over card — lands at
        // almost exactly this blend's ~(59,59,62), well inside `tolerance: 3`.
        // Measured, not assumed: the mutation below stayed green until the
        // count was confined to a strip at the row's own top edge, clear of
        // both the text (which starts well past the row's 11pt top padding)
        // and the group's rounded corners (radius 10, so x < 20 and x > 280
        // are excluded).
        let hairlineStrip = Self.count(in: row, x: 20, y: secondRowTop, width: 260, height: 3,
                                       near: blend, tolerance: 3)
        #expect(hairlineStrip > 0,
                "no hairline at the prototype's 8% along the second row's top edge (measured row height \(secondRowTop))")
    }

    @Test @MainActor func theRowsPaddingIsThePrototypesElevenAndFourteen() throws {
        // **Task 2 left `.row`'s `padding:11px 14px` pinned by nothing and named
        // this diff as the place to fix that.** Every number below was read out of
        // Chrome, not chosen: with the prototype's own window at 900, its
        // Notifications rows measure `654×44` with `padding: 11px 14px`, `gap:
        // 14px`, and a `38×22` `.sw` as the tallest thing in the row
        // (`getBoundingClientRect` + `getComputedStyle`, 2026-08-04).
        //
        // Three consequences follow arithmetically, and all three are asserted:
        // the row is `22 + 2×11 = 44` tall; the switch's track ends `14pt` from
        // the right edge, so at `654 − 14 = 640` (last lit pixel 639); and its top
        // is at `y = 11`.
        let width = 654
        let raster = try rasterise(SettingsGroup {
            SettingsRow("Fails") { SettingsSwitch(isOn: .constant(false)) }
        }.frame(width: CGFloat(width)))

        // The group carries `margin-bottom:18px` of its own.
        #expect(raster.height - 18 == 44,
                "a plain row is \(raster.height - 18)pt tall, the prototype's is 44")

        // **Scanned only past x=560, and that is not tidiness.** `#48484E` is a
        // mid grey and the title's bone-over-card antialiasing ramp passes
        // straight through it: measured, an unrestricted scan put the "track"
        // as far left as x=30, which is the letter F. The same trap
        // `aRowsTopHairlineIsTheBlendOfThePrototypesEightPercent` documents.
        var maxX = Int.min, minY = Int.max, maxY = Int.min
        let track = Raster.Pixel(SettingsPalette.switchOff)
        for y in 0..<raster.height {
            for x in 560..<raster.width {
                let p = raster[x, y]
                guard abs(Int(p.r) - Int(track.r)) <= 6, abs(Int(p.g) - Int(track.g)) <= 6,
                      abs(Int(p.b) - Int(track.b)) <= 6 else { continue }
                maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        #expect(maxX == width - 14 - 1,
                "the control's right edge is at \(maxX), 14pt padding puts it at \(width - 15)")
        #expect(minY == 11, "the control's top is at \(minY), 11pt padding puts it at 11")
        #expect(maxY - minY + 1 == 22, "the `.sw` is \(maxY - minY + 1)pt tall, not 22")
    }

    @Test @MainActor func theFirstRowInAGroupDrawsNoTopHairline() throws {
        // `settings.html:75` — `.group > .row:first-child{box-shadow:none}`. Task
        // 2 recorded this as unimplemented and Task 7's browser diff confirmed the
        // consequence: a line hugging the card's own rounded top edge, dividing
        // the first row from nothing.
        //
        // Same blend, same strip discipline, same render as the test above — so
        // this is not "a colour is absent somewhere" but "the colour that is
        // demonstrably drawn 39pt lower is not drawn here". A mutation that
        // reverts the exemption fails exactly this and nothing else.
        let card = SettingsPalette.card
        let blend = RGBA(r: card.r + (1 - card.r) * 0.08,
                         g: card.g + (1 - card.g) * 0.08,
                         b: card.b + (1 - card.b) * 0.08)
        let row = try rasterise(SettingsGroup {
            SettingsRow("Fails") { EmptyView() }
            SettingsRow("Fails") { EmptyView() }
        }.frame(width: 300, height: 120, alignment: .top))
        let firstStrip = Self.count(in: row, x: 20, y: 0, width: 260, height: 3,
                                    near: blend, tolerance: 3)
        #expect(firstStrip == 0,
                "the first row in a group still draws a top hairline (\(firstStrip) px)")
    }

    @Test @MainActor func aRowOutsideAGroupKeepsItsOwnHairline() throws {
        // The exemption is scoped to `.group > .row:first-child`, not to `.row`.
        // Without this, deleting the hairline outright would pass the two tests
        // above — the second row's line is the only thing they need, and a mutant
        // that made *every* row skip it would fail only the blend test... which is
        // why that one exists too. This pins the scope explicitly: the same row,
        // outside a group, over the same card ground, still draws it.
        let card = SettingsPalette.card
        let blend = RGBA(r: card.r + (1 - card.r) * 0.08,
                         g: card.g + (1 - card.g) * 0.08,
                         b: card.b + (1 - card.b) * 0.08)
        let bare = try rasterise(SettingsRow("Fails") { EmptyView() }
            .background(Color(card))
            .frame(width: 300, height: 80, alignment: .top))
        #expect(Self.count(in: bare, x: 20, y: 0, width: 260, height: 3,
                           near: blend, tolerance: 3) > 0,
                "a row outside a group lost the hairline `.row` always carries")
    }

    /// `pixelCount(near:)` restricted to a rectangle — the same shape of
    /// helper `SettingsSidebarTests.count(in:box:near:)` already uses, needed
    /// here because a mid-grey (or, as measured above, a *blend* colour that
    /// sits inside a light-on-dark antialiasing ramp) cannot be counted over
    /// a whole render.
    private static func count(in raster: Raster, x: Int, y: Int, width: Int, height: Int,
                              near colour: RGBA, tolerance: Int) -> Int {
        var n = 0
        for py in y..<(y + height) where py >= 0 && py < raster.height {
            for px in x..<(x + width) where px >= 0 && px < raster.width {
                let p = raster[px, py]
                guard p.a > 0 else { continue }
                let target = Raster.Pixel(colour)
                if abs(Int(p.r) - Int(target.r)) <= tolerance
                    && abs(Int(p.g) - Int(target.g)) <= tolerance
                    && abs(Int(p.b) - Int(target.b)) <= tolerance {
                    n += 1
                }
            }
        }
        return n
    }
}
