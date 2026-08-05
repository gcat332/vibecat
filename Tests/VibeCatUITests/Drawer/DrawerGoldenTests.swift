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

/// §10.1: `Other…`'s own control — "neither a numeral nor a checkbox... An
/// ellipsis reads as 'something else,' not 'option N.'" Restored by Plan 6.1
/// Task 5 after Plan 4 cut it; this is the render-level proof the control
/// actually reaches the pixels, the same reasoning
/// `multiSelectRowsDoNotLookLikeSingleSelectRows` above gives for why single-
/// and multi-select's own controls get a rendered comparison rather than a
/// property read. Same label text (`"X"`) on all three renders, so only the
/// *control* — badge, checkbox, or ellipsis — can be what differs.
///
/// What would have to break for this to fail: deleting `ChoiceRow`'s
/// `isOther` branch (`ChoiceRow.swift:111`) — an `isOther` row would then
/// fall into the plain single-select branch and render pixel-identical to
/// `numbered` below, which is exactly Plan 4's cut state.
@MainActor @Test func otherRowsControlLooksLikeNeitherANumberBadgeNorACheckbox() throws {
    let accent = Color(IslandState.waiting.accent)
    func row(isMulti: Bool, isOther: Bool) throws -> Raster {
        try rasterise(ChoiceRow(choice: Choice(id: "x", label: "X"), index: 0,
                                isMulti: isMulti, isSelected: false, isRecommended: false,
                                accent: accent, isOther: isOther)
            .frame(width: 300))
    }
    let numbered = try row(isMulti: false, isOther: false)
    let checkbox = try row(isMulti: true, isOther: false)
    let other = try row(isMulti: false, isOther: true)

    #expect(other.differingPixelCount(from: numbered) > 50,
            "Other…'s control rendered near-identically to a numbered badge — §10.2's 'a number badge means the click is the answer' would then wrongly apply to it")
    #expect(other.differingPixelCount(from: checkbox) > 50,
            "Other…'s control rendered near-identically to a checkbox")
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
///
/// **Plan 6.4, Task 3 update.** This function predates `PanelBar` — every
/// caller here was written when the 44pt band was still `Color.clear`, so
/// "any real content inside it at all" was an unambiguous overflow signal.
/// It no longer is: `PanelBar` now legitimately paints a hairline at the
/// band's own top row and two icons in its trailing ~74pt (`18pt` padding +
/// two `26pt` buttons + a `4pt` gap — see `PanelBar.swift`), and every one of
/// this file's four footer tests started failing the moment that content
/// existed, with no actual question-content overflow involved. So the
/// boundary row itself is skipped outright (it is *always* `PanelBar`'s
/// hairline, never question content — nothing above it can physically render
/// there without first passing through every row between), and any row
/// further into the band only counts content found in the leading columns,
/// where `PanelBar` is guaranteed blank
/// (`PanelBarTests.bothButtonsSitAgainstTheTrailingEdge` proves that
/// guarantee for the bar itself). This keeps the check meaning what it
/// always meant — does *question* content reach into the reservation — while
/// no longer confusing the reservation's own new occupant for an overflow.
///
/// **Plan 6.4 final fix.** The version of this note written above said the
/// hairline was *full-width*, and cited that as a measured fact about
/// `island-motion.html`. It was a measured fact about our own render:
/// `.panelbar` is inset `left:18px;right:18px` (`island-motion.html:181`), so
/// the rule spans `width − 36`, and `PanelBar` has been corrected to match.
/// Both accommodations survive that correction, and the final review
/// predicted they would not — so it was checked rather than assumed.
/// Measured, with the inset in place: un-skipping the boundary row puts all
/// four of these tests at `margin == -1`, because an 18pt-inset rule still
/// covers every column this helper scans; scanning the full width below the
/// boundary puts them at `margin == -30`, the icons. Neither accommodation is
/// an artefact of the divergence.
private func footerMargin(_ raster: Raster, footerHeight: Int) -> Int {
    func isRealContent(_ p: Raster.Pixel) -> Bool {
        guard p.a == 255 else { return false }
        return !(abs(Int(p.r) - 5) <= 6 && abs(Int(p.g) - 7) <= 6 && abs(Int(p.b) - 11) <= 6)
    }
    let boundary = raster.height - footerHeight
    // `PanelBar`'s own trailing footprint: 18pt padding + 26pt gear + 4pt gap
    // + 26pt mute = 74pt, plus a 10pt safety margin against measurement noise.
    let panelBarTrailingWidth = 84
    let leadingWidth = max(0, raster.width - panelBarTrailingWidth)
    for y in stride(from: raster.height - 1, through: 0, by: -1) {
        if y == boundary { continue } // PanelBar's own full-width hairline
        let scanWidth = y > boundary ? leadingWidth : raster.width
        if (0..<scanWidth).contains(where: { isRealContent(raster[$0, y]) }) {
            return boundary - (y + 1)
        }
    }
    return footerHeight
}

