import Foundation
import SwiftUI
import Testing
import VibeCatCore
@testable import VibeCatUI

// ─────────────────────────────────────────────────────────────────────────────
// Plan 6.3 Task 3. Two separate jobs, and they fail on different mutations:
//
//   1. the curve is the prototype's `--ease` and not something near it, and
//   2. §9.1's two shape springs are wired to their own half of the morph.
//
// The second is the one Plan 6.3 Task 2 could only report and not close: it
// found that pointing the *width* modifier at `IslandMotion.heightDamping`
// leaves the entire suite green, because the suite asserted the two constants'
// values and never which modifier consumed which.
// ─────────────────────────────────────────────────────────────────────────────

/// A CSS `cubic-bezier`'s y at a given x, by bisection on x — computed here
/// independently of anything in `Sources`, so this file's expected values do not
/// come from the code under test.
///
/// (`MotionFidelityProbe.bez` is the same routine. Deliberately not shared: that
/// file is a throwaway probe with a "delete once the plan has landed" header, and
/// these assertions must outlive it.)
private func cssBezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double,
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

/// `island-motion.html:24` and `settings.html:27`, both verbatim:
/// `--ease: cubic-bezier(.22,.9,.28,1)`.
private func ease(_ x: Double) -> Double { cssBezier(0.22, 0.9, 0.28, 1, atX: x) }

// MARK: - 1. The curve is the prototype's, at every interior point

/// **`island-motion.html:24`'s `--ease: cubic-bezier(.22,.9,.28,1)`, sampled.**
///
/// Two things are being checked at once, and the second is what makes the first
/// worth writing:
///
/// - `IslandMotion.easeCurve` — the exact `UnitCurve` production animates on —
///   agrees with an independently computed bezier at ten interior points. This
///   also pins down what `UnitCurve.bezier(startControlPoint:endControlPoint:)`
///   *means*: that the two points are CSS's two interior control points with
///   `(0,0)`/`(1,1)` implied, rather than, say, tangent vectors. Measured
///   agreement over 999 points is 2.4e-6, which is bisection residue on both
///   sides, so the tolerance below is 1e-4 and not a widened slop.
/// - the same ten samples **reject** `.easeOut` and `.easeInOut`, the two curves
///   this code used before. A test that could not tell them apart would be
///   testing nothing: it would pass on the very code Task 3 exists to replace.
///
/// Would fail if: `easeCurve`'s control points were mistyped or transposed (0.9
/// and 0.28 swapped moves p=0.3 from 0.824 to 0.516); if a call site went back to
/// a built-in curve *and* `easeCurve` were deleted with it; or if a future SwiftUI
/// reinterpreted `UnitCurve.bezier`'s arguments.
///
/// What it does **not** prove: that any `.animation` modifier uses this curve.
/// `theEaseSitesAreReachedByARealRender` covers each of the five sites *requesting*
/// it, and `theFiveEaseSitesAllRouteThroughIslandMotion` covers no site building
/// its own copy; both state their own limits.
@Test func theEaseCurveIsThePrototypeBezierAtEveryInteriorPoint() {
    // Ten interior points. The endpoints are excluded on purpose: every unit
    // curve in existence passes through (0,0) and (1,1), so asserting them is
    // the archetype of an assertion that cannot fail.
    let samples = (1...10).map { Double($0) / 11 }

    for p in samples {
        let want = ease(p)
        let got = IslandMotion.easeCurve.value(at: p)
        #expect(abs(got - want) < 1e-4,
                "IslandMotion.easeCurve is not cubic-bezier(.22,.9,.28,1): at p=\(p) it reads \(got) where the prototype's curve is \(want)")
    }

    // The discrimination half. `UnitCurve.easeOut`/`.easeInOut` are documented as
    // the curves `Animation.easeOut`/`.easeInOut` use, so this is the same
    // comparison the four replaced call sites embodied.
    func worst(_ curve: UnitCurve) -> (deviation: Double, at: Double) {
        var w = (0.0, 0.0)
        for step in 1...999 {
            let p = Double(step) / 1000
            let d = abs(curve.value(at: p) - ease(p))
            if d > w.0 { w = (d, p) }
        }
        return w
    }
    let eo = worst(.easeOut), eio = worst(.easeInOut)
    #expect(eo.deviation > 0.30,
            "SwiftUI's .easeOut is within \(eo.deviation) of --ease everywhere, so the ten samples above cannot distinguish the curve this task replaced from the one it installed and prove nothing")
    #expect(eio.deviation > 0.30,
            "SwiftUI's .easeInOut is within \(eio.deviation) of --ease everywhere — same problem")

    // And the samples themselves must be where the difference lives, not merely
    // somewhere on the curve: each of the ten rejects both built-ins outright.
    for p in samples {
        #expect(abs(UnitCurve.easeOut.value(at: p) - ease(p)) > 1e-2,
                "sample p=\(p) cannot tell --ease from .easeOut")
        #expect(abs(UnitCurve.easeInOut.value(at: p) - ease(p)) > 1e-2,
                "sample p=\(p) cannot tell --ease from .easeInOut")
    }
}

