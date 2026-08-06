import Testing
import Foundation
import SwiftUI
@testable import VibeCatUI

/// The drawer's footer: `island-motion.html:516-530`'s `.panelbar`, a mute
/// button and a settings button pinned to the trailing edge inside the 44pt
/// `DrawerView` already reserves for them.
///
/// A few helper names this plan's own draft guessed at don't exist in
/// `Raster.swift` — `opaquePixelCount` does, but `Raster.rasterise(_:size:)`
/// and `isBlank(inColumns:)` do not. The free function `rasterise(_:scale:)`
/// takes no size (a caller applies `.frame(width:height:)` first, the
/// convention every other golden test in this suite already uses — see
/// `SettingsPaletteTests.anOnSwitchDrawsSystemBlueAndAnOffSwitchDoesNot`), and
/// there is no ready-made column-blankness check, so `isBlank(inColumns:)`
/// below is a small local helper in the same spirit as
/// `IslandGoldenTests.paintedColumns` — a test-file-local reading over
/// `Raster.pixels`, not a new addition to `Raster.swift` itself.
@Suite("Panel bar")
struct PanelBarTests {
    /// Whether every pixel in the given column range is fully transparent,
    /// across every row **except row 0**. Named the way the plan's draft
    /// named it; implemented against what `Raster` actually exposes
    /// (`subscript(x:y:)`, `Pixel.isTransparent`) rather than a member that
    /// doesn't exist on it.
    ///
    /// Row 0 is excluded on purpose, because it is `.panelbar`'s `border-top`
    /// and not the buttons this helper's callers are looking for.
    ///
    /// **The reason recorded here for three plans was wrong, and the
    /// correction is worth keeping.** It said `island-motion.html:182`'s
    /// `.panelbar{border-top:1px solid var(--hairline)}` was a *full-width*
    /// divider, "measured during development: that hairline alone paints
    /// every column at `y == 0`". The measurement was of *our* render, which
    /// did draw it full-width; the prototype does not. `island-motion.html:181`
    /// is `.panelbar{position:absolute;left:18px;right:18px;…}`, so the border
    /// spans `width − 36`. `PanelBar` now insets it to match
    /// (`theHairlineIsInsetTheWayThePrototypesPanelbarIs` pins that), and this
    /// comment says what the CSS says rather than what our own bug said.
    ///
    /// The exclusion itself survives the correction, which is the part the
    /// final review predicted the other way: an 18pt-inset rule still paints
    /// columns 18 through `width − 18` at `y == 0`, so the plan's draft check
    /// (`isBlank(inColumns: 0..<100)` over every row) could not have passed
    /// against a prototype-faithful hairline either. Only the first 18 columns
    /// are ever blank in that row, and
    /// `bothButtonsSitAgainstTheTrailingEdge` checks exactly those.
    static func isBlank(_ raster: Raster, inColumns columns: Range<Int>) -> Bool {
        for x in columns where x >= 0 && x < raster.width {
            for y in 1..<raster.height where !raster[x, y].isTransparent {
                return false
            }
        }
        return true
    }

    /// `Raster.pixelCount(near:)` matches on premultiplied RGB with no floor
    /// on alpha beyond `> 0` — which means a partially-transparent
    /// antialiased edge of one tint can land within `tolerance` of an
    /// unrelated *other* tint purely because premultiplication scales RGB
    /// down by alpha, coincidentally landing near a second, dimmer target
    /// colour. Measured: `hazeColour` (#8A93A6) edges of the gear icon read
    /// 8 pixels "near" `dimColour`, and `dimColour`-adjacent maths put 22
    /// pixels of an all-`hazeColour` render "near" `dimColour` too — both
    /// false positives from edge antialiasing, not from either icon
    /// actually drawing the other's tint. Restricting to fully opaque
    /// pixels (`a == 255`) removes the coincidence: only a shape's solid
    /// interior — never an antialiased boundary — can match, which is what
    /// "a colour only the thing under test can emit" actually requires here.
    static func fullyOpaquePixelCount(_ raster: Raster, near colour: RGBA, tolerance: Int = 6) -> Int {
        let target = Raster.Pixel(colour)
        return raster.pixels.count { p in
            p.a == 255
                && abs(Int(p.r) - Int(target.r)) <= tolerance
                && abs(Int(p.g) - Int(target.g)) <= tolerance
                && abs(Int(p.b) - Int(target.b)) <= tolerance
        }
    }

