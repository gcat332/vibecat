import CoreGraphics
import Foundation
import SwiftUI
import Testing
import VibeCatCore
@testable import VibeCatUI

/// §10.1/§10.2's rules are visual, so they get rendered assertions rather
/// than read counters — `DrawerView` is rasterised directly here, the same
/// way `IslandGoldenTests` rasterises `IslandBody`/`IslandView`.
///
/// Two lessons this plan already paid for, both from `IslandGoldenTests`:
/// a colour-*count* assertion is nearly worthless (a render with one sprite
/// emptied still produced eighty-odd colours from everything else and
/// passed), and a scene with only one possible non-transparent colour cannot
/// fail a "nothing unexpected" check either way. Every assertion below either
/// targets a colour only the thing under test can produce (the accent, which
/// nothing else in an otherwise white-on-ground drawer emits), or compares
/// two renders that differ in exactly one input.

/// Three plain choices, single- or multi-select depending on the caller —
/// shared by every test in this file that only cares about the control
/// distinction, not about any one label. Deliberately not a destructive body
/// (see `DestructiveGuardTests`'s own warning about this): a body matching
/// `DestructiveGuard` would make `allow` need confirmation and silently
/// change what these renders show.
private func threeChoices(multi: Bool) -> VibeEvent {
    VibeEvent(id: "q", cli: "claude-code", kind: .permission, session: "s", cwd: "/tmp/proj",
              title: "Bash command", body: "pnpm install",
              choices: [Choice(id: "allow", label: "Allow once"),
                        Choice(id: "always", label: "Always allow"),
                        Choice(id: "deny", label: "Deny")],
              multi: multi, wantsReply: true)
}

/// A plain single-select question, for the recommended-row test. Nothing in
/// `VibeEvent`/`Choice` marks a choice as "recommended" — the field does not
/// exist anywhere on this branch. `QuestionFace` renders row 0 as the
/// recommended one (see its own doc comment on that convention), so this
/// fixture only needs "allow" listed first, matching every other fixture in
/// this codebase.
private func recommendedEvent() -> VibeEvent {
    VibeEvent(id: "q", cli: "claude-code", kind: .permission, session: "s", cwd: "/tmp/proj",
              title: "Bash command", body: "pnpm install",
              choices: [Choice(id: "allow", label: "Allow once"),
                        Choice(id: "deny", label: "Deny")],
              wantsReply: true)
}

/// Horizontal bands of drawn content, separated by bands of pure ground.
/// Specific to "this layout is a vertical list of rows" — belongs beside the
/// tests that need it rather than in `Raster`, which knows nothing about any
/// particular layout. A transparent pixel (outside the drawer's own rounded
/// corners) counts as "nothing drawn" here too, the same as ground itself.
private func contentBands(_ raster: Raster) -> [Range<Int>] {
    func isGroundOrEmpty(_ p: Raster.Pixel) -> Bool {
        guard p.a > 0 else { return true }
        return abs(Int(p.r) - 5) <= 6 && abs(Int(p.g) - 7) <= 6 && abs(Int(p.b) - 11) <= 6
    }
    var bands: [Range<Int>] = []
    var start: Int?
    for y in 0..<raster.height {
        let hasContent = (0..<raster.width).contains { !isGroundOrEmpty(raster[$0, y]) }
        if hasContent {
            if start == nil { start = y }
        } else if let s = start {
            bands.append(s..<y)
            start = nil
        }
    }
    if let s = start { bands.append(s..<raster.height) }
    return bands
}

/// §10.1: "Choices run top to bottom, one per row, so a label like 'Allow all
/// pnpm commands in ~/dev/api for this session' stays readable instead of
/// being truncated." Real permission prompts have labels this long, so the
/// test uses one.
@MainActor @Test func longLabelsGetTheirOwnRowAndAreNotTruncated() throws {
    let long = "Allow all pnpm commands in ~/dev/api for this session"
    let e = VibeEvent(id: "q", cli: "claude-code", kind: .permission, session: "s", cwd: "/tmp/proj",
                      title: "Bash command", body: "pnpm install",
                      choices: [Choice(id: "allow", label: "Allow once"),
                                Choice(id: "always", label: long),
                                Choice(id: "deny", label: "Deny")],
                      wantsReply: true)
    let m = QuestionModel(event: e)
    let raster = try rasterise(DrawerView(question: m, accent: IslandState.waiting.accent,
                                          width: 420))
    // Rows are horizontal bands of content separated by bands of pure ground.
    // Three choices means three bands.
    #expect(contentBands(raster).count >= 3,
            "expected one band per choice; found \(contentBands(raster).count)")
}

