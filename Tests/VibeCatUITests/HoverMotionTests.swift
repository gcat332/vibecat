import Foundation
import SwiftUI
import Testing
import VibeCatCore
@testable import VibeCatUI

// ─────────────────────────────────────────────────────────────────────────────
// Plan 6.3 Task 4 — hover is three clocks, not one.
//
// `island-motion.html` runs three things on two curves when the island is
// hovered:
//
//   .island  width + transform   440ms  --spring-w   (lines 84–85)
//   .detail  max-width + margin  280ms  --ease       (line 125)
//   .detail  opacity             160ms  --ease       (line 125)
//
// Ours was one `.animation(IslandMotion.ease(duration: 0.28), value:
// hoverRevealWidth)` on the whole silhouette stack, covering all three. The
// consequence that matters is not the durations, it is that **the shape had no
// overshoot at all** — so on hover, §9.1's "width overshoots more than height so
// the island reads as one body with mass" was absent rather than merely
// mismatched, while being correctly wired on the click since Task 2.
//
// Four claims are made here, each with the mutation that breaks it named:
//
//   1. the shape curve exceeds 100% of its travel, and the curve it replaced
//      provably cannot                       → theHoverShapeCurve…
//   2. the fade lands before the width does, with a consequence in points
//                                            → theHoverFade…
//   3. the three durations are the prototype's three tokens
//                                            → theThreeHoverClocks…
//   4. the two `--ease` clocks sit on their own properties, in the modifier
//      order that makes that true            → theRevealsTwoClocks…
//
// The wiring half — that the hover shape modifier reads `IslandMotion.widthSpring`
// and not `--ease` — is `IslandMotionTests`'
// `theTwoShapeSpringsAreWiredToTheirOwnHalfOfTheMorph`, whose width count went
// from 1 to 2 for exactly this reason, and
// `theEaseSitesAreReachedByARealRender`, whose hover duration set went from
// `[0.28]` to `[0.16, 0.28]`.
// ─────────────────────────────────────────────────────────────────────────────

/// A CSS `cubic-bezier`'s y at a given x, by bisection on x. Computed here
/// independently of `Sources`, so the expected values below do not come from the
/// code under test. (Same routine as `IslandMotionTests.cssBezier` and
/// `MotionFidelityProbe.bez`; deliberately not shared — the probe carries a
/// "delete once the plan has landed" header and these assertions must outlive it,
/// and `IslandMotionTests`' copy is `private` to that file for the same reason.)
private func hoverBezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double,
                         atX x: Double) -> Double {
    func axis(_ p1: Double, _ p2: Double, _ t: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t
    }
    var lo = 0.0, hi = 1.0
    for _ in 0..<60 {
        let mid = (lo + hi) / 2
        if axis(x1, x2, mid) < x { lo = mid } else { hi = mid }
    }
    return axis(y1, y2, (lo + hi) / 2)
}

/// A CSS `transition`: the curve, held at 1 once the duration is up.
private func cssTransition(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double,
                           duration: Double, atMs ms: Double) -> Double {
    ms >= duration * 1000 ? 1 : hoverBezier(x1, y1, x2, y2, atX: (ms / 1000) / duration)
}

/// `island-motion.html:22` — `--spring-w: cubic-bezier(.32,1.5,.5,1)`, over
/// `--t-shape: 440ms`. The `1.5` is what puts it past 100%.
private func protoShapeWidth(atMs ms: Double) -> Double {
    cssTransition(0.32, 1.5, 0.5, 1, duration: 0.440, atMs: ms)
}

/// The peak of a `Spring`'s approach to 1, and when it happens. 2ms steps out to
/// 800ms, which is well past both springs' settling time at `response 0.42`/`0.45`.
///
/// `response` is a parameter as of Plan 6.3 Task 5, because the two springs no
/// longer share one: the drawer's height runs 30ms longer than the width
/// (`IslandMotion.heightResponse`). The peak *value* is invariant under response —
/// a spring's overshoot is a function of damping alone, and time only rescales —
/// so the overshoot figures below are unaffected; the peak's *time* is not, and
/// passing the wrong response would report the drawer settling 30ms earlier than
/// production does.
private func springPeak(damping: Double,
                        response: Double = IslandMotion.response) -> (value: Double, atMs: Double) {
    let spring = Spring(response: response, dampingRatio: damping)
    var best = (value: 0.0, atMs: 0.0)
    for step in 0...400 {
        let ms = Double(step) * 2
        let v = spring.value(target: 1.0, time: ms / 1000)
        if v > best.value { best = (v, ms) }
    }
    return best
}