    @Test @MainActor func theMuteButtonShowsASlashOnlyWhenMuted() throws {
        // The plan's draft asserted `quiet.opaquePixelCount >
        // loud.opaquePixelCount` on the whole `PanelBar` — "the slash adds
        // ink the unmuted icon doesn't have." Measured against the actual
        // render, that premise doesn't hold: muted *hides* `wave1`/`wave2`
        // (`.pbtn[aria-pressed="true"] .wave1,.wave2{opacity:0}`,
        // `island-motion.html:196`) while showing the slash, so it is a
        // swap, not an addition — two stroked arcs disappear and one
        // appears. Measured once against the whole bar: quiet 301 opaque
        // pixels, loud 308. Reported per this project's own rule against
        // bending a test to force it green instead of reporting the
        // disagreement.
        //
        // Rasterising `MuteIcon` directly, not `PanelBar` — `#pgear` sits in
        // the same bar and is always `hazeColour` regardless of `muted`, so
        // any colour- or ink-based reading of the *whole* bar cannot
        // distinguish "the mute icon changed" from "the gear is just being
        // its usual colour". `MuteIcon` isn't `private` for exactly this.
        let size = CGSize(width: 16, height: 16)
        let quiet = try rasterise(MuteIcon(muted: true).frame(width: size.width, height: size.height))
        let loud = try rasterise(MuteIcon(muted: false).frame(width: size.width, height: size.height))

        // `.pbtn[aria-pressed="true"]{color:var(--dim)}` recolours the
        // *whole* glyph when muted — a colour only one of the two states can
        // ever emit, which is "assert a colour only the thing under test can
        // emit" rather than a total count (Global Constraints, and
        // `SettingsPaletteTests.anOnSwitchDrawsSystemBlueAndAnOffSwitchDoesNot`
        // uses the same pattern). This alone catches a tint regression but
        // — checked directly — does **not** catch "always draw the slash":
        // that mutation leaves `tint` computed correctly and only adds a
        // shape, so a second, geometry-based assertion is required below.
        #expect(Self.fullyOpaquePixelCount(quiet, near: dimColour) > 0, "muted must draw the icon in dimColour")
        #expect(Self.fullyOpaquePixelCount(loud, near: hazeColour) > 0, "unmuted must draw the icon in hazeColour")

        // A geometry-based check, derived empirically rather than by hand
        // trigonometry (an earlier draft of this test hand-computed a point
        // on the slash's line and got it wrong — it landed inside `wave1`'s
        // own stroke, which this measured-not-guessed approach cannot):
        // render each of the four component shapes alone, at the same 16×16
        // size `MuteIcon` uses, and find pixels the slash paints that
        // neither the speaker nor either wave arc ever does. Any such pixel
        // is, by construction, one only `SlashShape` can paint — exactly
        // "assert a colour [here, a location] only the thing under test can
        // emit".
        func paintedPixels(_ view: some View) throws -> Set<Int> {
            let r = try rasterise(view.frame(width: size.width, height: size.height))
            var set = Set<Int>()
            for y in 0..<r.height {
                for x in 0..<r.width where !r[x, y].isTransparent {
                    set.insert(y * r.width + x)
                }
            }
            return set
        }
        let speakerOnly = try paintedPixels(SpeakerShape().fill(Color.white))
        let wave1Only = try paintedPixels(Wave1Shape().stroke(Color.white, style: StrokeStyle(lineWidth: 1.7, lineCap: .round)))
        let wave2Only = try paintedPixels(Wave2Shape().stroke(Color.white, style: StrokeStyle(lineWidth: 1.7, lineCap: .round)))
        let slashOnly = try paintedPixels(SlashShape().stroke(Color.white, style: StrokeStyle(lineWidth: 1.9, lineCap: .round)))
        let slashExclusive = slashOnly.subtracting(speakerOnly).subtracting(wave1Only).subtracting(wave2Only)
        let slashPoint = try #require(slashExclusive.first,
            "the slash must paint at least one pixel neither the speaker nor either wave arc ever does")