/// The test above passes for a reason unrelated to wrapping. Measured
/// directly: at this drawer's own 420pt width, the brief's own 54-character
/// example ("Allow all pnpm commands in ~/dev/api for this session") fits
/// entirely on *one* line inside `ChoiceRow`'s available width (338pt after
/// the row's own padding and badge) — rendered height 16pt either with
/// `.fixedSize` present or replaced by `.lineLimit(1)`, byte-identical
/// either way. So `contentBands(...).count >= 3` is really only proving
/// "three rows exist," which was never in doubt and says nothing about
/// truncation — it would pass exactly as well with `.fixedSize` deleted
/// outright. This exercises the actual claim with a label long enough to
/// need a second line at this width (confirmed: 64pt wrapped vs. 36pt
/// truncated to one, rendering `ChoiceRow` directly rather than parsing
/// bands out of the whole drawer, which is more direct and does not depend
/// on `contentBands`'s row-scanning heuristic agreeing with itself).
@MainActor @Test func aLabelTooLongForOneLineActuallyWrapsRatherThanTruncating() throws {
    let reallyLong = "Allow all pnpm commands in ~/dev/api and ~/dev/web and ~/dev/mobile " +
                     "for this entire session, including postinstall scripts"
    let accent = Color(IslandState.waiting.accent)
    // 420 (drawer width) − 32 (QuestionFace's own horizontal padding) is the
    // width a row inside it actually receives.
    let rowWidth: CGFloat = 420 - 32

    let short = try rasterise(ChoiceRow(choice: Choice(id: "deny", label: "Deny"), index: 0,
                                        isMulti: false, isSelected: false,
                                        isRecommended: false, accent: accent)
        .frame(width: rowWidth))
    let long = try rasterise(ChoiceRow(choice: Choice(id: "x", label: reallyLong), index: 0,
                                       isMulti: false, isSelected: false,
                                       isRecommended: false, accent: accent)
        .frame(width: rowWidth))
    #expect(long.height > short.height + 20,
            "a label needing 3 lines rendered only \(long.height)pt tall against a 1-line row's \(short.height)pt — it looks truncated, not wrapped")
}

/// §10.1: "The recommended answer is tinted, not filled — a wide block of
/// solid colour shouts." A filled row is a wide run of accent pixels; a tinted
/// one is not.
@MainActor @Test func theRecommendedRowIsTintedRatherThanFilled() throws {
    let m = QuestionModel(event: recommendedEvent())
    let raster = try rasterise(DrawerView(question: m, accent: IslandState.waiting.accent,
                                          width: 420))
    let accentPixels = raster.pixelCount(near: IslandState.waiting.accent)
    let total = raster.opaquePixelCount
    #expect(Double(accentPixels) / Double(total) < 0.15,
            "the recommended row is \(accentPixels * 100 / total)% solid accent — that is a fill, not a tint")
    #expect(accentPixels > 0, "the recommended row carries no accent at all")
}

/// The test above is the brief's own, verbatim, and it passes — but its 0.15
/// threshold does not actually catch the regression its own doc comment
/// describes. Measured directly: making the recommended row's background a
/// fully solid `.fill(accent)` (exactly the "wide block of solid colour"
/// §10.1 forbids) produces a ratio of ~0.111 against this fixture's own
/// layout — under 0.15, so that test still passes with the rule broken. A
/// single row is a small enough fraction of the whole drawer (title, body,
/// three rows, 44pt of unclaimed footer) that even a 100%-opacity fill on
/// one row never reaches 15% of the total. The real, tinted implementation
/// measures ~0.008 here — nearly a 14x gap below the mutant's ~0.111 — so
/// 0.03 is what actually separates "tinted" from "filled" for this layout,
/// where 0.15 does not.
@MainActor @Test func theRecommendedRowsTintDoesNotApproachASolidFill() throws {
    let m = QuestionModel(event: recommendedEvent())
    let raster = try rasterise(DrawerView(question: m, accent: IslandState.waiting.accent,
                                          width: 420))
    let ratio = Double(raster.pixelCount(near: IslandState.waiting.accent)) / Double(raster.opaquePixelCount)
    #expect(ratio < 0.03,
            "recommended-row accent covers \(ratio * 100)% of the drawer — a solid fill on this fixture measures ~11%, so this is too close to be a tint")
}

