import Foundation
import SwiftUI

/// **Every curve the island moves on — the two §9.1 shape springs and the
/// prototype's `--ease` — in one place, handed out as `Animation` values rather
/// than as parameters a call site assembles for itself.**
///
/// The parameters used to be the whole of this type and the `.spring(…)` calls
/// were built at the two `.animation(_:value:)` sites, ~545 lines apart in
/// `IslandView`. That is why Plan 6.3 Task 2 could report a mutation that stays
/// green: **swapping the width modifier to `dampingFraction:
/// IslandMotion.heightDamping` left the entire suite passing**, because the
/// suite's only §9.1 assertion (`MotionCurveComparison`'s
/// `widthOvershootsFarMoreThanHeightAsTheDesignRequires`) reads the two
/// *constants* and never learns which modifier consumed which. Naming the whole
/// animation, and counting reads of each name, is what makes the wiring itself
/// checkable — see `widthSpringReadCount`.
///
/// ## The two shape springs
///
/// §9.1 says **"Width overshoots more than height, so the island reads as one
/// body with mass rather than a resizing box"**, and for four plans nothing
/// anywhere asserted it.
///
/// ### Retuned 2026-08-03, Plan 4.5, against the prototype
///
/// The prototype animates both over `--t-shape: 440ms` with explicit beziers:
/// `--spring-w: cubic-bezier(.32,1.5,.5,1)` and
/// `--spring-h: cubic-bezier(.34,1.22,.5,1)`. Plan 4.5's own note was that this
/// "will not be settled by matching numbers", because a spring settles
/// asymptotically where a bezier lands exactly. That is true about the *curve
/// shape* and it is not a reason to leave the difference unmeasured.
///
/// Measured by evaluating both (`MotionCurveComparison`, env-gated):
///
/// | | prototype | ours, before | ours, now |
/// |---|---|---|---|
/// | width overshoot | **8.0%** | 3.8% (`0.72`) | **8.3%** (`0.62`) |
/// | height overshoot | **1.5%** | 2.0% (`0.78`) | **1.5%** (`0.80`) |
/// | width÷height ratio | **5.3×** | 1.9× | **5.5×** |
///
/// So the old values did not merely differ from the prototype — **they nearly
/// erased the rule §9.1 states.** Width overshot only 1.9× as much as height
/// where the prototype has 5.3×, which is the difference between "one body with
/// mass" and "a resizing box". The overshoot is what carries that intent, so
/// matching the overshoot is what matching the prototype means here; the bezier's
/// exact shape cannot be reproduced by any spring and is recorded as a
/// deliberate, permanent divergence.
///
/// What is still not matched, and is not a defect: the prototype's width curve is
/// at 65.6% of its travel by 75ms where ours is at 35.8% — the worst deviation
/// between the two curves is 29.8%, and it is all front-loading. A bezier can
/// leap; a spring accelerates. That difference is inherent to the two mechanisms.
///
/// ## `--ease`, added 2026-08-05 by Plan 6.3 Task 3
///
/// `island-motion.html:24` declares a *third* curve —
/// `--ease: cubic-bezier(.22,.9,.28,1)` — for everything that is not a shape
/// spring. Plan 6.3's plan text says it is used 12 times; counted, it is **34**
/// (19 inside `transition:` declarations and 15 inside `animation:` shorthands),
/// and `settings.html:27` declares the identical token for 4 more. The transitions:
/// the hover reveal's `max-width`/`opacity`/`margin` (line 125), the face
/// crossfade's `opacity`/`transform`/`filter` (line 173), a session row's
/// `background` (line 346), the panel buttons (189, 194), the choice rows (306,
/// 322, 323), the settings switch's track and knob (`settings.html:89-90`), and the
/// open island's `border-radius` (line 86 — which Task 5 will need). The
/// `animation:` uses are all looping cat and badge keyframes, and those are a
/// measured exception; see `theLoopingKeyframeCurvesAreADeliberateDivergence`.
///
/// We had **none** of it. Five `.easeOut`/`.easeInOut` transition sites stood in,
/// and neither of those SwiftUI curves is this one: measured over 999 interior
/// points in `IslandMotionTests`, `.easeOut` is **38.1** percentage points off
/// `--ease` at its worst (p=0.273, which at the hover reveal's 280ms is 76ms — the
/// same divergence the motion-fidelity investigation reported as "38.1% behind at
/// 75ms") and `.easeInOut` is **63.8** points off at p=0.288. Both are worst
/// *early*, because `--ease` leaps where a built-in ramp accelerates.
///
/// **Cost: reasoned, not measured, and labelled as such.** Task 3 changed the
/// *shape* of four transitions and one settings transition and nothing about what
/// animates or how often — no timeline was added or removed, and the only
/// continuously ticking animations in the app (the `.repeatForever` cat and badge
/// transforms, which is where Plan 6.1's 0.38%-at-rest figure comes from) are
/// deliberately untouched. Swapping the curve on a `.animation(_:value:)` cannot
/// change the number of frames the render server interpolates, so the idle figure
/// is expected to be unchanged; it has **not** been re-measured here, and Plan
/// 6.3's own Global Constraints put that measurement on Task 6.
///
/// Exposed as a `UnitCurve` and not only as a finished `Animation` deliberately:
/// `Animation` cannot be sampled from outside SwiftUI, so an `Animation`-only
/// surface would leave the curve's *identity* unassertable and the fix would be
/// worth no more than the `.easeOut` it replaced. `UnitCurve.value(at:)` is
/// public, so `easeCurve` is the exact object production animates on **and** the
/// object the test evaluates against a bezier computed independently.
enum IslandMotion {
    // MARK: - §9.1's two shape springs

