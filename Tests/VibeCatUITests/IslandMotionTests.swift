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

    // 1. The hover reveal's TWO `--ease` clocks — `--t-hover` 280ms on its width
    //    and a bare 160ms on its opacity (island-motion.html:125). One duration
    //    here until Plan 6.3 Task 4; the set is the assertion, so three equal
    //    clocks collapse it to one element and fail.
    let model = IslandModel(geometry: IslandGeometry(screen: IslandGoldenTests.mbp14),
                            motion: MotionPreference(chosen: .full, systemWantsReduced: false))
    model.state = .waiting
    model.sessionCount = 3
    model.hovering = true
    let hover = durations { _ = IslandBody(model: model, now: Date()).body }
    #expect(hover == [IslandMotion.hoverFadeDuration, IslandMotion.hoverRevealDuration],
            "IslandBody.body asked for --ease at \(hover), expected exactly [\(IslandMotion.hoverFadeDuration), \(IslandMotion.hoverRevealDuration)] — the hover reveal's width and fade are no longer on two separate clocks, or one of them reverted")

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
/// The six sites — five replaced by Plan 6.3 Task 3, the sixth split off the
/// first by Task 4:
///
/// | site | prototype | was |
/// |---|---|---|
/// | `IslandView.swift` hover reveal **width**, 280ms | `island-motion.html:125` | `.easeOut` |
/// | `IslandView.swift` hover reveal **opacity**, 160ms | `island-motion.html:125` | *shared the 280ms clock* |
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
/// Would fail if: a seventh `--ease` surface were added with an inline
/// `.timingCurve(0.22, 0.9, 0.28, 1, …)`, or one of the six reverted to a
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
    #expect(callsPerFile == ["IslandView.swift": 2, "DrawerView.swift": 1,
                             "QuestionFace.swift": 1, "SessionRow.swift": 1,
                             "SettingsSwitch.swift": 1],
            "the IslandMotion.ease call sites per file changed: \(callsPerFile.sorted { $0.key < $1.key }) — one of the six --ease sites in the table above has gone (IslandView holds two since Task 4: the reveal's width and its opacity), or a seventh arrived without a row")
    #expect(inlineBeziers.isEmpty,
            "a --ease bezier is spelled out away from IslandMotion in \(inlineBeziers) — that is how the two shape springs went unchecked for four plans")
    // The two that stay are the looping keyframe approximations, and
    // `theLoopingKeyframeCurvesAreADeliberateDivergence` is why.
    #expect(builtInCurves.sorted() == ["BadgeCanvas.swift", "CatCanvas.swift"],
            "the set of built-in easing curves left in VibeCatUI changed: \(builtInCurves.sorted()). Only CatCanvas's and BadgeCanvas's autoreversing keyframe approximations are allowed to keep one — see theLoopingKeyframeCurvesAreADeliberateDivergence")
}