// MARK: - 1. The shape curve exceeds 100%

/// **The one assertion the pre-Task-4 code could not pass.**
///
/// §9.1: *"Width overshoots more than height, so the island reads as one body
/// with mass rather than a resizing box."* Hover is a width change — 273.1 →
/// 423.1pt on the mbp14 fixture, `CollapsedLayout.hoverReveal`'s 150pt — and
/// until Task 4 it ran on `IslandMotion.ease(duration: 0.28)`, a curve that
/// **cannot** exceed its target: `cubic-bezier(.22,.9,.28,1)`'s control points
/// both have y ≤ 1, so it approaches 1 from below and stops. The rule was
/// therefore not approximated on this gesture, it was missing.
///
/// Three things are asserted, and the second is what makes the first a test
/// rather than a tautology:
///
/// 1. the curve the hover shape now moves on — `Spring(response:
///    IslandMotion.response, dampingRatio: IslandMotion.widthDamping)`, the exact
///    parameters `IslandMotion.widthSpring` builds — goes **past 1.0**;
/// 2. `IslandMotion.easeCurve`, the curve it replaced, **never** does, at any of
///    999 interior points. A test that only checked (1) would pass just as well
///    against a spring installed nowhere;
/// 3. the overshoot is the prototype's, not merely nonzero — `--spring-w` at
///    440ms peaks at 108.0% and ours at 108.4%, so the peak is asserted inside a
///    1-point band around the prototype's rather than as `> 1`. A damping of
///    0.90 still overshoots (0.3%) and would pass a bare `> 1`.
///
/// Would fail if: the hover shape site went back to any monotone curve
/// (`widthSpringReadCount` in `IslandMotionTests` is what sees *that* change;
/// this test sees the change in what the curve can do); if
/// `IslandMotion.widthDamping` were raised back toward its pre-4.5 `0.72`, which
/// overshoots 3.8% and fails the band; or if `response` moved far enough to shift
/// the peak's timing out of the window.
@Test func theHoverShapeCurveExceedsOneHundredPercentOfItsTravel() {
    let peak = springPeak(damping: IslandMotion.widthDamping)

    #expect(peak.value > 1.0,
            "the island's width spring peaks at \(peak.value) — it never exceeds its target, so §9.1's overshoot is absent from the hover exactly as it was before Plan 6.3 Task 4")

    // The prototype's own peak, computed from the bezier and not quoted.
    var protoPeak = (value: 0.0, atMs: 0.0)
    for step in 0...400 {
        let ms = Double(step) * 2
        let v = protoShapeWidth(atMs: ms)
        if v > protoPeak.value { protoPeak = (v, ms) }
    }
    #expect(abs(protoPeak.value - 1.080) < 0.001 && abs(protoPeak.atMs - 230) < 6,
            "--spring-w over --t-shape peaks at \(protoPeak.value) at \(protoPeak.atMs)ms; the figures recorded in IslandMotion.hoverRevealDuration and Task 4's report are 108.0% at 230ms")
    #expect(abs(peak.value - protoPeak.value) < 0.01,
            "ours peaks at \(peak.value), the prototype at \(protoPeak.value) — more than a point apart, so the hover shape is overshooting but not by the prototype's amount")

    // The discriminating half: the curve this replaced cannot do it.
    var easeMax = 0.0
    for step in 1...999 { easeMax = max(easeMax, IslandMotion.easeCurve.value(at: Double(step) / 1000)) }
    #expect(easeMax <= 1.0,
            "IslandMotion.easeCurve reaches \(easeMax) — it can exceed 1, so the assertion above no longer distinguishes the spring Task 4 installed from the --ease clock it replaced and proves nothing")

    // And what it means in points, on the fixture the rest of the suite uses.
    let travel = CollapsedLayout.hoverReveal
    let past = (peak.value - 1) * travel
    #expect(past > 10 && past < 15,
            "the hovered island runs \(past)pt past its 423.1pt hovered width before settling; Task 4 recorded 12.5pt on a \(travel)pt reveal")
}

