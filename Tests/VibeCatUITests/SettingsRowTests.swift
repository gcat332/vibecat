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

    @Test @MainActor func aRowsTopHairlineIsTheBlendOfThePrototypesEightPercent() throws {
        // Derived from settings.html:14's rgba(255,255,255,.08) over --card
        // #2A2A2D, not from SettingsPalette.hairlineOpacity itself — Plan 6.4
        // found the token-against-itself version of this passing at 0.30.
        let card = SettingsPalette.card
        let blend = RGBA(r: card.r + (1 - card.r) * 0.08,
                         g: card.g + (1 - card.g) * 0.08,
                         b: card.b + (1 - card.b) * 0.08)
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
        let row = try rasterise(SettingsGroup { SettingsRow("Fails") { EmptyView() } }
            .frame(width: 300, height: 80, alignment: .top))
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
        let hairlineStrip = Self.count(in: row, x: 20, y: 0, width: 260, height: 3, near: blend, tolerance: 3)
        #expect(hairlineStrip > 0, "no hairline at the prototype's 8% along the row's own top edge")
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