    /// §9.1's `0.42`, unchanged, and close to the prototype's own 440ms.
    static let response: Double = 0.42
    /// Overshoots 8.3%, against the prototype's 8.0%. Was `0.72` (3.8%).
    static let widthDamping: Double = 0.62
    /// Overshoots 1.5%, matching the prototype exactly. Was `0.78` (2.0%).
    static let heightDamping: Double = 0.80

    /// **The one animation the island's *width* may morph on** — §9.1's
    /// overshooting half. Sole caller: `IslandBody.body`'s
    /// `.animation(_:value: restingWidth)`.
    ///
    /// A computed property rather than a `let` so the DEBUG read counter can
    /// fire; the `Animation` it returns is the same value the inline
    /// `.spring(response:dampingFraction:)` built before.
    @MainActor static var widthSpring: Animation {
        #if DEBUG
        widthSpringReadCount += 1
        #endif
        return .spring(response: response, dampingFraction: widthDamping)
    }

    /// **The one animation the drawer's *height* may morph on** — §9.1's nearly
    /// critically damped half. Sole caller: `IslandView.body`'s
    /// `.animation(_:value: drawerHeight)`.
    @MainActor static var heightSpring: Animation {
        #if DEBUG
        heightSpringReadCount += 1
        #endif
        return .spring(response: response, dampingFraction: heightDamping)
    }

    #if DEBUG
    /// Counts reads of `widthSpring`; `heightSpringReadCount` is its twin.
    ///
    /// **What these two close.** Plan 6.3 Task 2 reported that pointing the width
    /// modifier at the *height* damping leaves the whole suite green, so §9.1's
    /// central rule was unguarded at the wiring level — the constants were
    /// asserted, their consumers were not. `theTwoShapeSpringsAreWiredToTheirOwn
    /// HalfOfTheMorph` in IslandMotionTests.swift evaluates `IslandBody.body` and
    /// `IslandView.body` *separately* and pins the counts on each: the width
    /// spring is read by the first and not the second, the height spring by the
    /// second and not the first. Because `.animation(_:value:)` evaluates its
    /// first argument eagerly at the call site, and because a `some View`
    /// property's body is not run by merely constructing the struct, those four
    /// counts are four independent facts about where each curve is installed. So
    /// the reported mutation now fails, and so does swapping the two sites
    /// wholesale — which a single combined count could not tell apart.
    ///
    /// **What they do not prove**, the same limit `IslandBody.restingWidthRead
    /// Count`'s own doc comment states: that the `Animation` reached the
    /// `.animation` modifier rather than being read and dropped, and that SwiftUI
    /// then interpolated anything with it. Introspecting the resulting view tree
    /// for the correct wiring needs a view-inspection dependency this project
    /// does not take; whether building a body touched a given curve can be
    /// counted directly, and that is the narrower, honest thing available. Paired
    /// with `MotionCurveComparison`'s overshoot assertion — which pins the two
    /// constants' *values* — the two together cover both halves of §9.1: the
    /// numbers, and which modifier gets which.
    ///
    /// `#if DEBUG`-gated for the reason `IslandView.buildCount` is: pure test
    /// instrumentation, and `swift test` already builds this library in debug.
    @MainActor static var widthSpringReadCount = 0
    /// Counts reads of `heightSpring`. See `widthSpringReadCount`.
    @MainActor static var heightSpringReadCount = 0
    #endif