/// **The two shape springs are untouched.** Plan 4.5 measured them against the
/// prototype and the plan's Global Constraints forbid changing them; Task 4 gave
/// the *hover* a second reader of `widthSpring`, which must not have moved the
/// numbers either spring produces.
///
/// Would fail if: `response`, `widthDamping` or `heightDamping` were retuned while
/// "making hover overshoot" — the failure mode this task was most exposed to, since
/// raising the width overshoot is the obvious wrong way to make a hover feel
/// springier.
@Test func task4DidNotRetuneEitherShapeSpring() {
    #expect(IslandMotion.response == 0.42)
    #expect(IslandMotion.widthDamping == 0.62)
    #expect(IslandMotion.heightDamping == 0.80)

    let width = springPeak(damping: IslandMotion.widthDamping).value - 1
    let height = springPeak(damping: IslandMotion.heightDamping,
                            response: IslandMotion.heightResponse).value - 1
    #expect(abs(width - 0.083) < 0.002,
            "the width spring's overshoot measured \(width); IslandMotion records 8.3% against the prototype's 8.0%")
    #expect(abs(height - 0.015) < 0.002,
            "the height spring's overshoot measured \(height); IslandMotion records 1.5%, matching the prototype exactly")
}

// MARK: - 2. The fade finishes before the width does

/// **Three clocks means the *ordering* is observable, and an implementation with
/// three identical durations would look exactly like the one modifier it
/// replaced.**
///
/// `island-motion.html:125` gives the reveal's `max-width` `--t-hover` (280ms) and
/// its `opacity` a bare `160ms`. So the text is fully opaque 120ms before its
/// container stops widening, and the consequence in the rendered gesture — the
/// thing an eye actually sees — is that at the moment the fade lands the reveal is
/// still short of its full width. Asserted as that consequence rather than as
/// `0.16 < 0.28`, which would be a fact about two literals.
///
/// Would fail if: the two durations were equalised in either direction (the
/// collapse-to-one-clock mutation); if they were swapped, which `<` catches and a
/// set-membership assertion would not; or if the fade were lengthened past the
/// reveal's own clock.
@Test func theHoverFadeFinishesBeforeTheRevealWidthDoes() {
    #expect(IslandMotion.hoverFadeDuration < IslandMotion.hoverRevealDuration,
            "the reveal's fade runs \(IslandMotion.hoverFadeDuration)s against its width's \(IslandMotion.hoverRevealDuration)s — the prototype's line 125 has opacity finish first, and three clocks of equal length are the one clock Task 4 replaced wearing three hats")

    // The consequence: where the width has got to when the fade is over.
    let fraction = IslandMotion.hoverFadeDuration / IslandMotion.hoverRevealDuration
    let widthThen = IslandMotion.easeCurve.value(at: fraction)
    #expect(widthThen < 1.0,
            "at the instant the fade completes the reveal is already at its full width (\(widthThen)) — the text arrives rather than being uncovered")
    #expect(abs(widthThen - 0.970) < 0.002,
            "the reveal is \(widthThen) of the way across when the fade lands; IslandMotion.hoverFadeDuration's doc comment and Task 4's report both say 97.0%")

    // Both clocks are shorter than the shape's, which is what makes the reveal a
    // thing happening inside a moving shape rather than alongside it. `response`
    // is a spring's nominal period, so this compares like with like only loosely
    // — the point is the sign, and it is not close.
    #expect(IslandMotion.hoverRevealDuration < IslandMotion.response,
            "the reveal's own clock (\(IslandMotion.hoverRevealDuration)s) is no shorter than the shape's (\(IslandMotion.response)s), so the text stops moving no earlier than the island does")
}