/// §10.2: "a checkbox instead of a number badge. A number badge means the
/// click is the answer; a checkbox means it is not." The two must not render
/// the same.
@MainActor @Test func multiSelectRowsDoNotLookLikeSingleSelectRows() throws {
    let single = try rasterise(DrawerView(question: QuestionModel(event: threeChoices(multi: false)),
                                          accent: IslandState.waiting.accent, width: 420))
    let multi = try rasterise(DrawerView(question: QuestionModel(event: threeChoices(multi: true)),
                                         accent: IslandState.waiting.accent, width: 420))
    #expect(single.differingPixelCount(from: multi) > 200,
            "single and multi select rendered near-identically — the control is not carrying the distinction")
}

/// §10.2: "Send is disabled at zero." Disabled has to look disabled.
@MainActor @Test func sendLooksDifferentWhenItCannotBePressed() throws {
    let m = QuestionModel(event: threeChoices(multi: true))
    let dead = try rasterise(DrawerView(question: m, accent: IslandState.waiting.accent, width: 420))
    m.toggle("allow")
    let live = try rasterise(DrawerView(question: m, accent: IslandState.waiting.accent, width: 420))
    #expect(dead.differingPixelCount(from: live) > 50)
}

/// The test above, on its own, is nearly worthless in exactly the shape the
/// brief itself warns about: `m.toggle("allow")` also fills in that row's own
/// checkbox, which alone moves >50 pixels — confirmed by hard-coding Send's
/// fill/label to always read as "enabled" and re-running
/// `sendLooksDifferentWhenItCannotBePressed`: it still passed, because it
/// never isolates Send from the row that was actually toggled. This test
/// does: measured directly, toggling one checkbox with Send's own look
/// frozen contributes 278 accent pixels on its own (the checkbox fill), while
/// Send correctly reacting contributes 1870 — so 800 cleanly separates "Send
/// changed" from "only the row I clicked changed."
@MainActor @Test func sendItselfGainsASolidAccentBlockOnlyWhenEnabled() throws {
    let m = QuestionModel(event: threeChoices(multi: true))
    let dead = try rasterise(DrawerView(question: m, accent: IslandState.waiting.accent, width: 420))
    m.toggle("allow")
    let live = try rasterise(DrawerView(question: m, accent: IslandState.waiting.accent, width: 420))
    let deadAccent = dead.pixelCount(near: IslandState.waiting.accent)
    let liveAccent = live.pixelCount(near: IslandState.waiting.accent)
    #expect(liveAccent - deadAccent > 800,
            "enabling Send only added \(liveAccent - deadAccent) accent pixels, close to the ~278 a ticked checkbox contributes on its own — Send's own fill may not be reacting to canSend")
}

/// Caught only by Step 5's contact sheet, not by any test above: picking a
/// *non*-recommended single-select row painted nothing at all. `isSelected`
/// reached `ChoiceRow` but the single-select branch of its control never
/// read it, so the badge for a picked row and an unpicked one were pixel-
/// identical — confirmed directly, before this was fixed, by rasterising
/// before and after `pick("deny")` (index 2, not the recommended row 0) and
/// finding zero differing pixels. Every other test in this file only ever
/// picks or leaves alone the recommended row itself, where the tint already
/// changes the render for an unrelated reason, which is exactly how this
/// stayed invisible.
@MainActor @Test func pickingAnyRowMakesItVisiblyTheChosenOneNotJustTheRecommendedOne() throws {
    let m = QuestionModel(event: threeChoices(multi: false))
    let before = try rasterise(DrawerView(question: m, accent: IslandState.waiting.accent, width: 420))
    m.pick("deny")
    let after = try rasterise(DrawerView(question: m, accent: IslandState.waiting.accent, width: 420))
    #expect(before.differingPixelCount(from: after) > 50,
            "picking \"deny\" (not the recommended row) changed nothing — a single-select pick is invisible unless it lands on row 0")
}

/// The width every test above uses (420) is wider than the drawer is ever
/// actually asked to render at — `IslandView` passes `model.frames.body
/// .width`, and this checks the reservation at that real width instead.
///
/// Only a fully-opaque, non-ground pixel counts as real content: a
/// partially-transparent one is the shape's own rounded-bottom antialiasing
/// (which sits inside this same 44pt band), stored premultiplied, so its RGB
/// no longer reads as raw ground even where the notional colour is ground —
/// the same trap `contentBands` above sidesteps by treating any non-opaque
/// pixel as "nothing drawn," but this needs the sharper opaque-only test
/// because it is measuring a boundary in pixels, not just counting bands.
private func footerMargin(_ raster: Raster, footerHeight: Int) -> Int {
    func isRealContent(_ p: Raster.Pixel) -> Bool {
        guard p.a == 255 else { return false }
        return !(abs(Int(p.r) - 5) <= 6 && abs(Int(p.g) - 7) <= 6 && abs(Int(p.b) - 11) <= 6)
    }
    let boundary = raster.height - footerHeight
    for y in stride(from: raster.height - 1, through: 0, by: -1) {
        if (0..<raster.width).contains(where: { isRealContent(raster[$0, y]) }) {
            return boundary - (y + 1)
        }
    }
    return footerHeight
}

