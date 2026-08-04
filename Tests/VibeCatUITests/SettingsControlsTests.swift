import Testing
import Foundation
import SwiftUI
@testable import VibeCatUI
import VibeCatCore

/// `SettingsSelect`, `SettingsButton`, `PermissionState` and `SettingsPill`
/// (`SettingsControls.swift`) — the last three controls the Notifications
/// page needs.
///
/// **Two of the plan's own draft assertions do not survive contact with this
/// suite's real helpers**, the same shape of gap `SettingsRowTests.swift`'s
/// own header note already recorded for Task 2:
///
/// - There is no `Raster.rasterise(_:size:)` static — `rasterise` is the free
///   function from `Raster.swift`, taking `(_:scale:)` with no `size:`
///   parameter, so a caller applies `.frame(width:height:)` first. And
///   `pixelCount(near:tolerance:)` takes an `RGBA`, not a `Raster.Pixel` —
///   `Raster.Pixel(_:)` exists only to build the *expected* side of an exact
///   per-pixel comparison (see `Raster.Pixel`'s own doc comment), not the
///   colour argument to `pixelCount`, so the plan's draft
///   `Raster.Pixel(RGBA(hex:...)!)` at that call site does not compile.
/// - The select test's own comparison, `a != b`, does not compile at all —
///   `Raster` is not `Equatable` (`SettingsSidebarTests.swift`'s header note
///   records the same gap for its sidebar tests). More importantly, even
///   spelled through `differingPixelCount(from:)`, "differs" was already
///   caught failing in the wrong direction once in this plan
///   (`SettingsSidebarTests.theSelectedPageIsTheOnlyOneMarkedCurrent`'s own
///   history) and the plan's own note for *this* test says so explicitly:
///   "the select ignores its binding" is a stronger claim than "two renders
///   differ". So this measures the rendered label's own **width** instead —
///   `"standard"` (8 characters) against `"meow"` (4) — which is a
///   value-specific, direction-pinned property `SettingsSelect` computes from
///   `label(selection)`, not a coincidence a broken picker could produce by
///   always drawing `Value.allCases.first`.
@Suite("Settings select, button and pill")
struct SettingsControlsTests {
    @MainActor
    static func measureWidth(_ view: some View, height: CGFloat) throws -> CGFloat {
        try CGFloat(rasterise(view.frame(height: height)).width)
    }

    // MARK: - .sel