/// The single-select fixture likeliest to run the footer reservation close:
/// a long label that wraps (§10.1's own example, reused from the brief's
/// tests above) alongside two short ones — three rows total against
/// `.question`'s 288pt budget. Used to carry a fourth row, `Other…`; the
/// final whole-branch review cut it (see `QuestionFace.rows`'s own comment),
/// which is part of what the post-pick tests below need to clear the footer
/// at all — the other part being `destructiveQuestion`'s own confirmation
/// banner, which this non-destructive fixture never shows.
private func tightestPackingSingleSelect() -> VibeEvent {
    VibeEvent(id: "q", cli: "claude-code", kind: .permission, session: "s", cwd: "/tmp/proj",
              title: "Bash command", body: "pnpm install",
              choices: [Choice(id: "allow", label: "Allow once"),
                        Choice(id: "always", label: "Allow all pnpm commands in ~/dev/api for this session"),
                        Choice(id: "deny", label: "Deny")],
              wantsReply: true)
}

/// §6.4's reservation, checked at the width `IslandView` actually passes —
/// computed through the real `IslandGeometry`/`IslandModel` pipeline rather than a
/// literal that could drift from it as either changes.
///
/// **`model.drawerWidth`, not `model.frames.body.width` with the drawer closed,
/// since Plan 6.3 Task 1.** This read the *collapsed* width (273.1pt on the
/// `mbp14` fixture) and called it the production width, which it was only because
/// `drawerWidth` was derived from the collapsed layout — the defect §6.3's
/// 2026-08-05 correction records. The open drawer is 560pt, and this is the test
/// whose name claims to check the real one.
///
/// The narrow case is not lost with it: `theDrawerStaysClearOfTheFooterAtThe
/// NarrowestRealisticWidth` below renders the same tightest-packing question at
/// 258pt, narrower than the 273.1 this used to use, and it is where the 6pt of
/// margin measured during Plan 6.4 is still pinned.
@MainActor @Test func theDrawerStaysClearOfTheFooterAtTheRealisticProductionWidth() throws {
    let model = IslandModel(geometry: IslandGeometry(screen: IslandGoldenTests.mbp14),
                            motion: MotionPreference(chosen: .full, systemWantsReduced: false))
    model.state = .waiting
    model.sessionCount = 1
    model.question = QuestionModel(event: tightestPackingSingleSelect())
    model.drawerOpen = true
    let width = model.drawerWidth

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

/// Finding 2 of the final whole-branch review: every footer test above only
/// ever renders the *unpicked* state. The confirmation banner
/// (`QuestionFace.confirmBanner`) only appears once `needsConfirmation` is
/// true — a destructive body, picked but not yet confirmed — which none of
/// them reach. This is the exact flow Task 8's hardware verification
/// exercised end to end: `rm -rf build/`, "Allow once" picked.
private func destructiveQuestion(body: String = "rm -rf build/") -> VibeEvent {
    VibeEvent(id: "q", cli: "claude-code", kind: .permission, session: "s", cwd: "/tmp/proj",
              title: "Bash command", body: body,
              choices: [Choice(id: "allow", label: "Allow once"),
                        Choice(id: "always", label: "Allow all Bash calls this session"),
                        Choice(id: "deny", label: "Deny")],
              wantsReply: true)
}

/// Measured before this fix, at this exact production width: +6pt margin
/// with nothing picked (what `theDrawerStaysClearOfTheFooterAtThe
/// RealisticProductionWidth` above already covers) collapsed to -37pt — 37
/// of the reserved 44pt consumed — the instant "Allow once" is picked and
/// the confirmation banner appears below the rows. Deleting the inert
/// `Other…` row moved this to +7pt.
///
/// **Plan 6.1 Task 5 update.** Restoring `Other…` reopened exactly this hole:
/// with the row back and `QuestionFace.rows`' gap corrected to the
/// prototype's `5px` (`island-motion.html:301`, was `8`), this fixture still
/// measured -27pt — not a tight margin, `PanelBar`'s mute/gear icons pushed
/// entirely out of frame (screenshotted in the task report). The fix is
/// `QuestionFace.rows` gating `Other…` on `!question.needsConfirmation` as
/// well as `!question.isMulti`: this test is that decision's own regression
/// guard. Mutation-verified directly — dropping that guard (showing `Other…`
/// unconditionally alongside the banner again) reproduces the -27pt failure.
@MainActor @Test func theDrawerStaysClearOfTheFooterAfterPickingADestructiveAnswerAtProductionWidth() throws {
    let model = IslandModel(geometry: IslandGeometry(screen: IslandGoldenTests.mbp14),
                            motion: MotionPreference(chosen: .full, systemWantsReduced: false))
    model.state = .waiting
    model.sessionCount = 1
    let width = model.frames.body.width

    let m = QuestionModel(event: destructiveQuestion())
    m.pick("allow")
    #expect(m.needsConfirmation,
            "setup: picking a permissive choice on a destructive body must need confirmation")

    let raster = try rasterise(DrawerView(question: m, accent: IslandState.waiting.accent, width: width))
    let margin = footerMargin(raster, footerHeight: 44)
    #expect(margin >= 0,
            "the confirmation banner reaches \(-margin)pt into the reserved footer after picking, at production width \(width)pt")
}