/// The single-select fixture likeliest to run the footer reservation close:
/// a long label that wraps (§10.1's own example, reused from the brief's
/// tests above) alongside two short ones, plus `Other…` — four rows total
/// against `.question`'s 288pt budget.
private func tightestPackingSingleSelect() -> VibeEvent {
    VibeEvent(id: "q", cli: "claude-code", kind: .permission, session: "s", cwd: "/tmp/proj",
              title: "Bash command", body: "pnpm install",
              choices: [Choice(id: "allow", label: "Allow once"),
                        Choice(id: "always", label: "Allow all pnpm commands in ~/dev/api for this session"),
                        Choice(id: "deny", label: "Deny")],
              wantsReply: true)
}

/// §6.4's reservation, checked at the width `IslandView` actually passes —
/// one real session, not hovering, on the same `mbp14` fixture every
/// geometry test in this suite already fixes on (273.1pt, computed through
/// the real `IslandGeometry`/`IslandModel` pipeline rather than a literal
/// that could drift from it as either changes).
///
/// Measured: this holds with only 6pt of margin, not a comfortable buffer —
/// worth a reviewer's attention (see the task report) — but not currently
/// broken.
@MainActor @Test func theDrawerStaysClearOfTheFooterAtTheRealisticProductionWidth() throws {
    let model = IslandModel(geometry: IslandGeometry(screen: IslandGoldenTests.mbp14),
                            motion: MotionPreference(chosen: .full, systemWantsReduced: false))
    model.state = .waiting
    model.sessionCount = 1
    let width = model.frames.body.width

    let m = QuestionModel(event: tightestPackingSingleSelect())
    let raster = try rasterise(DrawerView(question: m, accent: IslandState.waiting.accent, width: width))
    let margin = footerMargin(raster, footerHeight: 44)
    #expect(margin >= 0,
            "content reaches \(-margin)pt into the reserved footer at the realistic production width \(width)pt")
}

/// The narrowest the body ever actually is: dormant, with nothing in the
/// right flank at all. Not an arbitrary probe — `IslandGeometry
/// .minimumRightFlank` is a hard floor for the corner seam (see its own doc
/// comment), so no real configuration is narrower than this.
///
/// Pinned here rather than left to be found later: measured directly, a
/// width only 3pt narrower than this one already overflows the footer by
/// 10pt, so this is the actual edge of safety, not a margin with room in it.
/// If a future change to fonts, padding, or spacing erodes the 6pt this
/// holds by today, this is the test that goes red first.
@MainActor @Test func theDrawerStaysClearOfTheFooterAtTheNarrowestRealisticWidth() throws {
    let model = IslandModel(geometry: IslandGeometry(screen: IslandGoldenTests.mbp14),
                            motion: MotionPreference(chosen: .full, systemWantsReduced: false))
    model.state = .dormant
    model.sessionCount = 0
    let width = model.frames.body.width

    let m = QuestionModel(event: tightestPackingSingleSelect())
    let raster = try rasterise(DrawerView(question: m, accent: IslandState.waiting.accent, width: width))
    let margin = footerMargin(raster, footerHeight: 44)
    #expect(margin >= 0,
            "content reaches \(-margin)pt into the reserved footer at the narrowest real width \(width)pt")
}

/// The drawer is the island's, so it wears the island's colour (§4.3).
@MainActor @Test func theDrawerWearsTheStatesAccent() throws {
    for state in [IslandState.waiting, .failed] {
        let raster = try rasterise(DrawerView(question: QuestionModel(event: threeChoices(multi: false)),
                                              accent: state.accent, width: 420))
        #expect(raster.pixelCount(near: state.accent) > 0, "\(state): no accent anywhere in the drawer")
    }
}

// MARK: - IslandView's own composition

/// A pixel-level match for `Raster.pixelCount(near:)`'s own tolerance, kept
/// local because this needs *positions*, not a count.
private func isNear(_ p: Raster.Pixel, _ colour: RGBA, tolerance: Int = 6) -> Bool {
    guard p.a > 0 else { return false }
    let target = (Int((colour.r * 255).rounded()), Int((colour.g * 255).rounded()), Int((colour.b * 255).rounded()))
    return abs(Int(p.r) - target.0) <= tolerance
        && abs(Int(p.g) - target.1) <= tolerance
        && abs(Int(p.b) - target.2) <= tolerance
}