/// The measured size of the divergence Task 3 removed, recorded as an assertion
/// so the numbers in `IslandMotion`'s doc comment and this plan's report cannot
/// quietly stop being true.
///
/// `.easeOut` is 38.1 percentage points behind `--ease` at p=0.273 — which at the
/// hover reveal's 280ms is 76ms, and is the same divergence the motion-fidelity
/// investigation reported as "38.1% behind at 75ms". `.easeInOut` is 63.8 points
/// off at p=0.288. Both are worst *early*: `--ease` leaps and both built-ins ramp.
///
/// Would fail if: SwiftUI's built-in curves changed shape (they are CSS
/// `ease-out` = `cubic-bezier(0,0,.58,1)` and `ease-in-out` =
/// `cubic-bezier(.42,0,.58,1)`, asserted below to that identity, which is how the
/// two numbers above are attributable at all).
@Test func theBuiltInCurvesWeUsedAreCssEaseOutAndEaseInOut() {
    for step in 1...999 {
        let p = Double(step) / 1000
        #expect(abs(UnitCurve.easeOut.value(at: p) - cssBezier(0, 0, 0.58, 1, atX: p)) < 1e-4,
                "UnitCurve.easeOut is no longer CSS ease-out at p=\(p); the 38.1pp figure recorded for the curve it replaced is attributed to the wrong bezier")
        #expect(abs(UnitCurve.easeInOut.value(at: p) - cssBezier(0.42, 0, 0.58, 1, atX: p)) < 1e-4,
                "UnitCurve.easeInOut is no longer CSS ease-in-out at p=\(p)")
    }

    func worstEarly(_ curve: UnitCurve) -> (deviation: Double, at: Double) {
        var w = (0.0, 0.0)
        for step in 1...999 {
            let p = Double(step) / 1000
            let d = abs(curve.value(at: p) - ease(p))
            if d > w.0 { w = (d, p) }
        }
        return w
    }
    let eo = worstEarly(.easeOut)
    #expect(abs(eo.deviation - 0.3814) < 0.001 && abs(eo.at - 0.273) < 0.01,
            ".easeOut's worst deviation from --ease measured \(eo.deviation) at p=\(eo.at); IslandMotion's doc comment and Plan 6.3's report both say 0.3814 at 0.273")
    let eio = worstEarly(.easeInOut)
    #expect(abs(eio.deviation - 0.6375) < 0.001 && abs(eio.at - 0.288) < 0.01,
            ".easeInOut's worst deviation from --ease measured \(eio.deviation) at p=\(eio.at); the recorded figure is 0.6375 at 0.288")
}

/// **The written decision, as numbers.** `CatCanvas`'s and `BadgeCanvas`'s looping
/// transforms keep `.easeInOut` where the prototype's keyframes say `var(--ease)`,
/// and that is a divergence with a measurement behind it rather than an
/// unconverted site.
///
/// CSS applies `animation-timing-function` to **each keyframe interval**, so
/// `animation:drowse 3s var(--ease) infinite` over `0%,100%{rest} 50%{extreme}`
/// runs `--ease` forwards twice. SwiftUI's `.repeatForever(autoreverses: true)`
/// runs it forwards and then **mirrored**. For a curve as front-loaded as `--ease`
/// (95% of travel by half its interval) the mirror sits near the extreme exactly
/// where CSS has already left it, so the two are nearly anti-phase on the return
/// leg — and routing these two sites through `IslandMotion.ease` would make the
/// worst deviation 42% *larger*.
///
/// Would fail if: someone "finished the sweep" by pointing those two sites at
/// `IslandMotion.ease` — the ordering below is exactly the claim that would make
/// wrong, and the comments at both sites cite these numbers.
@Test func theLoopingKeyframeCurvesAreADeliberateDivergence() {
    /// Where the value sits at fraction `u` of a *full* cycle, per CSS.
    func cssCycle(_ u: Double) -> Double {
        u <= 0.5 ? ease(2 * u) : 1 - ease(2 * u - 1)
    }
    /// The same, for `.animation(.curve(duration: period/2).repeatForever(autoreverses: true))`.
    func autoreversed(_ curve: UnitCurve, _ u: Double) -> Double {
        u <= 0.5 ? curve.value(at: 2 * u) : curve.value(at: 2 - 2 * u)
    }
    func worst(_ curve: UnitCurve) -> Double {
        (0...1000).map { abs(autoreversed(curve, Double($0) / 1000) - cssCycle(Double($0) / 1000)) }.max()!
    }

    let ours = worst(.easeInOut)
    let theSweep = worst(IslandMotion.easeCurve)
    #expect(abs(ours - 0.6375) < 0.001,
            ".easeInOut's worst full-cycle deviation measured \(ours); CatCanvas's comment records 0.638")
    #expect(abs(theSweep - 0.9031) < 0.001,
            "--ease's worst full-cycle deviation measured \(theSweep); CatCanvas's comment records 0.903")
    #expect(theSweep > ours,
            "--ease autoreversed is now closer to the CSS keyframe figure than .easeInOut (\(theSweep) against \(ours)) — the decision recorded at CatCanvas.swift and BadgeCanvas.swift is stale and those two sites should be swept after all")
}

// MARK: - 2. §9.1's two springs are wired to their own half of the morph