/// The same flow with a command long enough to actually wrap — measured
/// before this fix, this reached row 287 of a 288pt-tall drawer: the banner
/// was sliced mid-line, not merely tight against the footer.
/// `QuestionFace.header`'s command `Text` had no `lineLimit`, so an unusually
/// long command could grow the header without bound and push everything
/// below it — rows, banner, footer — down with it. A 2-line cap alone was
/// measured still 8pt short at this width with three rows and a banner
/// present; `QuestionFace.header`'s own comment records why 1 line is what
/// actually clears it.
@MainActor @Test func theDrawerStaysClearOfTheFooterWithALongCommandBodyAfterPicking() throws {
    let model = IslandModel(geometry: IslandGeometry(screen: IslandGoldenTests.mbp14),
                            motion: MotionPreference(chosen: .full, systemWantsReduced: false))
    model.state = .waiting
    model.sessionCount = 1
    let width = model.frames.body.width

    let longBody = "rm -rf /Users/dev/projects/vibecat-worktrees/feat-drawer-and-answering/build/intermediates/output"
    #expect(longBody.count > 80, "setup: the body must be long enough to actually wrap onto several lines")
    let m = QuestionModel(event: destructiveQuestion(body: longBody))
    m.pick("allow")
    #expect(m.needsConfirmation,
            "setup: picking a permissive choice on a destructive body must need confirmation")

    let raster = try rasterise(DrawerView(question: m, accent: IslandState.waiting.accent, width: width))
    let margin = footerMargin(raster, footerHeight: 44)
    #expect(margin >= 0,
            "content reaches \(-margin)pt into the reserved footer with a long command body after picking, at production width \(width)pt")
}

/// §10.3 asks a person to authorise a destructive command, so the command has
/// to be legible — and the part that decides whether it is safe to authorise
/// is its *target*, which is at the end. `.lineLimit(1)` above stopped the
/// banner clipping but left SwiftUI's default `.tail` truncation in place,
/// which elides exactly that: `rm -rf /Users/dev/projects/vibe…`.
///
/// What would have to break for this to fail, stated before it was written:
/// the two bodies differ only in their final three characters and nowhere
/// else, in a monospaced font, so they are the same width and `.tail`
/// truncation cuts both at the same column and renders them pixel-identical.
/// Only a truncation mode that keeps the tail can tell them apart — which is
/// also the whole of the safety claim, since `tmp` and `src` are the
/// difference between a harmless `rm -rf` and a catastrophic one.
@MainActor @Test func aLongCommandBodyKeepsTheTargetBeingAuthorisedRatherThanItsHead() throws {
    let model = IslandModel(geometry: IslandGeometry(screen: IslandGoldenTests.mbp14),
                            motion: MotionPreference(chosen: .full, systemWantsReduced: false))
    model.state = .waiting
    model.sessionCount = 1
    let width = model.frames.body.width

    let stem = "rm -rf /Users/dev/projects/vibecat-worktrees/feat-drawer-and-answering/build/cache/"
    #expect(stem.count > 60,
            "setup: the stem must already overflow \(width)pt on its own, or nothing is truncated and this test proves nothing")

    func render(_ target: String) throws -> Raster {
        try rasterise(DrawerView(question: QuestionModel(event: destructiveQuestion(body: stem + target)),
                                 accent: IslandState.waiting.accent, width: width))
    }
    let harmless = try render("tmp")
    let disaster = try render("src")

    // Nothing in this render reads a clock — `DrawerView` has no
    // `TimelineView` — so identical inputs give byte-identical output and the
    // jitter allowance the hover tests below need does not apply here. 40 is
    // measured, in both directions: three monospaced glyphs at 12pt differ by
    // 154 pixels once the tail survives, and by exactly 0 before it did —
    // this test was watched failing at 0 before `.truncationMode(.middle)`
    // existed, so the threshold sits in a gap with nothing in it.
    #expect(harmless.differingPixelCount(from: disaster) > 40,
            "the two commands differ only in their target — `…/cache/tmp` against `…/cache/src` — and rendered with \(harmless.differingPixelCount(from: disaster)) differing pixels: the target is being truncated away, so a person is asked to authorise a command they cannot see the end of")
}