    // MARK: - `--ease`

    /// `island-motion.html:24`'s `--ease: cubic-bezier(.22,.9,.28,1)`, as the
    /// samplable curve object rather than four numbers spelled out per call site.
    ///
    /// `UnitCurve.bezier` takes the same two interior control points CSS does,
    /// with `(0,0)` and `(1,1)` implied — asserted rather than assumed in
    /// `theEaseCurveIsThePrototypeBezierAtEveryInteriorPoint`, which compares it
    /// against an independent bisection evaluation of the same bezier.
    static let easeCurve = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.22, y: 0.9),
        endControlPoint: UnitPoint(x: 0.28, y: 1))

    /// The prototype's `transition:… <duration> var(--ease)`, for one duration.
    ///
    /// The duration stays a parameter because the prototype varies it per surface
    /// and the tokens are already named where they belong (`--t-hover` at the
    /// hover reveal, `--t-face` on `FaceCrossfade.duration`, a bare `130ms` on a
    /// row). What must not vary is the curve, which is the whole point of routing
    /// all of them through here.
    /// `@MainActor` for the DEBUG recorder below, and that is a real constraint on
    /// production and not only on tests: `--ease` may only be asked for from the
    /// main actor. Every one of the five sites is a `View`/`ToggleStyle` body, which
    /// already is. `response`/`widthDamping`/`heightDamping` stay unisolated so
    /// `MotionCurveComparison` can keep evaluating the two springs off-main.
    @MainActor static func ease(duration: Double) -> Animation {
        #if DEBUG
        easeDurationsRead.insert(duration)
        #endif
        return .timingCurve(easeCurve, duration: duration)
    }

    #if DEBUG
    /// Which durations `ease(duration:)` has been asked for since this was last
    /// emptied.
    ///
    /// Durations and not a bare count, because the duration is the only thing that
    /// says *which* `--ease` surface was reached: 0.28 is the hover reveal, 0.19 the
    /// face crossfade, 0.13 a session row, 0.18 the settings switch. So
    /// `theEaseSitesAreReachedByARealRender` can assert per-site rather than
    /// "something somewhere asked for the curve" — which is what makes reverting one
    /// site to `.easeOut` fail a test that evaluates a body, and not only the source
    /// scan in `theFiveEaseSitesAllRouteThroughIslandMotion`.
    ///
    /// A `Set` and not an ordered array, which was the first draft: this is appended
    /// to on *every* body build, and in a debug build of the actual app nothing ever
    /// empties it, so an array is an unbounded leak that grows with uptime. A set is
    /// bounded by the number of distinct `--ease` durations in the codebase — four.
    /// Nothing is lost: no site asks for two durations, so "which durations" already
    /// identifies the set of sites reached, and call order was never the claim.
    ///
    /// Same limit as every other read counter here and in `IslandView`: it proves
    /// the curve was *requested* while a body was built, not that the resulting
    /// `Animation` reached a modifier or that SwiftUI interpolated with it.
    @MainActor static var easeDurationsRead: Set<Double> = []
    #endif
}