        func painted(_ r: Raster, at index: Int) -> Bool {
            !r[index % r.width, index / r.width].isTransparent
        }
        #expect(painted(quiet, at: slashPoint), "the slash-exclusive pixel must be painted when muted")
        #expect(!painted(loud, at: slashPoint), "the slash-exclusive pixel must be blank when unmuted")
    }

    @Test @MainActor func bothButtonsSitAgainstTheTrailingEdge() throws {
        // The prototype's `.panelbar` opens with a `<span class="spacer">`,
        // so both buttons are pushed right. A leading-aligned bar would put
        // a gear where the session list's own content begins.
        let bar = try rasterise(
            PanelBar(muted: false, onToggleMute: {}, onOpenSettings: {})
                .frame(width: 200, height: 44))
        #expect(Self.isBlank(bar, inColumns: 0..<100), "the leading half of the bar must be empty")
        #expect(!Self.isBlank(bar, inColumns: 120..<200), "both buttons belong at the trailing edge")
        // The one range that is blank in *every* row, `border-top` included:
        // outside `.panelbar`'s own 18pt inset. Checked here rather than through
        // `isBlank`, whose whole job is to skip row 0.
        for y in 0..<bar.height {
            for x in 0..<17 {
                #expect(bar[x, y].isTransparent, "something is drawn at (\(x),\(y)), outside the 18pt inset")
            }
        }
    }

    @Test @MainActor func theHairlineIsInsetTheWayThePrototypesPanelbarIs() throws {
        // `island-motion.html:181-183`:
        //
        //   .panelbar{ position:absolute;left:18px;right:18px;bottom:9px;height:28px;
        //              …border-top:1px solid var(--hairline);padding-top:7px; }
        //
        // `border-top` is on an element inset 18px on both sides, so the rule spans
        // `width − 36`. This file drew it full-width for three plans and recorded
        // the divergence as a measured *fact about the prototype* — the premise
        // that then justified skipping row 0 in `isBlank` and reworking four
        // `DrawerGoldenTests`. Both of those accommodations turn out to be
        // necessary anyway (see `isBlank`'s own comment), but only this test makes
        // the inset itself something that can fail.
        //
        // Asserted at the ends and the middle rather than column by column: the
        // failure being caught is "the rule runs the whole width", and one blank
        // pixel inside the inset is enough to catch it, while a painted pixel just
        // inside each end is what rules out the opposite over-correction of
        // insetting too far.
        let width = 200
        let bar = try rasterise(
            PanelBar(muted: false, onToggleMute: {}, onOpenSettings: {})
                .frame(width: CGFloat(width), height: 44))
        #expect(bar[0, 0].isTransparent, "the rule reaches the drawer's own leading edge")
        #expect(bar[17, 0].isTransparent, "the rule starts before the 18pt inset")
        #expect(bar[width - 1, 0].isTransparent, "the rule reaches the drawer's own trailing edge")
        #expect(bar[width - 18, 0].isTransparent, "the rule runs past the trailing 18pt inset")
        #expect(!bar[18, 0].isTransparent, "the rule does not start at the 18pt inset")
        #expect(!bar[width / 2, 0].isTransparent, "no rule is drawn at all")
        #expect(!bar[width - 19, 0].isTransparent, "the rule stops short of the trailing inset")
    }

    @Test @MainActor func tappingEachButtonCallsItsOwnClosureAndNotTheOther() {
        // The plan's own draft left this test off `@MainActor`. `PanelBar`
        // is a `View`, and Swift 6 infers main-actor isolation on its
        // memberwise `init` from that conformance — constructing one from a
        // plain `@Test func` is a compile error
        // (`sending value of non-Sendable type '() -> ()' ... to main
        // actor-isolated initializer`), not a runtime one. Reported here
        // rather than silently added, per the plan's own "report a
        // disagreement, don't just bend the code" rule.
        //
        // **Mutation-verify finding, reported rather than patched around**:
        // the plan predicted mutation 3 — "wire the gear's action to
        // `onToggleMute`" in `body` — would fail this test. It does not,
        // and cannot, as either this test or the plan's own draft of it is
        // written. `toggleMuteForTesting()`/`openSettingsForTesting()` call
        // the *stored closures* directly (`onToggleMute()`/
        // `onOpenSettings()`), never touching `body`'s `Button(action:)`
        // wiring at all — they prove `PanelBar` retains the closures it was
        // constructed with, which a struct's memberwise storage cannot get
        // wrong on its own. The actual risk this test's own name describes
        // — the gear's `Button` forwarding to the *wrong* stored closure —
        // lives entirely in `body`, and this project's own conventions
        // (`ChoiceRow.onTap` is a single closure forwarded once, with
        // nothing to swap it against; `QuestionFace.tapped(_:)` is called
        // directly rather than dispatched through a rendered gesture) have
        // no precedent for simulating a real click on a rendered `Button`
        // headlessly, and this project takes no ViewInspector-style
        // dependency that could read a closure back out of a view. I could
        // not find a way to catch this specific miswiring without one of
        // those two things. Left as a known, reported gap rather than
        // silently declaring the mutation caught.
        var muteCalls = 0, settingsCalls = 0
        let bar = PanelBar(muted: false, onToggleMute: { muteCalls += 1 }, onOpenSettings: { settingsCalls += 1 })
        bar.toggleMuteForTesting()
        #expect((muteCalls, settingsCalls) == (1, 0))
        bar.openSettingsForTesting()
        #expect((muteCalls, settingsCalls) == (1, 1))
    }

    @Test @MainActor func theReservedFooterIsNoLongerEmpty() throws {
        // DrawerView reserved 44pt for this in Plan 4 and filled it with
        // Color.clear. If someone reverts the wiring, the bar's own tests
        // above still pass and only this one notices.
        //
        // Renders the **real** `DrawerView`, not a static helper the test
        // calls directly — an earlier draft of this test rasterised
        // `DrawerView.footerProbeForTesting(muted:)`, a static that called
        // the same code `body` did *in theory*, but which the test invoked
        // independently of `body` itself. Measured: reverting `body`'s own
        // line back to `Color.clear` left that version of this test green,
        // because the probe never went through `body` at all. Reported per
        // this plan's rule against a mutation that stays green, and fixed
        // by testing the actual rendered drawer instead.
        //
        // `opaquePixelCount > 0` cannot be the assertion here either:
        // `IslandShape`'s ground fill (`islandGroundColour`) is opaque
        // everywhere `body` draws, including straight through a
        // `Color.clear` placeholder, so that count would be positive either
        // way. The real discriminator is colour: the footer strip of a
        // correct render carries the bar's own ink (the hairline, the
        // icons) somewhere other than `islandGroundColour`; an empty
        // reservation carries only the ground fill, unbroken.
        let width: CGFloat = 388
        let drawn = try rasterise(
            DrawerView(question: nil, sessions: [], accent: IslandState.waiting.accent, width: width))
        let footerTop = drawn.height - Int(DrawerView.footerHeight)
        try #require(footerTop >= 0, "the drawer rendered shorter than the footer reservation")
        var sawNonGroundInk = false
        outer: for y in footerTop..<drawn.height {
            for x in 0..<drawn.width {
                let p = drawn[x, y]
                // Skip partial-alpha pixels entirely rather than treating
                // them as "not ground colour" — see `isNear`'s own doc
                // comment for why the rounded bottom corners make that the
                // wrong call.
                guard p.a == 255 else { continue }
                if !Self.isNear(p, islandGroundColour) {
                    sawNonGroundInk = true
                    break outer
                }
            }
        }
        #expect(sawNonGroundInk, "the reserved footer's own strip is unbroken islandGroundColour — still empty")
    }

    /// Whether a rendered pixel's RGB is within a small tolerance of
    /// `colour`. Callers must gate on `pixel.a == 255` themselves first —
    /// see `theReservedFooterIsNoLongerEmpty`'s own comment: `IslandShape`'s
    /// bottom corners are rounded, so the footer strip's left/right edges
    /// antialias against full transparency there, and treating a partial-
    /// alpha corner pixel's premultiplied RGB as either "near" or "not near"
    /// a target is meaningless — it must be skipped, not classified.
    private static func isNear(_ pixel: Raster.Pixel, _ colour: RGBA, tolerance: Int = 6) -> Bool {
        let target = Raster.Pixel(colour)
        return abs(Int(pixel.r) - Int(target.r)) <= tolerance
            && abs(Int(pixel.g) - Int(target.g)) <= tolerance
            && abs(Int(pixel.b) - Int(target.b)) <= tolerance
    }
}