/// Plan 4.5, colour. The prototype has two named text greys and uses them 32
/// times between them — `--bone: #EDEFF4` for primary text, `--haze: #8A93A6`
/// for secondary. Which label takes which is read off its own drawer markup:
/// `.ask-q` (the question) is `--bone`; `.detail.mono` (the command body) is
/// `--haze`; `.choice.alt` — a non-recommended row — is `--haze`;
/// `.confirm .tally` is `--haze`.
///
/// We had neither. Every label was `Color.white` or `Color.white.opacity(…)`,
/// which is a different family rather than a near miss: white at 65% over
/// `islandGroundColour` renders ≈(168,169,169), dead neutral, where `--haze` is
/// (138,147,166) — about 30 levels darker **and cool**, `b − r = 28` against our
/// 1. No opacity value reaches a hue.
///
/// **Both floors are measured, and the white one is the load-bearing half.**
/// Pure white sits 18/16/11 levels from `--bone`, outside
/// `pixelCount(near:)`'s tolerance of 6, so a title still painted `Color.white`
/// leaves a core of white glyph pixels — 437 of them before this change, 0 after.
/// A bare `pixelCount(near: bone) > 0` would *not* have caught it: antialiasing
/// white text over a near-black ground incidentally produces pixels within
/// tolerance of `--bone`, so that assertion passed before the tones existed. The
/// floors below are set against what the tones actually draw.
@MainActor @Test func theDrawersTextUsesThePrototypesTonesRatherThanWhiteAtAnOpacity() throws {
    let bone = try #require(RGBA(hex: "#EDEFF4"), "the prototype's --bone")
    let haze = try #require(RGBA(hex: "#8A93A6"), "the prototype's --haze")
    let pureWhite = try #require(RGBA(hex: "#FFFFFF"))
    let m = QuestionModel(event: threeChoices(multi: false))
    let raster = try rasterise(DrawerView(question: m, accent: IslandState.waiting.accent,
                                          width: 420))

    #expect(raster.pixelCount(near: pureWhite) == 0,
            "\(raster.pixelCount(near: pureWhite)) pure-white pixels remain — text is still `Color.white`, which is 18 levels off --bone (437 before this change)")
    #expect(raster.pixelCount(near: bone) > 150,
            "only \(raster.pixelCount(near: bone)) --bone pixels — the question title is not drawn in the prototype's primary tone")
    #expect(raster.pixelCount(near: haze) > 150,
            "only \(raster.pixelCount(near: haze)) --haze pixels — the command body and the non-recommended rows are not drawn in the prototype's secondary tone")
}

/// Plan 5, Task 1. The sliver `theDrawersContentDoesNotShiftWhenOnlyHoverChanges`
/// records as a known residual: `IslandBody` painted one silhouette rect at the
/// hover-coupled width across the *whole* body height, and since Task 8 that
/// height includes an open drawer — while Plan 4 deliberately made the drawer's
/// own width hover-independent. So hovering painted `hoverReveal` points of
/// island ground down the right of the drawer, over ~92% of its height.
///
/// Asserted as the rule itself rather than by sampling a column: **hover must
/// change the collapsed row's painted width by exactly the reveal, and the
/// drawer row's by nothing.** A first draft of this test sampled one pixel at
/// `drawerWidth + 2` and failed against a correct implementation, because the
/// painted region starts at the panel's own leading offset (24pt here), not at
/// column 0 — so that column was still inside the drawer. Measuring the extent
/// needs no offset arithmetic to get wrong.
@MainActor @Test func hoverWidensTheCollapsedRowAndLeavesTheDrawerRowAlone() throws {
    let model = IslandModel(geometry: IslandGeometry(screen: IslandGoldenTests.mbp14),
                            motion: MotionPreference(chosen: .full, systemWantsReduced: false))
    // .idle, not .waiting, for the same reason the hover test below uses it: a
    // continuous mood takes IslandView's TimelineView branch and reads the real
    // wall clock per render, which made two-render comparisons flake.
    model.state = .idle
    model.sessionCount = 3
    model.question = QuestionModel(event: threeChoices(multi: false))
    model.drawerOpen = true

    /// The painted run's width on one row, in points.
    func paintedWidth(_ raster: Raster, row y: Int) -> Int {
        var first = -1, last = -1
        for x in 0..<raster.width where !raster[x, y].isTransparent {
            if first < 0 { first = x }
            last = x
        }
        return first < 0 ? 0 : last - first + 1
    }

    let inTheBar = Int(model.geometry.notch.height) / 2
    let belowTheNotch = Int(model.geometry.notch.height) + 60

    model.hovering = false
    let atRest = try rasterise(IslandView(model: model))
    model.hovering = true
    let hovered = try rasterise(IslandView(model: model))

    let drawerAtRest = paintedWidth(atRest, row: belowTheNotch)
    let drawerHovered = paintedWidth(hovered, row: belowTheNotch)
    #expect(drawerAtRest > 0, "setup: nothing is painted below the notch line at all")
    #expect(drawerHovered == drawerAtRest,
            "the drawer row went from \(drawerAtRest)pt to \(drawerHovered)pt wide on hover — the reveal is dragging the hover-independent drawer with it, which is the sliver")

    // With the drawer open the reveal is dropped entirely, so the bar matches
    // the drawer rather than stepping past it — see the `.frame` comment in
    // `IslandBody`. So the bar must not move on hover *either*, while open.
    let barAtRest = paintedWidth(atRest, row: inTheBar)
    let barHovered = paintedWidth(hovered, row: inTheBar)
    #expect(barHovered == barAtRest,
            "the collapsed bar went \(barAtRest)pt → \(barHovered)pt on hover with the drawer open — §6.1's tiers are progressive, and a bar wider than the drawer under it is a step off to the right of every question")
    #expect(barHovered == drawerHovered,
            "bar \(barHovered)pt against drawer \(drawerHovered)pt — with the drawer open the two must be one column, not two widths")
}