/// Every test above rasterises `DrawerView` directly; none renders
/// `IslandView`'s own composition — the accent and width handed down, the
/// stacking order, and the leading offset that keeps the drawer flush with
/// the collapsed silhouette above it. A wrong width property, a reversed
/// stack order, or an unaligned drawer would pass every test above and be
/// caught by nothing except eyeballing.
///
/// Confirmed directly while writing this test: before `IslandView.
/// drawerLeadingOffset` existed, rendering `IslandView` with a real
/// `IslandGeometry` and `model.question` set showed the drawer sitting
/// visibly right of the collapsed body — `VStack`'s default `.center`
/// alignment centring two children of very different widths (`IslandBody`'s
/// own outer frame is the full, wider panel; `DrawerView` is only the live
/// body's width). Screenshotted before and after in the task report.
@MainActor @Test func islandViewComposesTheDrawerFlushBelowAndAlignedWithTheCollapsedBody() throws {
    let model = IslandModel(geometry: IslandGeometry(screen: IslandGoldenTests.mbp14),
                            motion: MotionPreference(chosen: .full, systemWantsReduced: false))
    model.state = .waiting
    model.sessionCount = 1
    model.question = QuestionModel(event: recommendedEvent())

    let raster = try rasterise(IslandView(model: model))
    let drawerTop = Int(model.panelFrames.panel.height.rounded(.up))
    #expect(raster.height > drawerTop,
            "the rendered image is no taller than the collapsed panel alone — the drawer never reached the tree")

    // Ordering: the cat's own fixed facial tones (see `IslandGoldenTests`'
    // own use of them as "the sprite actually drew") belong above the
    // drawer — catching a reversed `VStack`, which the horizontal-only
    // checks below could not, since the drawer's own internal alignment
    // does not depend on where it sits vertically.
    let palette = CatPalette(accent: model.state.accent)
    for tone in [Tone.innerEar, .nose] {
        let inTop = (0..<drawerTop).contains { y in
            (0..<raster.width).contains { x in isNear(raster[x, y], palette[tone]) }
        }
        #expect(inTop, "\(tone): not found above the drawer — the collapsed body may not be on top")
    }

    // Alignment and width: the recommended row's accent border is the only
    // accent this scene draws *below* the collapsed body (its own badge and
    // session count sit above `drawerTop`, excluded by only scanning below
    // it).
    var leftmostAccent: Int?
    var rightmostAccent: Int?
    for y in drawerTop..<raster.height {
        for x in 0..<raster.width where isNear(raster[x, y], IslandState.waiting.accent) {
            leftmostAccent = min(leftmostAccent ?? x, x)
            rightmostAccent = max(rightmostAccent ?? x, x)
        }
    }
    let left = try #require(leftmostAccent,
                            "no accent pixel below the collapsed body — the drawer's accent never reached the pixels")
    let right = try #require(rightmostAccent)

    let collapsed = try rasterise(IslandBody(model: model, now: Date(timeIntervalSince1970: 1_000_000)))
    let collapsedPainted = try #require(IslandGoldenTests.paintedColumns(collapsed),
                                        "the collapsed body painted nothing")
    #expect(abs(left - collapsedPainted.first) <= 20,
            "drawer's leftmost accent at \(left) does not align with the collapsed body's own leftmost painted column at \(collapsedPainted.first) — the drawer has drifted sideways")

    #expect(Double(right - left) < model.frames.body.width,
            "accent spans \(right - left)pt — at or past the live body width \(model.frames.body.width); the drawer may be sized off the fixed panel's wider frame instead")
}

/// `IslandView.body`'s `.animation(value: drawerHeight)` can't be read back
/// from the tree a render produces — the same reason `IslandBody`'s own two
/// springs are each backed by a read-counter rather than trusted to a render
/// alone (see `IslandBody.restingWidthReadCount`'s doc comment for exactly
/// what that does and does not prove). This pins the one thing the render
/// test above cannot: that `body` actually reads `drawerHeight` while being
/// built, so the §9.1 spring has a live input to key on rather than a
/// property nothing touches.
@MainActor @Test func bodyActuallyReadsDrawerHeightWhileBeingBuilt() {
    let model = IslandModel(geometry: IslandGeometry(screen: IslandGoldenTests.mbp14),
                            motion: MotionPreference(chosen: .full, systemWantsReduced: false))
    IslandView.drawerHeightReadCount = 0
    _ = IslandView(model: model).body
    #expect(IslandView.drawerHeightReadCount > 0,
            "body never read drawerHeight — the drawer spring's input may not be wired")
}