/// **The hole Plan 6.3 Task 2 reported and could not close.**
///
/// Task 2's finding: swapping `IslandBody`'s width `.animation` to
/// `dampingFraction: IslandMotion.heightDamping` leaves the **entire suite**
/// green. So §9.1's central rule — *"width overshoots more than height, so the
/// island reads as one body with mass rather than a resizing box"* — was asserted
/// only as two numbers (`MotionCurveComparison.widthOvershootsFarMoreThanHeight
/// AsTheDesignRequires`) with nothing tying either number to the modifier that
/// consumes it.
///
/// The two curves are now named `Animation` accessors with DEBUG read counters,
/// and the binding is that **the two bodies are evaluated separately**:
///
/// | evaluated | `widthSpring` | `heightSpring` |
/// |---|---|---|
/// | `IslandBody.body` | **2** | 0 |
/// | `IslandView.body` | 0 | 1 |
///
/// Four facts, not two, and that is what makes both mutations fail:
///
/// - **the reported mutation** (a width site reads the height spring, or the height
///   damping inline): row 1 becomes `1 / 1` for the accessor form and `1 / 0` for
///   the inline form. Fails on the first row's first expectation either way.
/// - **swapping the two sites wholesale**: row 1 becomes `0 / 2` and row 2 becomes
///   `2 / 0`, which a single combined count could not see. Fails on both rows.
///
/// **The `2` is Plan 6.3 Task 4's**, and it is not slop. The island has *two* width
/// morphs — the click (`value: restingWidth`) and the hover reveal's shape half
/// (`value: hoverRevealWidth`) — and the prototype puts both on the one
/// `--spring-w` token, `.island{transition:width var(--t-shape) var(--spring-w)}`
/// at island-motion.html:84. Before Task 4 the hover site was
/// `IslandMotion.ease(duration: 0.28)`, so **collapsing hover back onto one
/// `--ease` clock reads `1 / 0` here and fails.** What `2` cannot say — and `1`
/// could not either — is which of the two width modifiers got the spring; the
/// ordering assertion in `HoverMotionTests` is what covers the hover one
/// specifically.
///
/// The zeros are load-bearing and are not an accident of `Group`: `.animation(_:
/// value:)` evaluates its first argument eagerly where it is written, and building
/// `IslandView.body` constructs an `IslandBody` value without running its `body`
/// (the mechanism `IslandView.buildCount` already relies on). So the zeros say
/// "this curve is not installed at this level", which is exactly the claim.
///
/// What this does **not** prove — the same limit `IslandBody.restingWidthReadCount`
/// states of itself: that the `Animation` read reached the modifier rather than
/// being read and discarded, or that SwiftUI interpolated anything with it.
/// Inspecting the built view tree for that needs a view-inspection dependency this
/// project does not take. Paired with `MotionCurveComparison`'s overshoot
/// assertion on the two *values*, both halves of §9.1 are now covered: the numbers,
/// and which modifier gets which.
@MainActor @Test func theTwoShapeSpringsAreWiredToTheirOwnHalfOfTheMorph() {
    let geometry = IslandGeometry(screen: IslandGoldenTests.mbp14)

    func freshModel() -> IslandModel {
        let m = IslandModel(geometry: geometry,
                            motion: MotionPreference(chosen: .full, systemWantsReduced: false))
        m.state = .waiting
        m.sessionCount = 3
        m.sessions = []
        m.hovering = true
        m.drawerOpen = true      // so the height spring has a drawer to be about
        return m
    }

    // Row 1 — the collapsed silhouette's own body. Both width morphs live here:
    // the click (`value: restingWidth`) and the hover reveal's shape half
    // (`value: hoverRevealWidth`), hence 2.
    IslandMotion.widthSpringReadCount = 0
    IslandMotion.heightSpringReadCount = 0
    _ = IslandBody(model: freshModel(), now: Date()).body
    #expect(IslandMotion.widthSpringReadCount == 2,
            "IslandBody.body read widthSpring \(IslandMotion.widthSpringReadCount) times, expected 2 — one of the island's two width morphs (the click, or the hover reveal's shape half) is no longer keyed to the overshooting spring (Plan 6.3 Task 2's reported mutation, Task 4's collapse-to-one-clock mutation, or a deleted site)")
    #expect(IslandMotion.heightSpringReadCount == 0,
            "IslandBody.body read heightSpring \(IslandMotion.heightSpringReadCount) times, expected 0 — the drawer's nearly-critically-damped curve has been installed on the width, which is the mutation §9.1 forbids")

    // Row 2 — the drawer overlay, one level up. The height spring lives here.
    IslandMotion.widthSpringReadCount = 0
    IslandMotion.heightSpringReadCount = 0
    _ = IslandView(model: freshModel()).body
    #expect(IslandMotion.heightSpringReadCount == 1,
            "IslandView.body read heightSpring \(IslandMotion.heightSpringReadCount) times, expected 1 — the drawer height morph lost its own curve")
    #expect(IslandMotion.widthSpringReadCount == 0,
            "IslandView.body read widthSpring \(IslandMotion.widthSpringReadCount) times, expected 0 — the width's overshooting spring has been installed on the drawer's height, so the two are swapped")
}