/// The other half of the same rule, and the one that keeps the fix above from
/// being "delete the hover reveal": with the drawer **closed**, hover must still
/// widen the island by exactly the reveal. A single test asserting only the open
/// case would pass against a `hoverRevealWidth` hardcoded to zero.
@MainActor @Test func hoverStillWidensTheIslandWhenNoDrawerIsOpen() throws {
    let model = IslandModel(geometry: IslandGeometry(screen: IslandGoldenTests.mbp14),
                            motion: MotionPreference(chosen: .full, systemWantsReduced: false))
    model.state = .idle
    model.sessionCount = 3

    func paintedWidth(_ raster: Raster, row y: Int) -> Int {
        var first = -1, last = -1
        for x in 0..<raster.width where !raster[x, y].isTransparent {
            if first < 0 { first = x }
            last = x
        }
        return first < 0 ? 0 : last - first + 1
    }
    let inTheBar = Int(model.geometry.notch.height) / 2

    model.hovering = false
    let atRest = try rasterise(IslandView(model: model))
    model.hovering = true
    let hovered = try rasterise(IslandView(model: model))

    #expect(paintedWidth(hovered, row: inTheBar) - paintedWidth(atRest, row: inTheBar)
                == Int(CollapsedLayout.hoverReveal),
            "hover changed the closed island's width by \(paintedWidth(hovered, row: inTheBar) - paintedWidth(atRest, row: inTheBar))pt, not \(Int(CollapsedLayout.hoverReveal)) — the reveal itself is gone")
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
///
/// The alignment check below asserts against a *derived* expected position,
/// not a wide tolerance around the collapsed body's own edge — a first
/// version used a blanket ±20pt band and it passed even with
/// `drawerLeadingOffset` zeroed out (residual −8pt against the correct
/// +16pt, both inside ±20), because `QuestionFace.leadingPadding` is itself
/// close to that width. See that check's own comment.
///
/// **Updated for Task 8.** Two things changed once `IslandModel` gained a
/// real tier: `model.drawerOpen = true` is now required — `IslandView` only
/// composes `DrawerView` in at all when `model.tier` is actually `.drawer`,
/// not merely when `model.question` is set (see `IslandView.body`'s own
/// comment on why gating on the question alone stopped being enough). And
/// `drawerTop`, the boundary this test scans around, moved from
/// `model.panelFrames.panel.height` to `model.geometry.notch.height`:
/// `panelFrames` is itself tier-aware now, so with the drawer open it *equals*
/// the full rendered height rather than marking where the collapsed content
/// ends — `notch.height` is what actually still does that (see
/// `IslandBody.content`'s own hard clip to it).
@MainActor @Test func islandViewComposesTheDrawerFlushBelowAndAlignedWithTheCollapsedBody() throws {
    let model = IslandModel(geometry: IslandGeometry(screen: IslandGoldenTests.mbp14),
                            motion: MotionPreference(chosen: .full, systemWantsReduced: false))
    model.state = .waiting
    model.sessionCount = 1
    model.question = QuestionModel(event: recommendedEvent())
    model.drawerOpen = true

    let raster = try rasterise(IslandView(model: model))
    // The true "collapsed only" reference, independent of the model's own
    // (now tier-aware) `panelFrames` — computed at a fixed `.rest` so this
    // still means what it always meant, regardless of what tier the model
    // under test happens to be in.
    let collapsedPanelHeight = Int(model.geometry.maxCollapsedFrames(tier: .rest).panel.height.rounded(.up))
    #expect(raster.height > collapsedPanelHeight,
            "the rendered image is no taller than the collapsed panel alone — the drawer never reached the tree")

    // Where the collapsed content ends and the drawer begins — `notch.height`,
    // not `panelFrames.panel.height` (see the doc comment above).
    let drawerTop = Int(model.geometry.notch.height.rounded(.up))

    // Ordering: the cat's own fixed facial tones (see `IslandGoldenTests`'
    // own use of them as "the sprite actually drew") belong above the
    // drawer — catching a reversed stacking order, which the horizontal-only
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

    // A ±20pt band here would pass both the correct render *and* a
    // zeroed-out leading offset: `QuestionFace.leadingPadding` (16pt) is
    // itself close to that width, so a genuinely misaligned drawer
    // (residual −8pt, measured directly) still lands inside a tolerance
    // sized only to shrug off the padding as noise. The padding is a known,
    // derivable quantity, not noise — read back through
    // `QuestionFace.leadingPadding` rather than a second copy of the
    // literal — so the expected left edge is computed explicitly and the
    // remaining tolerance covers only antialiasing at the border's own
    // 1pt stroke, not an unrelated bug hiding behind the same number.
    let expectedLeft = collapsedPainted.first + Int(QuestionFace.leadingPadding)
    #expect(abs(left - expectedLeft) <= 3,
            "drawer's leftmost accent at \(left), expected \(expectedLeft) (collapsed body's own left edge \(collapsedPainted.first) + QuestionFace.leadingPadding \(QuestionFace.leadingPadding)) — the drawer has drifted sideways")

    #expect(Double(right - left) < model.frames.body.width,
            "accent spans \(right - left)pt — at or past the live body width \(model.frames.body.width); the drawer may be sized off the fixed panel's wider frame instead")
}