    @Test @MainActor func aSelectShowsTheCurrentValueAndNotTheFirstOne() throws {
        // The defect this catches: a control rendering `allCases.first`
        // regardless of its binding, which looks perfect until you change it.
        // "standard" (8 glyphs) must measure wider than "meow" (4) — not merely
        // *different* from it, which a coincidental redraw could also produce.
        let standardWidth = try Self.measureWidth(
            SettingsSelect(.constant(CueChoice.standard)) { "\($0)" }, height: 28)
        let meowWidth = try Self.measureWidth(
            SettingsSelect(.constant(CueChoice.meow)) { "\($0)" }, height: 28)
        #expect(standardWidth > meowWidth + 10,
                "the select ignores its binding: standard=\(standardWidth) meow=\(meowWidth)")
    }

    @Test @MainActor func aSelectPaintsBoneOnCard2() throws {
        // The colour half of `.sel` (`settings.html:106`), inside the box the
        // closed control actually draws at — not scanned across the whole
        // frame, the same discipline `SettingsRowTests` needed for the
        // hairline: a mid-tone can land inside another mid-tone's tolerance by
        // coincidence once you stop restricting where you look.
        let raster = try rasterise(SettingsSelect(.constant(CueChoice.meow)) { "\($0)" }
            .frame(width: 140, height: 28, alignment: .topLeading))
        #expect(raster.pixelCount(near: SettingsPalette.card2, tolerance: 6) > 0,
                "no --card2 fill drawn")
        #expect(raster.pixelCount(near: SettingsPalette.bone, tolerance: 10) > 0,
                "no --bone text drawn")
    }

    @Test @MainActor func aSelectStillDrawsItsOwnBoxRatherThanAPickersChrome() throws {
        // Task 7 gave `SettingsSelect` a `.accessibilityRepresentation { Picker }`
        // so assistive technology gets a real combo box — the gap Task 3 recorded
        // and could not close. **Nothing headless can read an accessibility tree**
        // (no ViewInspector, and this project takes none), so what is pinned here
        // is the hazard that modifier introduces: if it ever stopped being purely
        // representational — or if someone "simplified" the drawing into the
        // native control it stands in for — the drawn box would become
        // `NSPopUpButton`'s, which Task 3 measured as a different size entirely
        // and a track of `#2E2E30` instead of `--card2`.
        //
        // The expected size is not a recorded number: it is a replica built from
        // `.sel`'s own CSS (`settings.html:106` — 13px text, padding 5/9), so this
        // compares the control against the rule it transcribes rather than against
        // whatever it happened to measure the day it was written.
        let replica = HStack(spacing: SettingsSelectMetrics.chevronGap) {
            Text("Meow").font(.system(size: 13))
            Image(systemName: "chevron.down")
                .font(.system(size: SettingsSelectMetrics.chevronSize, weight: .semibold))
        }
            .padding(.vertical, 5)
            .padding(.horizontal, 9)
        let expected = try rasterise(replica)
        let actual = try rasterise(SettingsSelect(.constant(CueChoice.meow)) { "\($0)" })
        #expect(actual.width == expected.width && actual.height == expected.height,
                "the select draws \(actual.width)×\(actual.height), `.sel`'s own padding predicts \(expected.width)×\(expected.height)")
    }

    // MARK: - .btn

    @Test @MainActor func aButtonCallsItsActionExactlyOnce() {
        var calls = 0
        SettingsButton("System Settings…") { calls += 1 }.actionForTesting()
        #expect(calls == 1)
    }

    @Test @MainActor func aButtonPaintsBoneOnCard2() throws {
        let raster = try rasterise(SettingsButton("System Settings…") {}
            .frame(width: 160, height: 28))
        #expect(raster.pixelCount(near: SettingsPalette.card2, tolerance: 6) > 0,
                "no --card2 fill drawn")
        #expect(raster.pixelCount(near: SettingsPalette.bone, tolerance: 10) > 0,
                "no --bone text drawn")
    }

    // MARK: - .pill

    @Test @MainActor func aGrantedPillIsGreenAndADeniedPillIsAmber() throws {
        // **The assertion that matters most in this whole task.** A permission
        // row that says "Granted" in amber, or "Denied" in green, is a lie
        // about a security state, and it is exactly the kind of wiring error a
        // property read cannot see — only a rendered pixel can.
        let size = CGSize(width: 120, height: 24)
        let ok = try rasterise(SettingsPill(.granted).frame(width: size.width, height: size.height))
        let no = try rasterise(SettingsPill(.denied).frame(width: size.width, height: size.height))
        let idle = RGBA(hex: "#3FD99B")!
        let waiting = RGBA(hex: "#FFA63C")!
        #expect(ok.pixelCount(near: idle, tolerance: 8) > 0
                && ok.pixelCount(near: waiting, tolerance: 8) == 0,
                "granted must be idle-green and never waiting-amber")
        #expect(no.pixelCount(near: waiting, tolerance: 8) > 0
                && no.pixelCount(near: idle, tolerance: 8) == 0,
                "denied must be waiting-amber and never idle-green")
    }

    @Test @MainActor func aNotDeterminedPillIsNeitherGreenNorAmber() throws {
        // The written decision this task records: `notDetermined` is a real
        // third state (Task 7's Automation read never prompts, so this will
        // genuinely occur) and claims neither security fact the prototype's
        // two colours would imply.
        let raster = try rasterise(SettingsPill(.notDetermined).frame(width: 160, height: 24))
        let idle = RGBA(hex: "#3FD99B")!
        let waiting = RGBA(hex: "#FFA63C")!
        #expect(raster.pixelCount(near: idle, tolerance: 8) == 0,
                "not-determined must not draw the granted green")
        #expect(raster.pixelCount(near: waiting, tolerance: 8) == 0,
                "not-determined must not draw the denied amber")
    }
}
