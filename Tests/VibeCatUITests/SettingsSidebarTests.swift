import Testing
import Foundation
import SwiftUI
@testable import VibeCatUI
import VibeCatCore

/// The `196pt` nav (`settings.html:53`) and the four panes' chrome (`:66-70`,
/// `:210`, `:273`, `:323`, `:379`).
///
/// Two of the plan's own draft assertions named APIs this suite does not have,
/// and both are adapted rather than added: there is no `Raster.rasterise(_:size:)`
/// static — the free function `rasterise(_:scale:)` takes no size, so a caller
/// applies `.frame(width:height:)` first, the convention every other golden test
/// here already follows — and `Raster` is not `Equatable`, so `general != display`
/// is spelled with `differingPixelCount(from:)`, which also says *how much*
/// differed when it fails.
@Suite("Settings sidebar and panes")
struct SettingsSidebarTests {
    // MARK: - the four pages

    @Test func theFourPagesAreTheProtoypesFourInItsOrder() {
        #expect(SettingsPage.all.map(\.key) == ["general", "integrations", "notifications", "display"])
        #expect(SettingsPage.all.map(\.label) == ["General", "Integrations", "Notifications", "Display"])
    }

    @Test func theCoreAndTheUIAgreeOnThePageKeys() {
        // SettingsPageKey lives in VibeCatCore because `load()` must reject an
        // unknown key and Core cannot see the views. Two lists of the same truth is
        // a drift waiting to happen — this is the only thing that would notice.
        #expect(SettingsPage.all.map(\.key) == SettingsPageKey.all)
    }