/// The render-level version of "a question must not open the drawer on its
/// own" (design §6.1's Click tier; `NotchControllerTests
/// .aQuestionDoesNotOpenTheDrawerOnItsOwn` pins the same property at the
/// model level, checking `model.tier` rather than pixels).
///
/// `IslandView.body` gates `DrawerView` on `model.tier` being `.drawer`, not
/// merely on `model.question` being non-nil — confirmed to matter, not
/// belt-and-braces: reverting that gate back to `if let question =
/// model.question` (dropping the tier check) leaves this scene's *rendered
/// size* unchanged (`ImageRenderer` does not expand a view's reported size to
/// fit an `.overlay` taller than its base — ImageRenderer sizes to
/// `IslandBody`'s own outer frame, which stays at the small collapsed size
/// while `model.tier` is `.rest`), but does still paint
/// `DrawerView`'s own ground-coloured fill into the sliver of rows both the
/// collapsed frame and the (clipped, oversized) overlay share — a real,
/// pixel-level leak of "drawer content" into a render that must show none.
@MainActor @Test func aQuestionWithoutAClickRendersIdenticallyToNoQuestionAtAll() throws {
    func scene(withQuestion: Bool) throws -> Raster {
        let model = IslandModel(geometry: IslandGeometry(screen: IslandGoldenTests.mbp14),
                                motion: MotionPreference(chosen: .full, systemWantsReduced: false))
        // .idle, not .waiting: found flaky during this fix wave's own
        // full-suite runs (an intermittent 4-pixel difference). This test
        // renders IslandView — not IslandBody directly, unlike
        // IslandGoldenTests' own silhouette() helper, which sidesteps the
        // same hazard by passing an explicit fixed `now:` — twice and
        // compares them pixel-for-pixel. .waiting's cat (`call`) and badge
        // (`bang`) are both continuous, so IslandView.body takes the
        // TimelineView branch and reads the *real* wall clock (`ctx.date`)
        // each render; two calls close together in a synchronous test
        // usually land on the same rendered frame, but not always,
        // especially under full-suite load. .idle's mood (`happy`) and
        // badge (`star`) are both non-continuous (confirmed by
        // `aSteadyStateNeedsNoTimeline` in IslandModelTests.swift), so
        // `needsTimeline` is false and this falls to the plain `Date()`
        // branch instead — not perfectly time-invariant either, but the two
        // calls are microseconds apart against multi-second cycles, which
        // is what this fix wave's own repeated full-suite runs confirmed
        // stops the flake — see the task report for the exact counts.
        model.state = .idle
        model.sessionCount = 1
        if withQuestion {
            model.question = QuestionModel(event: recommendedEvent())
            // drawerOpen deliberately left false — a question arriving must
            // not open the drawer by itself.
        }
        return try rasterise(IslandView(model: model))
    }

    let withQuestion = try scene(withQuestion: true)
    let withoutQuestion = try scene(withQuestion: false)

    #expect(withQuestion.height == withoutQuestion.height,
            "a question nobody clicked open changed the rendered height (\(withQuestion.height) vs \(withoutQuestion.height)pt) — the drawer reached the tree before any click")
    // <= 30, not == 0: found flaky during this fix wave's full-suite runs
    // even after switching off `.waiting` above — a handful of pixels
    // (measured: 4) differing between two otherwise-identical renders,
    // which switching state did not fully close (a residual, low-probability
    // rendering jitter this project's own Raster.pixelCount(near:tolerance:)
    // already documents for exact-equality-against-a-render checks generally
    // — "colour management, antialiasing and premultiplication all move a
    // value by a level or two"). 30 is comfortably above every jitter
    // magnitude measured during this fix wave (4, 4, 8) and nowhere near a
    // real difference (the drawer actually reaching the tree measures in the
    // thousands of pixels — see e.g. `theDrawersContentDoesNotShiftWhen
    // OnlyHoverChanges`'s own mutation numbers in the task report).
    #expect(withQuestion.differingPixelCount(from: withoutQuestion) <= 30,
            "a question nobody clicked open changed \(withQuestion.differingPixelCount(from: withoutQuestion)) pixels — the drawer reached the tree (or painted into it) before any click")
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