/// The same wiring, checked through a *render* rather than a body access, because
/// a `body` access is not what production does: SwiftUI evaluates `IslandBody.body`
/// itself, and this is the only way to see that both curves are reached in one
/// pass over the real tree.
///
/// Deliberately a `>= 1 / total` shape rather than exact counts: `ImageRenderer`
/// may evaluate a body more than once, and pinning an exact number here would be
/// pinning `ImageRenderer`'s internals. The exact counts are
/// `theTwoShapeSpringsAreWiredToTheirOwnHalfOfTheMorph`'s job; this one's is that
/// **both** curves survive into a rendered island at all, which that test — which
/// never calls `IslandBody.body` from inside `IslandView` — cannot say.
///
/// Would fail if: either `.animation` modifier were deleted outright, which the
/// counter test above cannot distinguish from "the other one is missing too" in
/// the row where it expects 0.
@MainActor @Test func aRealRenderOfTheOpenIslandReachesBothShapeSprings() throws {
    let m = IslandModel(geometry: IslandGeometry(screen: IslandGoldenTests.mbp14),
                        motion: MotionPreference(chosen: .full, systemWantsReduced: false))
    m.state = .waiting
    m.sessionCount = 3
    m.sessions = MotionFidelityProbe.sessions(3)
    m.hovering = true
    m.drawerOpen = true

    IslandMotion.widthSpringReadCount = 0
    IslandMotion.heightSpringReadCount = 0
    _ = try rasterise(IslandView(model: m), scale: 1)
    #expect(IslandMotion.widthSpringReadCount >= 1,
            "a rendered open island never read widthSpring — §9.1's width morph is not in the tree SwiftUI actually builds")
    #expect(IslandMotion.heightSpringReadCount >= 1,
            "a rendered open island never read heightSpring — the drawer's height morph is not in the tree SwiftUI actually builds")
}

// MARK: - 3. Each `--ease` site is reached, and asks for the right duration

/// **Each of the five `--ease` surfaces, checked by building the body that owns
/// it** — so reverting any one of them to `.easeOut`/`.easeInOut` fails here and
/// not only in the source scan below.
///
/// `IslandMotion.easeDurationsRead` records the *duration* asked for, which is the
/// only thing that says which surface asked: 0.28 is `--t-hover`, 0.19 is
/// `--t-face`, 0.13 the session row's bare `130ms`, 0.18 the settings switch's
/// knob. A bare read count could not tell "the hover reveal reverted" from "the
/// row reverted".
///
/// Each surface is exercised on its own rather than through one render of
/// everything, because SwiftUI does not build a nested body when the enclosing one
/// is evaluated, and because `ImageRenderer` paints nothing inside a `ScrollView`
/// (recorded at `SessionListFaceTests`) — so a session row is never reached by
/// rendering the open island, and a test that tried would be asserting on
/// `ImageRenderer`'s internals.
///
/// Would fail if: any of the five reverted to a built-in curve; if a site's
/// duration drifted off the prototype's token (0.19 becoming 0.2 fails, which is
/// also what pins `FaceCrossfade.duration` to `--t-face`); or if the `.animation`
/// modifier were deleted from the surface entirely.
///
/// What it does **not** prove — the standing limit of every read counter here: that
/// the `Animation` returned reached a modifier, or that SwiftUI interpolated
/// anything with it.
@MainActor @Test func theEaseSitesAreReachedByARealRender() throws {
    func durations(_ build: () throws -> Void) rethrows -> Set<Double> {
        IslandMotion.easeDurationsRead = []
        try build()
        return IslandMotion.easeDurationsRead
    }

    // 1. `IslandBody`'s THREE `--ease` clocks — the hover reveal's `--t-hover`
    //    280ms width and its bare 160ms opacity (island-motion.html:125), plus the
    //    bottom-radius morph's `--t-shape` 440ms (line 86). One duration until Plan
    //    6.3 Task 4, two until Task 5; the set is the assertion, so any two of the
    //    three collapsing onto one clock drops an element and fails.
    //
    //    **The radius is the third and it is not on a spring.** Line 86 is
    //    `border-radius var(--t-shape) var(--ease)` inside the same rule whose other
    //    two clauses are `var(--spring-w)`, so the radius sharing the width's clock
    //    while taking the bezier is a distinction the prototype draws deliberately.
    //    `IslandMotion.shapeDuration` appearing here is what says our radius took
    //    the bezier: a radius put on `widthSpring` instead would leave this set at
    //    two elements.
    let model = IslandModel(geometry: IslandGeometry(screen: IslandGoldenTests.mbp14),
                            motion: MotionPreference(chosen: .full, systemWantsReduced: false))
    model.state = .waiting
    model.sessionCount = 3
    model.hovering = true
    let hover = durations { _ = IslandBody(model: model, now: Date()).body }
    #expect(hover == [IslandMotion.hoverFadeDuration, IslandMotion.hoverRevealDuration,
                      IslandMotion.shapeDuration],
            "IslandBody.body asked for --ease at \(hover), expected exactly [\(IslandMotion.hoverFadeDuration), \(IslandMotion.hoverRevealDuration), \(IslandMotion.shapeDuration)] — the hover reveal's width and fade are no longer on two separate clocks, one of them reverted, or the bottom-radius morph lost its --t-shape bezier")

    // 2. The drawer's face swap, `--t-face` 190ms (island-motion.html:173).
    let question = QuestionModel(event: VibeEvent(id: "e", cli: "claude-code", kind: .permission,
                                                  session: "s", cwd: "/tmp/p"))
    let drawer = durations {
        _ = DrawerView(question: question, sessions: [], accent: IslandState.waiting.accent,
                       width: DrawerFace.question.width, onAnswer: { _ in }).body
    }
    #expect(drawer == [FaceCrossfade.duration],
            "DrawerView.body asked for --ease at \(drawer), expected exactly [\(FaceCrossfade.duration)]")

    // 3. `QuestionFace`'s own sub-face swap — rows ↔ the reply field, same token.
    let face = durations {
        _ = QuestionFace(question: question, accent: .white, onAnswer: { _ in }).body
    }
    #expect(face == [FaceCrossfade.duration],
            "QuestionFace.body asked for --ease at \(face), expected exactly [\(FaceCrossfade.duration)]")

    // 4. A session row's background, a bare `130ms` (island-motion.html:346).
    let session = Session(event: VibeEvent(id: "r", cli: "claude-code", kind: .running,
                                           session: "s", cwd: "/tmp/p"),
                          now: Date(timeIntervalSince1970: 1_000_000))
    let row = durations { _ = SessionRow(session: session, now: Date()).body }
    #expect(row == [0.13],
            "SessionRow.body asked for --ease at \(row), expected exactly [0.13]")

    // 5. The settings switch, 180ms (settings.html:90). Rasterised, not
    //    body-accessed: the `.animation` lives in a private `ToggleStyle`, and
    //    `makeBody` only runs when something actually lays the `Toggle` out.
    let toggle = try durations { _ = try rasterise(SettingsSwitch(isOn: .constant(true))) }
    #expect(toggle == [0.18],
            "rendering SettingsSwitch asked for --ease at \(toggle), expected exactly [0.18] — settings.html:90 is `transform 180ms var(--ease)`")
}

