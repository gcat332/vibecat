import Testing
import Foundation
import SwiftUI
@testable import VibeCatUI

// MARK: - the palette is the settings sheet's, not the island's

@Test func settingsHasItsOwnInkAndDoesNotBorrowTheIslands() {
    // The collision this guards: `--accent` is system blue in settings.html and
    // the current state's colour in the island. A settings switch tinted from
    // IslandState would turn amber because some agent is blocked. If someone
    // "unifies" the two palettes, this fails.
    #expect(SettingsPalette.systemBlue == RGBA(hex: "#0A84FF")!)
    #expect(SettingsPalette.dim == RGBA(hex: "#6A6A74")!)
    // The island's own dim (dormant's accent) is a different colour. Asserting
    // the difference is what makes the test about the collision rather than
    // about one value.
    #expect(SettingsPalette.dim != IslandState.dormant.accent,
            "the island's dim (#5A6273) is not the settings sheet's (#6A6A74)")
}

@Test func everyPaletteTokenMatchesThePrototypesOwnValue() {
    // Transcribed from settings.html:9-27. A wrong digit here is invisible.
    #expect(SettingsPalette.background == RGBA(hex: "#1C1C1E")!)
    #expect(SettingsPalette.chrome     == RGBA(hex: "#232326")!)
    #expect(SettingsPalette.pane       == RGBA(hex: "#161618")!)
    #expect(SettingsPalette.card       == RGBA(hex: "#2A2A2D")!)
    #expect(SettingsPalette.bone       == RGBA(hex: "#F2F2F5")!)
    #expect(SettingsPalette.haze       == RGBA(hex: "#9A9AA2")!)
    #expect(SettingsPalette.switchOff  == RGBA(hex: "#48484E")!)
    // `settings.html:14` — `--line:rgba(255,255,255,.08)`, split across two
    // properties because `RGBA` carries no alpha channel. **The opacity half was
    // asserted by nothing at all**, and it is the half with a plausible wrong
    // value: 0.30 for 0.08 passed all 20 tests in this file, because
    // `theSidebarsRightBorderIsTheHairlineAndNotOpaqueWhite` derived its expected
    // pixel from `hairlineOpacity` itself and so could only ever prove that the
    // caller applied *the* constant, never that the constant is 8%.
    #expect(SettingsPalette.hairline == RGBA(r: 1, g: 1, b: 1))
    #expect(SettingsPalette.hairlineOpacity == 0.08)
    // The other prototype's `--hairline` is `.09` and `PanelBar` draws with that
    // one. Asserting the disagreement is what keeps a future "let us unify these"
    // from silently moving one of the two surfaces.
    #expect(SettingsPalette.hairlineOpacity != hairlineOpacity,
            "settings.html's --line (.08) and island-motion.html's --hairline (.09) are different numbers")
}

@Test func theStateHuesInSettingsAreTheIslandsExactlyBecauseTheyPreviewIt() {
    // settings.html carries --idle/--running/--waiting/--error at the same values
    // as the island, because the Display page previews the island. This is the
    // one place state colour belongs in a settings sheet, and if the two ever
    // drift the preview stops being a preview. (This enum deliberately does not
    // hold copies of these four — it asserts agreement with IslandState instead.)
    #expect(RGBA(hex: "#3FD99B")! == IslandState.idle.accent)
    #expect(RGBA(hex: "#5B9DF9")! == IslandState.running.accent)
    #expect(RGBA(hex: "#FFA63C")! == IslandState.waiting.accent)
    #expect(RGBA(hex: "#FF5C5C")! == IslandState.failed.accent)
}

// MARK: - the switch actually draws its two states differently

@Test @MainActor func anOnSwitchDrawsSystemBlueAndAnOffSwitchDoesNot() throws {
    // Two renders differing in exactly one input, and asserting on a colour only
    // the thing under test can emit. A count-of-colours assertion would pass
    // against a switch that never changed at all — that exact mistake has been
    // made in this repo before, with a sprite emptied and eighty colours still
    // counted from everything else.
    //
    // `Raster.swift` has no `contains(_:tolerance:)` — the plan's draft of this
    // test named a helper that doesn't exist. What it actually has is
    // `pixelCount(near:tolerance:)`, used the same way throughout
    // `IslandGoldenTests.swift` and `RevealContentTests.swift`.
    let on = try rasterise(
        SettingsSwitch(isOn: .constant(true)).frame(width: 44, height: 28))
    let off = try rasterise(
        SettingsSwitch(isOn: .constant(false)).frame(width: 44, height: 28))
    #expect(on.pixelCount(near: SettingsPalette.systemBlue, tolerance: 12) > 0,
            "an on switch must carry system blue")
    #expect(off.pixelCount(near: SettingsPalette.systemBlue, tolerance: 12) == 0,
            "an off switch must not")
}
