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
        model.state = .waiting
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
    #expect(withQuestion.differingPixelCount(from: withoutQuestion) == 0,
            "a question nobody clicked open changed what is rendered — the drawer reached the tree (or painted into it) before any click")
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
/// the full raster width — a known, minor, and deliberately unfixed residual:
/// `IslandBody`'s own silhouette is one shape spanning the *whole* body
/// height (collapsed content and drawer both, since `body.height` already
/// includes the open drawer's own height), drawn at `restingWidth +
/// hoverRevealWidth` regardless of what `DrawerView` does with its own
/// width. While hovering, that shape is wider than the now hover-independent
/// drawer sitting on top of it, so a same-coloured sliver of it (with its
/// own, differently-positioned rounded bottom corner) is visible to the
/// right of the drawer, only while hovering. Fixing that would mean teaching
/// `IslandBody`'s own hover reveal to stop widening while a drawer happens
/// to be open — a real change to a different, more heavily-relied-on
/// mechanism (Task 9/10's collapsed-pill width split) for a same-colour,
/// off-to-the-side cosmetic detail, and out of scope for what this finding
/// asked: the drawer's *own* content must hold still, which this proves.
@MainActor @Test func theDrawersContentDoesNotShiftWhenOnlyHoverChanges() throws {
    let model = IslandModel(geometry: IslandGeometry(screen: IslandGoldenTests.mbp14),
                            motion: MotionPreference(chosen: .full, systemWantsReduced: false))
    model.state = .waiting
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
    let drawerRight = Int(drawerWidth.rounded(.down))
    var differing = 0
    for y in drawerTop..<atRest.height {
        for x in 0..<drawerRight where atRest[x, y] != hovered[x, y] {
            differing += 1
        }
    }
    #expect(differing == 0,
            "\(differing) pixels within the drawer's own width changed when only `hovering` toggled — the drawer's own content moved with the hover reveal")
}