// MARK: - 4. The five `--ease` sites route through the one constant

/// **Every `--ease` transition site reads `IslandMotion.easeCurve` and no site
/// builds its own bezier.** A grep-shaped assertion, and the honest reason it is
/// written as one: SwiftUI's `Animation` cannot be sampled from outside the
/// framework, so there is no way to ask a built view "which curve is on this
/// modifier". What *can* be checked is that no source file spells the four control
/// points out for itself, which is the failure mode the one-constant grouping
/// exists to prevent — §9.1's two springs went unchecked for four plans precisely
/// because they were assembled at their call sites.
///
/// The seven sites — five replaced by Plan 6.3 Task 3, the sixth split off the
/// first by Task 4, the seventh added by Task 5:
///
/// | site | prototype | was |
/// |---|---|---|
/// | `IslandView.swift` hover reveal **width**, 280ms | `island-motion.html:125` | `.easeOut` |
/// | `IslandView.swift` hover reveal **opacity**, 160ms | `island-motion.html:125` | *shared the 280ms clock* |
/// | `IslandView.swift` **bottom-radius morph**, 440ms | `island-motion.html:86` | *the radius was a constant 15* |
/// | `DrawerView.swift` face swap, 190ms | `island-motion.html:173` | `.easeInOut` |
/// | `QuestionFace.swift` sub-face swap, 190ms | `island-motion.html:173` | `.easeInOut` |
/// | `SessionRow.swift` row background, 130ms | `island-motion.html:346` | `.easeOut` |
/// | `SettingsSwitch.swift` track + knob, 180ms | `settings.html:89-90` | `.easeInOut` |
///
/// The fifth is the one the investigation missed: it counted only
/// `island-motion.html`'s uses, and `settings.html:27` declares the same token
/// verbatim.
///
/// **Counted per file rather than as a set of names**, because Task 4 made
/// `IslandView.swift` hold two of them and a `Set` would have swallowed that: a
/// mutation that deletes one of the island's two `--ease` clocks has to be visible
/// here. `theRevealsTwoClocksSitOnTheirOwnProperties` in `HoverMotionTests` is what
/// says the two are on the right properties; this only counts them.
///
/// **`IslandView.swift: 3` since Plan 6.3 Task 5, and the third is a decision this
/// test forced rather than a number nudged to make it pass.** Task 3 left this
/// assertion knowing Task 5 would have to break it, because the whole reason it
/// exists is that five `--ease` surfaces had drifted onto `.easeOut`/`.easeInOut`
/// unnoticed — so a new site must not be able to arrive silently either. What was
/// checked before editing it: that `island-motion.html:86` really does put
/// `border-radius` on `var(--ease)` and not on `var(--spring-w)` like the other two
/// clauses of the same rule; and that the radius reaches `IslandMotion.ease` **once**
/// in that file, as a single `let` in `IslandBody.body` shared by both silhouette
/// halves, rather than twice — two halves calling it separately would have made this
/// `4` and hidden which of them a later deletion took.
///
/// Would fail if: an eighth `--ease` surface were added with an inline
/// `.timingCurve(0.22, 0.9, 0.28, 1, …)`, or one of the seven reverted to a
/// built-in curve (the `.easeOut`/`.easeInOut` scan below).
@Test func theFiveEaseSitesAllRouteThroughIslandMotion() throws {
    let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()      // VibeCatUITests
        .deletingLastPathComponent()      // Tests
        .deletingLastPathComponent()      // repo root
        .appendingPathComponent("Sources/VibeCatUI")

    var easeCallers: [String] = []
    var builtInCurves: [String] = []
    var inlineBeziers: [String] = []

    let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!
    for case let url as URL in files where url.pathExtension == "swift" {
        let name = url.lastPathComponent
        for line in try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n") {
            // Comments in this repo quote the curves they replaced at length;
            // only live code counts.
            guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") else { continue }
            if line.contains("IslandMotion.ease(") { easeCallers.append(name) }
            if line.contains(".easeOut(") || line.contains(".easeInOut(") { builtInCurves.append(name) }
            // `0.22` *and* `0.28` on one line of code is this bezier and very
            // little else. File names, not line numbers, throughout: this repo's
            // comments are long and a line number would make the assertion fail on
            // an edit three hundred lines above the thing it is about.
            if line.contains("0.22") && line.contains("0.28") && name != "IslandMotion.swift" {
                inlineBeziers.append(name)
            }
        }
    }

    let callsPerFile = Dictionary(grouping: easeCallers, by: { $0 }).mapValues(\.count)
    #expect(callsPerFile == ["IslandView.swift": 3, "DrawerView.swift": 1,
                             "QuestionFace.swift": 1, "SessionRow.swift": 1,
                             "SettingsSwitch.swift": 1],
            "the IslandMotion.ease call sites per file changed: \(callsPerFile.sorted { $0.key < $1.key }) — one of the seven --ease sites in the table above has gone (IslandView holds three since Task 5: the reveal's width, its opacity, and the bottom-radius morph), or an eighth arrived without a row")
    #expect(inlineBeziers.isEmpty,
            "a --ease bezier is spelled out away from IslandMotion in \(inlineBeziers) — that is how the two shape springs went unchecked for four plans")
    // The two that stay are the looping keyframe approximations, and
    // `theLoopingKeyframeCurvesAreADeliberateDivergence` is why.
    #expect(builtInCurves.sorted() == ["BadgeCanvas.swift", "CatCanvas.swift"],
            "the set of built-in easing curves left in VibeCatUI changed: \(builtInCurves.sorted()). Only CatCanvas's and BadgeCanvas's autoreversing keyframe approximations are allowed to keep one — see theLoopingKeyframeCurvesAreADeliberateDivergence")
}