    @Test func eachPageWearsItsOwnChipColourAndNoneIsAStateColour() {
        #expect(SettingsPage.all.map(\.chip) == [RGBA(hex: "#6E6E73")!, RGBA(hex: "#32ADE6")!,
                                                 RGBA(hex: "#FF3B30")!, RGBA(hex: "#5E5CE6")!])
        // The point of the assertion: a sidebar chip must never be mistaken for the
        // island's state vocabulary. Notifications' red is #FF3B30; failed is #FF5C5C.
        // The plan's draft wrote this as a `Set` — `RGBA` is `Equatable` but not
        // `Hashable`, so that does not compile, and making a production type
        // conform for one test's convenience is the wrong direction. An array and
        // `contains` answer the same question.
        let stateHues = IslandState.allCases.map(\.accent)
        for page in SettingsPage.all {
            #expect(!stateHues.contains(page.chip), "\(page.key)'s chip is a state colour")
        }
    }

    @Test func everyPageHasItsOwnGlyphAndNoTwoShareOne() {
        // `settings.html:520-523` gives each page its own `d`. Four pages wearing
        // one glyph would leave the sidebar's rows distinguishable only by colour
        // and text — and it is the one defect `eachPageWearsItsOwnChipColour…`
        // above cannot see, since that test never looks at the icon at all.
        #expect(Set(SettingsPage.all.map(\.icon)).count == SettingsPage.all.count)
        // Every glyph draws *something*: a case that returned `nil` from both
        // halves would render an empty chip and every other assertion here would
        // still pass, because the chip's own colour is drawn by the rounded rect
        // behind the glyph.
        for page in SettingsPage.all {
            #expect(page.icon.strokedPath != nil || page.icon.filledPath != nil,
                    "\(page.key)'s glyph draws nothing")
        }
    }

    @Test func everyPaneAnnouncesWhichPlanOwnsItsControls() {
        // This plan ships chrome. A pane that looks finished and does nothing is
        // worse than one that says so, and this is what stops the next reader
        // filing it as a bug.
        for page in SettingsPage.all where page.key != "notifications" {
            #expect(SettingsPage.ownerNote(for: page.key) != nil, "\(page.key) has no owner note")
        }
        // The plan's own loop skips `notifications` — presumably because mute, the
        // one control 6.4 does ship, is that page's. It still has no controls *in
        // this window*, so it still carries a note, and asserting it here is what
        // stops "every pane" from being a name for "three panes". Reported rather
        // than silently rewriting the plan's loop.
        #expect(SettingsPage.ownerNote(for: "notifications") != nil)
        // The other half: an unknown key has no note, so a `switch` with a
        // `default` returning a placeholder string cannot pass.
        #expect(SettingsPage.ownerNote(for: "kitchen-sink") == nil)
        // Each note names the plan that owns the page, which is the whole content
        // of the promise. A note that said "coming soon" would pass every
        // assertion above.
        #expect(SettingsPage.ownerNote(for: "general")?.contains("6.7") == true)
        #expect(SettingsPage.ownerNote(for: "integrations")?.contains("6.7") == true)
        #expect(SettingsPage.ownerNote(for: "notifications")?.contains("6.5") == true)
        #expect(SettingsPage.ownerNote(for: "display")?.contains("6.6") == true)
    }

    // MARK: - what is actually drawn

    @Test @MainActor func theSelectedPageIsTheOnlyOneMarkedCurrent() throws {
        // **This test's first version could not fail in the direction that
        // matters, and this is the seventh such test in this plan.** It rendered
        // two selections and asserted only `differingPixelCount > 0`. Measured:
        // inverting `SettingsSidebar.swift:30` from `page.key == selection` to
        // `!=` left all 29 tests in this file green — three rows highlighted at
        // 11% white, the current row plain, and `.isSelected` on exactly the
        // wrong three rows. "Differs" is not "differs in the right direction".
        //
        // So the highlight is counted, per row, inside a window where only the
        // highlight can be:
        //
        //   * Rows are `36pt` apart from `y = 10` — `.padding(.vertical, 10)` on
        //     the stack, then `24pt` chip + `6pt` above and below inside each
        //     `.nav`. The same three numbers `theSidebarsRowsSitWhereThePrototype
        //     Measures` pins.
        //   * `x 140..<185` because that is past the longest label. Measured, not
        //     guessed: the four rows' ink stops at x 95, 121, 125 and 93, so
        //     "Notifications" leaves a 15pt margin. **The whole row box does not
        //     work** — 6 to 12 pixels of label antialiasing over `--pane` pass
        //     through the highlight's own value on their way from `--bone`, so an
        //     unselected row reads 6–12 rather than 0 there. A window with no
        //     text in it reads exactly 0.
        //   * The expected colour is `rgba(255,255,255,.11)` over `--pane`
        //     (`settings.html:57`), composited by hand, not transcribed from a
        //     render.
        //   * The expected *count* is the window's own area: 45 columns × 32 rows
        //     = 1440. Measured 1440.
        let o = 0.11
        let pane = SettingsPalette.pane
        let highlight = RGBA(r: pane.r * (1 - o) + o, g: pane.g * (1 - o) + o, b: pane.b * (1 - o) + o)
        let window = 140..<185
        let rowHeight = 36, firstRowTop = 10, inset = 2

        for selected in SettingsPage.all {
            let sidebar = try rasterise(SettingsSidebar(selection: .constant(selected.key))
                .frame(height: 200))
            for (i, page) in SettingsPage.all.enumerated() {
                let top = firstRowTop + rowHeight * i
                var n = 0
                for y in (top + inset)..<(top + rowHeight - inset) {
                    for x in window where near(sidebar[x, y], highlight, tolerance: 3) { n += 1 }
                }
                if page.key == selected.key {
                    #expect(n == window.count * (rowHeight - 2 * inset),
                            "selecting \(selected.key) did not highlight its own row (\(n) of 1440 pixels)")
                } else {
                    #expect(n == 0,
                            "selecting \(selected.key) also highlighted \(page.key) (\(n) pixels)")
                }
            }
        }
    }

    @Test @MainActor func theSidebarIsTheWidthTheProtoypeGivesIt() throws {
        // `settings.html:53` — `.side{width:196px}`, border included, because
        // `*{box-sizing:border-box}` (`:29`). No `.frame(width:)` here on purpose:
        // the width has to come from the view itself, or the pane beside it starts
        // in the wrong place.
        let sidebar = try rasterise(SettingsSidebar(selection: .constant("general"))
            .frame(height: 200))
        #expect(sidebar.width == 196)
    }

    @Test @MainActor func theSidebarsRowsSitWhereThePrototypeMeasures() throws {
        // Numbers read out of a real Chrome layout of `settings.html`, not off its
        // CSS: `.side` at x=307 puts its first `.chip` at x=323 and y=+16, and the
        // four rows are pitched exactly 36pt apart (y = 79, 115, 151, 187 against a
        // sidebar at y=69). That is `padding:10px 8px` on `.side` plus `padding:6px
        // 8px` on `.nav` around a `24pt` chip — so the chips land at (16, 16 + 36n),
        // and every one of those three numbers is a separate thing to get wrong.
        //
        // Each chip is looked for at its own place, which is also what pins the
        // *order*: the same four colours in the wrong order fails here while
        // passing `theFourPagesAreTheProtoypesFourInItsOrder`, since that reads the
        // list rather than the render.
        let sidebar = try rasterise(SettingsSidebar(selection: .constant("general"))
            .frame(height: 200))
        for (i, page) in SettingsPage.all.enumerated() {
            let box = (x: 16, y: 16 + 36 * i, side: 24)
            #expect(count(in: sidebar, box: box, near: page.chip) > 300,
                    "\(page.key)'s chip is not at (16,\(box.y)) — row pitch or padding is off")
        }
    }

    @Test @MainActor func theChipsGlyphIsTheFourteenPointOneThePrototypeDraws() throws {
        // `.chip svg{width:14px;height:14px;color:#fff}` (`settings.html:63`) in a
        // `24pt` chip. Nothing else here would notice the glyph being drawn at the
        // chip's own size: the chip-colour counts have hundreds of pixels of slack,
        // and a bigger glyph only eats into that slack.
        //
        // **A first version of this only asked that no white fell outside the
        // centred 14pt box, and it could not fail** for anything short of a glyph at
        // the full 24: at 20pt the bell's own ink still lands inside a 14pt box's
        // one-pixel-slack window (mutation 14, this task's report). So the
        // assertion is on the ink's measured *width* against the width the
        // prototype's own numbers predict:
        //
        //   the bell path spans x 4.4…19.6 in a 24 viewBox, so at `14/24` its
        //   centreline spans 8.87pt.
        //
        // The *centreline*, not the stroked outline: at this size the stroke is
        // 2 × 14/24 = 1.17pt wide, so no pixel at its outer edge is ever fully
        // covered and a near-white reading traces the path itself. (The stroked
        // extent would be 10.03pt; the measured core is 8.0, and pinning the
        // wider number would have meant widening the tolerance until it fit
        // rather than predicting what is being measured.) At `glyphSide: 20` the
        // same arithmetic gives 12.67pt, well outside the ±1.5 allowed here.
        let bell = SettingsPage.all[2]
        let pane = try rasterise(SettingsPaneView(page: bell).frame(width: 704, height: 620))
        let chip = (x: 24, y: 20, side: 24)
        var minX = Int.max, maxX = Int.min
        for y in chip.y..<(chip.y + chip.side) {
            for x in chip.x..<(chip.x + chip.side) where near(pane[x, y], RGBA(r: 1, g: 1, b: 1), tolerance: 40) {
                minX = min(minX, x)
                maxX = max(maxX, x)
            }
        }
        #expect(minX <= maxX, "the chip drew no glyph at all")
        let inkWidth = Double(maxX - minX + 1)
        let expected = (19.6 - 4.4) * 14 / 24
        #expect(abs(inkWidth - expected) <= 1.5,
                "the bell's ink is \(inkWidth)pt wide, expected ~\(expected)pt for a 14pt glyph")
    }

    @Test @MainActor func theSidebarsRightBorderIsTheHairlineAndNotOpaqueWhite() throws {
        // **`SettingsPalette.hairline` is stored as opaque white** — `RGBA` has no
        // alpha channel — so `border-right:1px solid rgba(255,255,255,.08)` only
        // happens if the *caller* applies the opacity. Nothing in Task 2's own
        // tests could notice a caller forgetting to: the value is a legitimate
        // colour either way, and the sidebar would still draw a 1pt rule down its
        // trailing edge. It would just be a bright white one.
        //
        // So the expected value is derived from the rule — 8% white composited
        // over `--pane` — rather than transcribed from a measurement.
        //
        // **And the rule's two numbers are the prototype's own literals, not
        // `SettingsPalette`'s constants, which is a deliberate change.** Deriving
        // `o` from `SettingsPalette.hairlineOpacity` pins "the caller applied *the*
        // constant" and nothing more: measured, `0.08` → `0.30` in
        // `SettingsPalette.swift` left this test and all 20 in
        // `SettingsPaletteTests` green, because both sides of the comparison moved
        // together. Transcribing `settings.html:14`'s `.08` and `:12`'s `#161618`
        // here means this render is pinned to the prototype end to end, and the
        // palette's own test pins the constants separately.
        let sidebar = try rasterise(SettingsSidebar(selection: .constant("general"))
            .frame(height: 200))
        let o = 0.08
        let pane = RGBA(hex: "#161618")!
        let expected = Raster.Pixel(RGBA(r: pane.r * (1 - o) + o,
                                         g: pane.g * (1 - o) + o,
                                         b: pane.b * (1 - o) + o))
        let border = sidebar[sidebar.width - 1, 100]
        #expect(abs(Int(border.r) - Int(expected.r)) <= 3
            && abs(Int(border.g) - Int(expected.g)) <= 3
            && abs(Int(border.b) - Int(expected.b)) <= 3,
                "the trailing border read \(border), expected ~\(expected): 8% white over --pane. Opaque white reads #FFFFFF, a missing border reads --pane itself")
    }

    @Test @MainActor func eachPaneWearsItsOwnPagesChipAndNoOthers() throws {
        // `settings.html:532` — "the pane headings reuse the sidebar's icon so the
        // two always agree" — and the failure it guards is a pane heading built
        // from a second, hand-copied chip declaration. A pane drawing the wrong
        // page's chip, or none, fails here.
        //
        // **Counted inside the chip's own box, not over the whole pane, and the
        // reason is a false positive this test hit first time out.** `general`'s
        // `#6E6E73` is a mid grey, and *every* antialiased edge on the pane crosses
        // it: `--haze` text over `--card` passes through `(110,110,115)` at about
        // 61% coverage, and `--bone` over `--bg` at about 38%. Measured — the
        // whole-pane version of this assertion read 111, 145 and 131 stray "chip"
        // pixels on the three panes that draw no grey chip at all. Tightening the
        // tolerance cannot fix that; a ramp passes through every value on it.
        //
        // So the window is a *place* instead of a colour: `.content{padding:20px
        // 24px}` puts `.ptitle`'s `24×24` chip at exactly (24,20). Inside that box
        // only two inks exist, the chip and its white glyph, and no white-over-chip
        // ramp for any of these four colours crosses another one of them.
        //
        // The floor is derived rather than observed: 24×24 = 576 pixels, less the
        // `14×14` glyph box (196) and the four `6pt` corner radii (~31), leaves
        // ~349 that can only be flat chip colour.
        let chipBox = (x: 24, y: 20, side: 24)
        for page in SettingsPage.all {
            let pane = try rasterise(SettingsPaneView(page: page).frame(width: 704, height: 620))
            #expect(count(in: pane, box: chipBox, near: page.chip) > 300,
                    "\(page.key)'s pane heading does not draw its own chip at (24,20)")
            for other in SettingsPage.all where other.key != page.key {
                #expect(count(in: pane, box: chipBox, near: other.chip) == 0,
                        "\(page.key)'s pane draws \(other.key)'s chip colour")
            }
        }
    }

    @Test @MainActor func aPaneDrawsItsOwnerNoteRatherThanMerelyHavingOne() throws {
        // `everyPaneAnnouncesWhichPlanOwnsItsControls` reads a static function. It
        // passes just as well against a pane that never draws the note at all —
        // which is exactly the defect that matters, because a pane looking finished
        // is the thing the note exists to prevent.
        //
        // The note is the only thing on a pane below the heading, and it is made of
        // three inks: the `--card` group behind it, the `--blue` rule, and the
        // `--haze` text. So below the heading band, a pixel that is none of the
        // card, the rule or the window's own ground can only be text — which makes
        // "the words were drawn" answerable without reading them.
        let pane = try rasterise(SettingsPaneView(page: SettingsPage.all[3])
            .frame(width: 704, height: 620))
        // `.content{padding-top:20px}` + `.chip{height:24px}` +
        // `.ptitle{padding-bottom:18px}` = the group starts at y=62. Everything
        // above that is the heading, and its bone text would otherwise count as
        // "ink that is not the card".
        let firstRowBelowTheHeading = 66
        #expect(PanelBarTests.fullyOpaquePixelCount(pane, near: SettingsPalette.card) > 0,
                "the note's `.group` card is missing")

        var textPixels = 0
        var rulePixels = 0
        for y in firstRowBelowTheHeading..<pane.height {
            for x in 0..<pane.width {
                let p = pane[x, y]
                guard p.a == 255 else { continue }
                if near(p, SettingsPalette.systemBlue) { rulePixels += 1 }
                // `--haze` is the note text's own ink and the only thing on a pane
                // that wears it. The card's rounded corners blend card→`--bg`
                // (darker than either) and the rule's edges blend blue→card;
                // neither ramp comes anywhere near `#9A9AA2`.
                else if near(p, SettingsPalette.haze, tolerance: 10) { textPixels += 1 }
            }
        }
        #expect(rulePixels > 0, "`.note i`, the 2pt blue rule, is missing")
        // **The first version of this counted "any fully-opaque pixel that is
        // neither the card, the rule nor the background", and it could not fail.**
        // Replacing the note's `Text` with an empty one left it green: the card's
        // own antialiased corners and the rule's own antialiased edges are already
        // "not one of those three colours", so the count never reached zero and the
        // assertion was measuring antialiasing. Measured, not reasoned about —
        // mutation 7 in this task's report. Counting the text's *own* ink instead
        // reads 875 pixels here and exactly 0 with the words removed.
        #expect(textPixels > 100, "the note's card and rule are drawn but its words are not (\(textPixels) haze pixels)")
    }

    @Test @MainActor func theShellShowsThePaneTheSidebarSelects() throws {
        // The wiring test. `theSelectedPageIsTheOnlyOneMarkedCurrent` proves the
        // *sidebar* reads `selection`; this proves the content area does, which is
        // a separate defect — a shell that always drew General would pass every
        // other assertion in this file.
        //
        // Read at the pane heading's chip box, not over the whole shell: the
        // sidebar draws all four chips on every render, so a whole-shell count
        // mixes the thing under test with three constants and the grey noise
        // `eachPaneWearsItsOwnPagesChipAndNoOthers` documents. The heading's chip
        // sits at `196` (`.side`) + `24` (`.content`'s padding) = x 220, y 20,
        // where nothing else on the shell is drawn.
        let size = SettingsWindowController.contentSize
        let headingChip = (x: Int(SettingsSidebar.width) + 24, y: 20, side: 24)
        for selected in SettingsPage.all {
            let shell = try rasterise(SettingsShell(selection: .constant(selected.key))
                .frame(width: size.width, height: size.height))
            #expect(count(in: shell, box: headingChip, near: selected.chip) > 300,
                    "selecting \(selected.key) did not put its chip in the pane heading")
            for other in SettingsPage.all where other.key != selected.key {
                #expect(count(in: shell, box: headingChip, near: other.chip) == 0,
                        "selecting \(selected.key) drew \(other.key)'s pane heading")
            }
        }
    }

    @Test @MainActor func theWindowsRootViewShowsTheModelsPage() throws {
        // The one thing between the observable model and everything above:
        // `SettingsRootView`'s `@Bindable` bridge. Handing `SettingsShell` a
        // `.constant("general")` instead would leave the window permanently on
        // General while `theWindowOpensOnThePageThatWasStored` — which reads the
        // model, not the render — still passed.
        //
        // The read direction only. Nothing here can prove a *click* on a nav row
        // reaches `model.selectedPage`, for the same reason
        // `PanelBarTests.tappingEachButtonCallsItsOwnClosureAndNotTheOther` records:
        // no ViewInspector-style dependency, and this project takes none.
        let model = SettingsWindowModel(selectedPage: "notifications")
        let root = try rasterise(SettingsRootView(model: model)
            .frame(width: SettingsWindowController.contentSize.width, height: 400))
        let headingChip = (x: Int(SettingsSidebar.width) + 24, y: 20, side: 24)
        #expect(count(in: root, box: headingChip, near: SettingsPage.all[2].chip) > 300,
                "the root view is not showing the model's page")
    }

    @Test @MainActor func anUnknownSelectionStillDrawsAPane() throws {
        // `SettingsWindowController` clamps, but the shell must not depend on that
        // to avoid an empty content area — the same two-layer reasoning
        // `anUnknownStoredPageStillOpensSomething` records one file over.
        let shell = try rasterise(SettingsShell(selection: .constant("kitchen-sink"))
            .frame(width: SettingsWindowController.contentSize.width, height: 400))
        let headingChip = (x: Int(SettingsSidebar.width) + 24, y: 20, side: 24)
        #expect(count(in: shell, box: headingChip, near: SettingsPage.all[0].chip) > 300,
                "an unknown key left the content area empty")
    }

    // MARK: - helpers

    /// `pixelCount(near:)` restricted to a square box. See
    /// `eachPaneWearsItsOwnPagesChipAndNoOthers` on why a chip has to be counted
    /// where it is rather than merely somewhere.
    private func count(in raster: Raster, box: (x: Int, y: Int, side: Int),
                       near colour: RGBA, tolerance: Int = 3) -> Int {
        var n = 0
        for y in box.y..<(box.y + box.side) where y >= 0 && y < raster.height {
            for x in box.x..<(box.x + box.side) where x >= 0 && x < raster.width {
                if near(raster[x, y], colour, tolerance: tolerance) { n += 1 }
            }
        }
        return n
    }

    private func near(_ p: Raster.Pixel, _ colour: RGBA, tolerance: Int = 6) -> Bool {
        let target = Raster.Pixel(colour)
        return abs(Int(p.r) - Int(target.r)) <= tolerance
            && abs(Int(p.g) - Int(target.g)) <= tolerance
            && abs(Int(p.b) - Int(target.b)) <= tolerance
    }
}

/// Writes the sidebar, the four panes and the whole shell as PNGs, for the
/// prototype diff this task exists to do — `settings.html` is 640 lines and no
/// plan before this one ever compared anything to it.
///
/// Env-gated exactly like `contactSheet`/`filmstrip`: it asserts nothing, and a
/// run without `VIBECAT_SETTINGS_SHEET` set does no work at all.
///
///     VIBECAT_SETTINGS_SHEET=/tmp/settings swift test --filter settingsSheet
@Test @MainActor func settingsSheet() throws {
    guard let prefix = ProcessInfo.processInfo.environment["VIBECAT_SETTINGS_SHEET"] else { return }
    let size = SettingsWindowController.contentSize
    for page in SettingsPage.all {
        let shell = try rasterise(SettingsShell(selection: .constant(page.key))
            .frame(width: size.width, height: size.height), scale: 2)
        shell.writePNG(to: "\(prefix)-\(page.key).png")
    }
    let chips = try rasterise(
        HStack(spacing: 12) { ForEach(SettingsPage.all) { SettingsChip(page: $0) } }
            .padding(12)
            .background(Color(SettingsPalette.pane)),
        scale: 8)
    chips.writePNG(to: "\(prefix)-chips.png")
}