/// **The three durations are the prototype's three tokens**, and the shape's is
/// not one of the `--ease` ones.
///
/// `--t-hover: 280ms` and `--t-shape: 440ms` are declared at `island-motion.html:26`
/// and `:25`; the fade's `160ms` is written inline at line 125. Our shape clock is
/// a spring, so its `response` is `0.42` rather than `0.44` — §9.1's own number,
/// recorded in `IslandMotion.response` as "close to the prototype's own 440ms" and
/// deliberately not retuned by this task.
///
/// Would fail if: a duration drifted off its token (0.28 → 0.3 fails); if the fade
/// were given `--t-face`'s 0.19 by copy-paste, which is the nearest wrong value in
/// the codebase; or if either constant were deleted and inlined back at the call
/// site, since then nothing here would compile.
@MainActor @Test func theThreeHoverClocksAreThePrototypesOwnTokens() {
    #expect(IslandMotion.hoverRevealDuration == 0.28,
            "--t-hover is 280ms at island-motion.html:26")
    #expect(IslandMotion.hoverFadeDuration == 0.16,
            "island-motion.html:125 is `opacity 160ms var(--ease)`")
    #expect(IslandMotion.hoverFadeDuration != FaceCrossfade.duration,
            "the hover fade has been given --t-face's duration; they are different surfaces with different tokens")

    // The shape clock is within 5% of --t-shape, which is the claim
    // `IslandMotion.response`'s own comment makes.
    #expect(abs(IslandMotion.response - 0.440) / 0.440 < 0.05,
            "the shape clock is \(IslandMotion.response)s against --t-shape's 0.440s — further apart than IslandMotion.response's comment claims")
}

// MARK: - 3. Each `--ease` clock sits on its own property

/// **Which clock governs which property, checked against this file's own source.**
///
/// The honest reason it is a source-shape assertion: SwiftUI offers no way to ask
/// a built view which `Animation` is on which modifier — the standing limit every
/// read counter in this repo states of itself — and `IslandMotion.easeDurations
/// Read` can only say *that* 0.16 and 0.28 were both requested while
/// `IslandBody.body` was built, never that 0.16 landed on the opacity. So an
/// implementation that requested both durations and attached them the wrong way
/// round would pass `theEaseSitesAreReachedByARealRender` and look wrong.
///
/// What makes the source order load-bearing rather than cosmetic:
/// `.animation(_:value:)` governs the modifiers **below** it in the chain and is
/// overridden by any nearer one. So in
///
///     RevealContent(…)
///         .opacity(revealWidth > 0 ? 1 : 0)
///         .animation(ease(hoverFadeDuration), value: revealWidth)     // 160ms
///         .frame(width: revealWidth, alignment: .leading)
///         .clipped()
///         .animation(ease(hoverRevealDuration), value: revealWidth)   // 280ms
///
/// the fade animation is the nearest one to `.opacity` and the reveal animation
/// the nearest one to `.frame` — and the inner of the two is also what stops the
/// enclosing stack's `widthSpring` from reaching either. Moving either
/// `.animation` line to the other side of the property it is meant to govern
/// silently hands that property to the other clock, and that is the specific edit
/// this test exists to fail.
///
/// Would fail if: the two `.animation` lines were swapped; if either were hoisted
/// above `.opacity` or below the whole chain (both put the two properties back on
/// one clock); if `.opacity` and `.frame` were reordered without moving the
/// animations with them; or if the hover shape modifier stopped reading
/// `IslandMotion.widthSpring`.
///
/// What it does **not** prove: that SwiftUI interpolated anything. It is a claim
/// about the modifier chain's shape, which is the layer where the wrong-clock
/// mistake lives.
@Test func theRevealsTwoClocksSitOnTheirOwnProperties() throws {
    let source = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()      // VibeCatUITests
        .deletingLastPathComponent()      // Tests
        .deletingLastPathComponent()      // repo root
        .appendingPathComponent("Sources/VibeCatUI/IslandView.swift")
    // Comments in this file quote modifiers at length; only live code counts.
    let lines = try String(contentsOf: source, encoding: .utf8)
        .components(separatedBy: "\n")
        .enumerated()
        .filter { !$0.element.trimmingCharacters(in: .whitespaces).hasPrefix("//") }

    func onlyLine(containing needle: String) throws -> Int {
        let hits = lines.filter { $0.element.contains(needle) }
        try #require(hits.count == 1,
                     "expected exactly one line of code in IslandView.swift containing `\(needle)`, found \(hits.count) — the hover reveal's modifier chain has been restructured and this test's premise no longer holds")
        return hits[0].offset
    }

    let opacity = try onlyLine(containing: ".opacity(revealWidth > 0 ? 1 : 0)")
    let fadeClock = try onlyLine(containing: "IslandMotion.hoverFadeDuration")
    let frame = try onlyLine(containing: ".frame(width: revealWidth, alignment: .leading)")
    let revealClock = try onlyLine(containing: "IslandMotion.hoverRevealDuration")

    #expect(opacity < fadeClock,
            "the 160ms fade clock (line \(fadeClock + 1)) is written above the `.opacity` it must govern (line \(opacity + 1)) — `.animation(_:value:)` governs what is below it, so the opacity has been handed to whatever animation encloses the chain")
    #expect(fadeClock < frame,
            "the 160ms fade clock (line \(fadeClock + 1)) sits below the reveal's `.frame` (line \(frame + 1)), so it governs the width too and the two properties are back on one clock")
    #expect(frame < revealClock,
            "the 280ms reveal clock (line \(revealClock + 1)) is written above the `.frame` it must govern (line \(frame + 1))")

    // And the shape half: the hover's own width modifier is the spring, not --ease.
    let shapeClock = try onlyLine(containing: "value: hoverRevealWidth")
    #expect(lines.first { $0.offset == shapeClock }!.element.contains("IslandMotion.widthSpring"),
            "the hover's shape modifier reads `\(lines.first { $0.offset == shapeClock }!.element.trimmingCharacters(in: .whitespaces))` — §9.1's overshooting width spring is not what the island's own width morphs on during a hover")
}