// MARK: - 5. Plan 6.3 Task 5: the height trails the width by 30ms

/// **`island-motion.html:132`: `transition:height calc(var(--t-shape) + 30ms)
/// var(--spring-h)`.** So the drawer's height runs 470ms against the width's 440ms,
/// and the *lag* is the design content — the width leads and the body follows it
/// down, which is the other half of §9.1's "one body with mass" (the first half
/// being that the width overshoots 5.5× as far,
/// `widthOvershootsFarMoreThanHeightAsTheDesignRequires`). Both axes on one clock
/// is a box being rescaled.
///
/// **Asserted as the difference, never as two numbers.** `#expect(response ==
/// 0.42)` beside `#expect(heightResponse == 0.45)` passes intact if someone later
/// retunes both to 0.5 — the pair of literals would be wrong and the pair of
/// assertions would be updated together without anyone noticing the lag had gone.
/// The difference is the invariant, and the one thing the prototype actually
/// writes down (`+ 30ms`, in a `calc`).
///
/// **And it is not tautological**, which is the trap this repo has fallen into
/// before: `heightResponse` is spelled out as `0.45` and not as `response + 0.030`
/// precisely so this can fail. `IslandMotion.heightResponse`'s own doc comment
/// records that decision.
///
/// Would fail if: the two responses were equalised in either direction (the
/// mutation this task was asked to try); if the lag were applied to the width
/// instead, which the sign catches; or if the lag drifted to a "rounder" 50ms.
@Test func theDrawersHeightTrailsTheWidthByThePrototypes30ms() {
    #expect(IslandMotion.heightResponse > IslandMotion.response,
            "the drawer's height response (\(IslandMotion.heightResponse)s) does not exceed the width's (\(IslandMotion.response)s) — island-motion.html:132 runs the height LONGER, so either they have been equalised or the lag is on the wrong axis")

    let lag = IslandMotion.heightResponse - IslandMotion.response
    #expect(abs(lag - IslandMotion.heightLag) < 1e-9,
            "the height trails the width by \(lag * 1000)ms; island-motion.html:132's `calc(var(--t-shape) + 30ms)` is \(IslandMotion.heightLag * 1000)ms")
    #expect(IslandMotion.heightLag == 0.030,
            "IslandMotion.heightLag is \(IslandMotion.heightLag * 1000)ms, not the prototype's 30ms — the constant the assertion above compares against has itself moved")

    // The lag is small against the clocks it separates: 30ms on 440 is 6.8%, which
    // reads as a follow rather than as a second, separate movement. A "lag" that
    // doubled the height's clock would satisfy every assertion above.
    #expect(lag / IslandMotion.response < 0.10,
            "the height runs \(lag / IslandMotion.response * 100)% longer than the width — past about a tenth the drawer stops reading as the same body following and starts reading as a second animation")
}

