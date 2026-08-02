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

/// The drawer is the island's, so it wears the island's colour (§4.3).
@MainActor @Test func theDrawerWearsTheStatesAccent() throws {
    for state in [IslandState.waiting, .failed] {
        let raster = try rasterise(DrawerView(question: QuestionModel(event: threeChoices(multi: false)),
                                              accent: state.accent, width: 420))
        #expect(raster.pixelCount(near: state.accent) > 0, "\(state): no accent anywhere in the drawer")
    }
}