// MARK: - 4. Three clocks, through a real render

/// **The refactor did not change what a hovered island paints.** Task 4 reordered
/// `RevealContent`'s modifier chain — `.opacity` moved from after `.frame`/
/// `.clipped()` to before them, so the fade animation could sit between the two
/// properties — and `.opacity` before a `.frame` is a different tree from
/// `.opacity` after it.
///
/// The invariant that must survive, measured off pixels and not read off a
/// property: the reveal's own `--bone` text is painted while hovering, not painted
/// at rest, and confined to the 150pt band `CollapsedLayout.hoverReveal` reserves
/// for it at the right-hand end. `IslandGoldenTests` owns the silhouette-width half
/// at four session counts; this adds the half specific to the reorder.
///
/// Would fail if: `.opacity` ended up governed by something that leaves it at 0 in
/// the hovered tree (measured: pinning it to `.opacity(0)` fails the second
/// expectation); if the reveal stopped consulting hover at all (measured:
/// `revealWidth` returning `CollapsedLayout.hoverReveal` unconditionally paints 99
/// `--bone` pixels at rest and fails the first); or if the reveal moved out of the
/// right flank into the cutout's own columns or the left one (§5.1/§5.2, the third).
///
/// **A green mutation, reported rather than patched.** An earlier draft of this test
/// claimed the third expectation would also fail if `.clipped()` were removed from
/// the reveal, on the strength of `content(cell:)`'s own comment calling it
/// "load-bearing" for §5.1. **It does not, and neither does anything else in the
/// suite** — deleting `.clipped()` leaves all 721 tests green. The reason is that
/// the reveal sits in an `.overlay` of an `IslandShape` that is itself
/// `.clipShape(IslandShape(…))`-ed (`IslandView.swift`, the collapsed half of the
/// silhouette `VStack`), so overflow to the right of the island is already cut
/// before `.clipped()` sees it. `.clipped()` is redundant on this path rather than
/// load-bearing, and that is a pre-existing inaccuracy in that comment, not
/// something Task 4 introduced. Left in place: proving which of two redundant clips
/// is doing the work would need both removed, and removing the outer one is a
/// change to §5.1's guarantee that no plan has asked for.
@MainActor @Test func aHoveredRenderStillPaintsTheRevealAndOnlyInTheFlank() throws {
    let geometry = IslandGeometry(screen: IslandGoldenTests.mbp14)

    func render(hovering: Bool) throws -> (raster: Raster, model: IslandModel) {
        let m = IslandModel(geometry: geometry,
                            motion: MotionPreference(chosen: .full, systemWantsReduced: false))
        m.state = .waiting
        m.sessionCount = 3
        m.sessions = MotionFidelityProbe.sessions(3)
        // `revealed` is its own property, not derived from `sessions` — the reveal
        // shows the most urgent session and `NotchController.render()` assigns both
        // from one ordering. Setting only `sessions` leaves `RevealContent(session:
        // nil)`, which renders an empty `HStack` and no `--bone` at all; this test's
        // first draft did exactly that and its "the reveal is painted" expectation
        // failed against correct code.
        m.revealed = MotionFidelityProbe.sessions(1).first
        m.hovering = hovering
        return (try rasterise(IslandView(model: m), scale: 1), m)
    }

    let rest = try render(hovering: false).raster
    let (hovered, hoveredModel) = try render(hovering: true)

    // `--bone` is the reveal's own project-name colour (`RevealContent`), and
    // nothing else in a collapsed island paints it — the cat is accent-tinted and
    // the tally is too.
    let restBone = rest.pixelCount(near: boneColour)
    let hoverBone = hovered.pixelCount(near: boneColour)
    #expect(restBone == 0,
            "a resting island paints \(restBone) --bone pixels — the reveal is visible with no cursor on it")
    #expect(hoverBone > 0,
            "a hovered island paints no --bone pixels at all, so the reveal's text is gone; the modifier reorder in content(cell:) has taken the opacity or the width with it")

    // Where those pixels are. Columns, so the claim is geometric: the reveal has
    // its own 150pt at the right-hand end of the island and must stay inside it.
    let bone = (r: Int((boneColour.r * 255).rounded()),
                g: Int((boneColour.g * 255).rounded()),
                b: Int((boneColour.b * 255).rounded()))
    var boneFirst = -1, boneLast = -1
    for x in 0..<hovered.width {
        for y in 0..<min(Int(geometry.notch.height.rounded()), hovered.height) {
            let p = hovered[x, y]
            if p.a > 0, abs(Int(p.r) - bone.r) <= 6, abs(Int(p.g) - bone.g) <= 6,
               abs(Int(p.b) - bone.b) <= 6 {
                if boneFirst < 0 { boneFirst = x }
                boneLast = x
                break
            }
        }
    }
    try #require(boneFirst >= 0, "no --bone pixels above the notch line to locate")

    let panelMinX = hoveredModel.frames.panel.minX
    let lastCutoutColumn = Int((geometry.notch.maxX - panelMinX).rounded()) - 1
    // The span, `boneFirst…boneLast`, is reported in the message and deliberately
    // **not** asserted against `CollapsedLayout.hoverReveal`. A draft did assert it
    // and that was a second green mutation: laying the reveal out at `revealWidth *
    // 2` — F1 of Plan 5's final review, the overrun that squeezes §5.4's session
    // count — leaves this render's `--bone` span unchanged, because the span measures
    // the *project name's own ink* rather than the frame it sits in, and the text is
    // leading-aligned so a wider frame does not move it. "A short string fits in
    // 150pt" cannot fail. F1's real symptom is the tally being squeezed, and
    // `IslandGoldenTests`' `theSessionCountSurvivesAnOpenDrawerWhileHovering`
    // measures that.
    #expect(boneFirst > lastCutoutColumn,
            "the reveal's --bone ink spans columns \(boneFirst)…\(boneLast) and starts inside or left of the cutout (which ends at \(lastCutoutColumn)) — §5.1 forbids content in the hole and §5.2 puts the reveal in the right flank")
}