/// **The Settings glyph is a gear, and it was not until the owner said so.**
///
/// `island-motion.html:526-527` draws `#pgear` as an `r=3.1` circle plus eight *detached*
/// radial ticks — the classic brightness glyph. We reproduced it faithfully, and the
/// owner opened the running app and called it a brightness icon without having seen the
/// SVG. §10.2's rule is that the control carries the meaning, so a Settings button that
/// reads as "adjust brightness" has lost its only job; the divergence is recorded on
/// `GearRingShape`.
///
/// **Nothing tested this shape before**, which is how a rays-not-teeth glyph survived
/// four plans. What makes teeth teeth is the ring they attach to, so that is the
/// assertion: the ring must paint ink at the radius where every tooth ends. Derived from
/// the path data rather than eyeballed — the ticks run `r 8.80 → 6.50`, so `6.5` is the
/// tooth root and a point on it must be inked.
@MainActor @Test func theSettingsGlyphHasARingItsTeethAttachTo() throws {
    let side: CGFloat = 16, scale: CGFloat = 8
    let ring = try rasterise(GearRingShape().stroke(Color.white, lineWidth: 1.7)
        .frame(width: side, height: side), scale: scale)

    // The tooth root, in the SVG's 24-unit space mapped into the raster.
    let unit = Double(ring.width) / 24
    let cx = 12.0 * unit, cy = 12.0 * unit
    func inked(atRadius r: Double) -> Bool {
        // Straight up from the centre, where a tooth also sits — so this cannot pass on
        // some unrelated stroke elsewhere in the glyph.
        let y = Int((cy - r * unit).rounded())
        let x = Int(cx.rounded())
        for dx in -2...2 where ring[min(max(0, x + dx), ring.width - 1), min(max(0, y), ring.height - 1)].a > 128 {
            return true
        }
        return false
    }
    #expect(inked(atRadius: 6.5), "no ring at the tooth root — the teeth are detached rays, not a gear")
    #expect(inked(atRadius: 3.1), "the hub the prototype does specify is missing")
    #expect(!inked(atRadius: 5.0), "ink between the hub and the tooth root — the ring is filled, not stroked")
}