/// Finding 1 of the final whole-branch review: the test above only proves
/// *some* property is read while `body` is built — it stayed green
/// throughout the actual defect, because `model.question?.face.height ?? 0`
/// (what `drawerHeight` read before this fix) is also "a property." That
/// expression changes the moment a question ARRIVES (`model.question` goes
/// non-nil) and does not change when `drawerOpen` flips — the exact inverse
/// of what §9.1's spring exists to animate. Confirmed directly: reverting
/// `drawerHeight` to that shape keeps `bodyActuallyReadsDrawerHeightWhileBeingBuilt`
/// green (some property is still read every time) while every assertion
/// below fails, because a still-open question makes `closed` and `open`
/// compute the identical, already-nonzero value.
@MainActor @Test func drawerHeightTracksTheTierOpeningNotTheQuestionArriving() {
    let model = IslandModel(geometry: IslandGeometry(screen: IslandGoldenTests.mbp14),
                            motion: MotionPreference(chosen: .full, systemWantsReduced: false))
    model.question = QuestionModel(event: recommendedEvent())

    model.drawerOpen = false
    let closed = IslandView(model: model).drawerHeight
    model.drawerOpen = true
    let open = IslandView(model: model).drawerHeight

    #expect(closed == 0,
            "a question that has not been clicked open must contribute no height to the spring's input")
    #expect(open == model.question!.face.height,
            "an open drawer's height did not reach drawerHeight")
    #expect(closed != open,
            "drawerHeight did not change between drawerOpen == false and true — the §9.1 spring has nothing to animate on click")
}