/// **The bottom-radius morph is on `--ease` over `--t-shape`, and on neither
/// spring** — `island-motion.html:86`, the third clause of the one rule that moves
/// the island's shape:
///
/// ```
/// transition:width var(--t-shape) var(--spring-w),
///            transform var(--t-shape) var(--spring-w),
///            border-radius var(--t-shape) var(--ease);
/// ```
///
/// The radius shares the width's *clock* and refuses its *curve*, and that is a
/// deliberate distinction rather than an oversight in the mockup: `--spring-w`
/// overshoots 8%, so a radius on it would swell past 20pt and settle back. On a
/// width that reads as mass; on a corner it reads as a wobble.
///
/// `theEaseSitesAreReachedByARealRender` is what says a built `IslandBody.body`
/// actually asks for `--ease` at this duration. This says the duration is the
/// prototype's token and that it is not either spring's response — the two ways the
/// clock could be wrong while still being an `--ease` clock.
///
/// Would fail if: the radius were given `--t-hover`, `--t-face` or either spring's
/// response by copy-paste; or if `shapeDuration` were "tidied" to equal `response`,
/// which is the most plausible wrong edit, since 0.42 is what the springs use and
/// looks like the same number.
/// `@MainActor` only because `FaceCrossfade.duration` is — the comparison against
/// `--t-face` is the point of reaching for it.
@MainActor @Test func theRadiusMorphsOverTShapeOnTheEaseCurveAndNotOnEitherSpring() {
    #expect(IslandMotion.shapeDuration == 0.440,
            "--t-shape is 440ms at island-motion.html:25; shapeDuration is \(IslandMotion.shapeDuration * 1000)ms")
    #expect(IslandMotion.shapeDuration != IslandMotion.response,
            "the radius clock has been collapsed onto the width spring's response — 0.42 is §9.1's spring parameter with an asymptotic settle, 0.44 is a bezier's exact end, and they are not interchangeable")
    #expect(IslandMotion.shapeDuration != IslandMotion.heightResponse)
    #expect(IslandMotion.shapeDuration != IslandMotion.hoverRevealDuration,
            "the radius is on --t-hover, the reveal's clock, not --t-shape")
    #expect(IslandMotion.shapeDuration != FaceCrossfade.duration,
            "the radius is on --t-face, the crossfade's clock, not --t-shape")

    // `--ease` cannot overshoot, which is the property that makes it the right
    // curve for a corner and the wrong one for the width. Derived from the curve
    // production animates on, not from the four control points restated.
    var peak = 0.0
    for step in 0...1000 { peak = max(peak, IslandMotion.easeCurve.value(at: Double(step) / 1000)) }
    #expect(peak <= 1.0,
            "IslandMotion.easeCurve reaches \(peak) — a radius on an overshooting curve swells past 20pt and settles back, which is a wobble")
}

// MARK: - 6. §9.3 reaches the island's own six clocks

/// **The fourth §9.3 bypass, and the first that could be counted per site.**
///
/// Plan 6.1's Task 2 closed three — `IslandBody.phase`, `BadgeCanvas`, `CatCanvas`
/// — and made `motion:` a required, undefaulted parameter on the two canvases so a
/// fourth could not be added silently. The island's **own** six shape and hover
/// clocks were nonetheless never consulting the preference, because a `.animation`
/// modifier takes no `MotionPreference` and so there was no parameter to leave
/// undefaulted. `IslandMotion.gated(_:by:)` is that parameter, and this is the
/// assertion that a site cannot slip back out of it.
///
/// | evaluated | gated sites |
/// |---|---|
/// | `IslandBody.body` | the click's width spring, the hover's width spring, the reveal's 160ms fade, the reveal's 280ms width, the bottom-radius morph |
/// | `IslandView.body` | the drawer's height spring |
///
/// **Counted rather than sampled**, for the reason
/// `IslandMotion.gatedSuppressionCount` gives at length: a boolean "does anything
/// consult the preference" is satisfied by one site out of six, which is the exact
/// shape of the three bypasses that stood for four plans. `5 / 0` and `0 / 5` are
/// six independent facts.
///
/// Would fail if: any one of the six reverted to a bare `.animation(IslandMotion
/// .widthSpring, …)` (reads `4 / 0` at motion off); if `gated` returned its argument
/// unconditionally (reads `0 / 5` at off, so the first expectation fails); if the
/// gate were keyed to `chosen` rather than `effective` — that is
/// `MotionPreference.allowsMotion`'s job and `.noMotion` here has
/// `systemWantsReduced: false` deliberately, so a gate reading only the system
/// setting passes nothing; or if a seventh clock were added ungated (the totals
/// below are exact, not `>=`).
///
/// What it does **not** prove, the standing limit of every counter in this file: that
/// the `nil` reached the modifier, or that SwiftUI declined to interpolate.
@MainActor @Test func motionOffSuppressesEveryOneOfTheIslandsSixClocks() {
    let geometry = IslandGeometry(screen: IslandGoldenTests.mbp14)

    @MainActor func model(_ motion: MotionPreference) -> IslandModel {
        let m = IslandModel(geometry: geometry, motion: motion)
        m.state = .waiting
        m.sessionCount = 3
        m.sessions = []
        m.hovering = true
        m.drawerOpen = true
        return m
    }

    @MainActor func counts(_ build: () -> Void) -> (suppressed: Int, passed: Int) {
        IslandMotion.gatedSuppressionCount = 0
        IslandMotion.gatedPassCount = 0
        build()
        return (IslandMotion.gatedSuppressionCount, IslandMotion.gatedPassCount)
    }

    // A user who chose `off` with the system asking for nothing — the weaker of the
    // two inputs, so this proves the preference is honoured on its own rather than
    // riding on the system's coat-tails (`MotionPreference.noMotion`'s own note).
    let off = MotionPreference(chosen: .off, systemWantsReduced: false)
    let bodyOff = counts { _ = IslandBody(model: model(off), now: Date()).body }
    #expect(bodyOff == (suppressed: 5, passed: 0),
            "at motion off, IslandBody.body suppressed \(bodyOff.suppressed) of its clocks and let \(bodyOff.passed) through, expected 5 and 0 — one of the click's width spring, the hover's width spring, the reveal's fade, the reveal's width or the bottom-radius morph is not going through IslandMotion.gated")

    let viewOff = counts { _ = IslandView(model: model(off)).body }
    #expect(viewOff == (suppressed: 1, passed: 0),
            "at motion off, IslandView.body suppressed \(viewOff.suppressed) clocks and let \(viewOff.passed) through, expected 1 and 0 — the drawer's height spring is not gated")

    // Full motion: the same six sites, all reached, none suppressed. Without this
    // half, `gated` returning nil unconditionally would satisfy everything above —
    // and would silently delete every animation in the island.
    let full = MotionPreference(chosen: .full, systemWantsReduced: false)
    let bodyFull = counts { _ = IslandBody(model: model(full), now: Date()).body }
    #expect(bodyFull == (suppressed: 0, passed: 5),
            "at full motion, IslandBody.body suppressed \(bodyFull.suppressed) of its clocks and let \(bodyFull.passed) through, expected 0 and 5")

    let viewFull = counts { _ = IslandView(model: model(full)).body }
    #expect(viewFull == (suppressed: 0, passed: 1),
            "at full motion, IslandView.body suppressed \(viewFull.suppressed) clocks and let \(viewFull.passed) through, expected 0 and 1")
}

/// **`reduced` keeps the island moving, and `off` is the only level that stops it.**
///
/// §9.3's three levels are not "on / half / off": `MotionPreference.resolve(_:)`
/// expresses `reduced` as **halving `framesPerSecond` and nothing else**, and a
/// `.animation` transition has no frame rate this app paces — the render server
/// interpolates it. So the honest reading of `reduced` for a transition is
/// "unchanged", exactly as `IslandView.phase(at:cycle:motion:)` reads it for a
/// cycle, and inventing a shortened duration or a weakened overshoot here would be
/// a behaviour §9.3 does not describe.
///
/// The system override is checked in both directions because it is one-directional:
/// a system asking for less beats a user asking for more, and it never drags a user
/// who chose `off` back into motion.
///
/// Would fail if: `gated` were keyed to `chosen` rather than `effective` (row 4
/// would keep animating a system that asked for less); if it treated `reduced` as
/// `off` (rows 2 and 4); or if the `off` + `systemWantsReduced` row were promoted
/// back to motion, which is the specific mistake `MotionPreference.refreshed`'s own
/// doc comment records having been made once.
@MainActor @Test func onlyMotionOffSuppressesATransitionAndReducedIsUnchanged() {
    let cases: [(chosen: MotionLevel, system: Bool, animates: Bool, why: String)] = [
        (.full, false, true, "the default"),
        (.reduced, false, true, "reduced halves a frame rate; a transition has none to halve"),
        (.off, false, false, "the user asked for no motion"),
        (.full, true, true, "the system asks for less, which resolves to reduced — and reduced still moves"),
        (.off, true, false, "off stays off; the override never drags a user back into motion"),
        (.reduced, true, true, "already reduced"),
    ]
    for c in cases {
        let motion = MotionPreference(chosen: c.chosen, systemWantsReduced: c.system)
        let got = IslandMotion.gated(.linear(duration: 1), by: motion)
        #expect((got != nil) == c.animates,
                "chosen=\(c.chosen) system=\(c.system) resolved to \(motion.effective) and \(got == nil ? "suppressed" : "kept") the transition; expected it \(c.animates ? "kept" : "suppressed") — \(c.why)")
    }

    // The gate *is* `allowsMotion`, not a second reading of §9.3's precedence. If
    // this ever diverges, one of the two is wrong and there is no way to tell which.
    for chosen in MotionLevel.allCases {
        for system in [false, true] {
            let motion = MotionPreference(chosen: chosen, systemWantsReduced: system)
            #expect((IslandMotion.gated(.linear(duration: 1), by: motion) != nil)
                        == motion.allowsMotion,
                    "gated disagrees with MotionPreference.allowsMotion at chosen=\(chosen) system=\(system) — §9.3's precedence is being re-derived rather than reused")
        }
    }
}