/// Finding 5 of the final whole-branch review: `IslandView` used to hand
/// `DrawerView` `model.frames.body.width` directly, which carries the
/// collapsed pill's own 150pt hover reveal (§9.1) — measured before this
/// fix, 423.1pt while hovering against 273.1pt while not, on the identical
/// open question. An open drawer spends most of its life with the cursor
/// somewhere else entirely, so every row reflowed the instant it left,
/// unannounced. Decision: the drawer's width does not depend on hover at all
/// (`IslandModel.drawerWidth`) — nothing in `QuestionFace` needs the extra
/// room hover reveals (a session's name and elapsed time, neither of which
/// this face shows), so there is no reason for its layout to change with it.
///
/// Checked on the render, not just the property: `panelFrames.panel.width`
/// is fixed regardless of hovering (`IslandGeometry.maxCollapsedFrames`
/// always assumes the theoretical widest), so both renders below are the
/// same canvas size regardless of which width the drawer itself used —
/// comparing pixels below the collapsed body directly is what actually
/// proves the drawer's own content held still, rather than merely that some
/// property nothing reads stayed constant.
///
/// Scoped to the drawer's own painted columns (`0..<model.drawerWidth`), not
/// the full raster width.
///
/// **That scoping used to be a concession and no longer is.** It carried a long
/// note here describing a "known, minor, and deliberately unfixed residual": the
/// silhouette was one shape spanning the whole body height at the hover-coupled
/// width, so hovering painted a same-coloured sliver of it to the right of the
/// hover-independent drawer. Plan 5's Task 1 split the silhouette in two and that
/// sliver is gone — see
/// `hoverWidensTheCollapsedRowAndLeavesTheDrawerRowAlone`, and the mutation
/// behind it: with the old single rect restored, the drawer row measures 423pt
/// wide hovered against 273pt at rest, exactly `hoverReveal` of sliver.
///
/// The scoping stays anyway, because it is the right scope for *this* test's own
/// question — the drawer's own content holding still is a claim about the
/// drawer's own columns — and because narrowing a passing test's scope is not
/// something to do on the strength of one fix.
@MainActor @Test func theDrawersContentDoesNotShiftWhenOnlyHoverChanges() throws {
    let model = IslandModel(geometry: IslandGeometry(screen: IslandGoldenTests.mbp14),
                            motion: MotionPreference(chosen: .full, systemWantsReduced: false))
    // .idle, not .waiting: this test renders IslandView twice and compares
    // pixels, which found flaky during this fix wave's own full-suite runs
    // for the same reason `aQuestionWithoutAClickRendersIdenticallyToNoQuestionAtAll`
    // above did — see that test's own comment for the mechanism (`.waiting`'s
    // continuous mood/badge takes IslandView's TimelineView branch, which
    // reads the real wall clock per render).
    model.state = .idle
    model.sessionCount = 3
    // `tightestPackingSingleSelect`'s long label, not `recommendedEvent`'s
    // short ones: a label short enough to fit either width unwrapped shows
    // nothing when the available width changes, which is exactly why this
    // needs one long enough to wrap *differently* at 273pt than at 423pt —
    // confirmed below (`heightDifference` before this fix) that it does.
    model.question = QuestionModel(event: tightestPackingSingleSelect())
    model.drawerOpen = true

    model.hovering = false
    let atRest = try rasterise(IslandView(model: model))
    let drawerWidth = model.drawerWidth
    model.hovering = true
    let hovered = try rasterise(IslandView(model: model))
    #expect(atRest.width == hovered.width && atRest.height == hovered.height,
            "setup: the two renders are different sizes, so a row-for-row comparison below proves nothing")
    #expect(model.drawerWidth == drawerWidth,
            "setup: drawerWidth itself moved when hovering changed, which is exactly what this test exists to catch")

    let drawerTop = Int(model.geometry.notch.height.rounded(.up))
    // Clamped to the raster, and stated as a failure rather than left to
    // `Raster`'s own subscript precondition. Found while mutation-checking Plan
    // 6.3 Task 1: a mutant that widened `drawerWidth` without widening the panel
    // made this scan run past the render's right edge and **trap**, which aborts
    // the whole serial suite at that point — so the mutation's real effect
    // elsewhere could not be read at all. A test that crashes tells you less than
    // one that fails.
    #expect(drawerWidth <= CGFloat(atRest.width),
            "setup: the drawer is \(drawerWidth)pt wide inside a \(atRest.width)pt render — the panel is not covering the drawer, so the scan below would run off the edge")
    let drawerRight = min(atRest.width, Int(drawerWidth.rounded(.down)))
    var differing = 0
    for y in drawerTop..<atRest.height {
        for x in 0..<drawerRight where atRest[x, y] != hovered[x, y] {
            differing += 1
        }
    }
    // `== 0`, not `<= 30`. The 30 was measured against real jitter (4, 4, 8, and
    // later 22, across separate full-suite runs) while the sliver still existed;
    // with the silhouette split this measures **0**, so the allowance is no
    // longer absorbing anything and a tolerance that absorbs nothing should not
    // be spent. A real difference here is in the thousands (2015 pixels, from
    // this test's own mutation check), so nothing between 0 and 30 is a signal
    // this test cares about either way.
    //
    // (The superseded `<= 30` paragraph used to sit stacked directly *above*
    // this one, over code that already read `== 0` — F6 of the final
    // whole-branch review: a reader met the wrong one first. Its measurements
    // are folded in above rather than deleted, because they are the record of
    // why 30 was ever chosen. The `<= 30` block near
    // `aQuestionWithoutAClickRendersIdenticallyToNoQuestionAtAll` is a
    // different test's own tolerance and is correct there.)
    //
    // Observed once during Plan 5's final fix wave, on one full-suite run out of
    // ~10 and never reproducible under `--filter`: 72 differing pixels. Far
    // above every jitter magnitude previously recorded and far below a real
    // regression. Not chased, and not absorbed by loosening this back — logged
    // in plans/README.md against the drawer-golden flake this file already
    // carries. If it recurs, that entry is the place to start.
    #expect(differing == 0,
            "\(differing) pixels within the drawer's own width changed when only `hovering` toggled — the drawer's own content moved with the hover reveal")
}
