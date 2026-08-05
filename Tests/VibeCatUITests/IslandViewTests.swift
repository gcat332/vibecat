import Foundation
import SwiftUI
import Testing
import CoreGraphics
import VibeCatCore
@testable import VibeCatUI

private let t0 = Date(timeIntervalSince1970: 1_000_000)

private let mbp14 = ScreenMetrics(
    frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
    visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
    safeAreaTop: 32,
    auxLeft: CGRect(x: 0, y: 950, width: 663, height: 32),
    auxRight: CGRect(x: 848, y: 950, width: 664, height: 32))

private let externalDisplay = ScreenMetrics(
    frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
    visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1415),
    safeAreaTop: 0, auxLeft: nil, auxRight: nil)

@MainActor private func islandModel(_ state: IslandState, count: Int,
                                    hovering: Bool = false,
                                    motion: MotionLevel = .full,
                                    coat: Coat = .tabby,
                                    geometry: ScreenMetrics = mbp14) -> IslandModel {
    let m = IslandModel(geometry: IslandGeometry(screen: geometry),
                        motion: MotionPreference(chosen: motion, systemWantsReduced: false))
    m.state = state
    m.sessionCount = count
    m.hovering = hovering
    m.coat = coat
    return m
}

// MARK: - IslandView: the top-level branch (TimelineView vs. static)

@MainActor @Test func theViewEvaluatesForEveryStateAndCoat() {
    for state in IslandState.allCases {
        for coat in Coat.allCases {
            let m = islandModel(state, count: state == .dormant ? 0 : 2)
            m.coat = coat
            _ = IslandView(model: m).body
        }
    }
}

@MainActor @Test func theViewEvaluatesHoveredAndWithMotionOff() {
    _ = IslandView(model: islandModel(.running, count: 3, hovering: true)).body
    _ = IslandView(model: islandModel(.running, count: 3, motion: .off)).body
}

@MainActor @Test func theViewEvaluatesOnTheFallbackPill() {
    let m = IslandModel(geometry: IslandGeometry(screen: externalDisplay),
                        motion: MotionPreference(chosen: .full, systemWantsReduced: false))
    _ = IslandView(model: m).body
}

/// `.failed`'s cat (`dead`) and badge (`cross`) are both steady, so
/// `activeProfile.framesPerSecond` is genuinely 0 — yet a fresh aura bloom
/// still makes `needsTimeline` true (`IslandModel.needsTimeline` falls back
/// to `aura.isBlooming` once neither mood nor badge is continuous). This is
/// the one case where `IslandView.body` picks the `TimelineView` branch
/// with a zero-fps profile, exactly what `minimumInterval(for:)` guards
/// against below.
@MainActor @Test func theViewEvaluatesWithAnInFlightBloomOnASteadyState() {
    let m = islandModel(.failed, count: 1)
    var aura = AuraTrigger()
    _ = aura.observe(.idle, now: t0)
    _ = aura.observe(.failed, now: Date())
    m.aura = aura
    #expect(m.needsTimeline)
    #expect(m.activeProfile.framesPerSecond == 0)
    _ = IslandView(model: m).body
}

/// `IslandView.body`'s choice of `minimumInterval` can't be read back from
/// the `TimelineView` it builds — `TimelineSchedule` values are opaque to a
/// test — so the guard is pinned directly instead. Without it, the
/// steady-state-plus-bloom case above would compute `1.0 / 0` == `.infinity`,
/// which would let the schedule's first frame be its last — freezing the
/// glow instead of letting it fade, the one outcome `AuraTrigger`'s own doc
/// comment rules out ("a glow that stayed lit would be a second indicator").
@Test func minimumIntervalNeverDividesByZero() {
    #expect(IslandView.minimumInterval(for: MotionProfile(framesPerSecond: 12, cycle: 1, isContinuous: true))
            == 1.0 / 12.0)
    #expect(IslandView.minimumInterval(for: .still) == 1.0 / 8.0)
    #expect(IslandView.minimumInterval(for: .still).isFinite)
}

// MARK: - IslandBody: the actual layout

/// `IslandView.body` only evaluates its own top-level branch — when
/// `needsTimeline` is true that branch is a `TimelineView`, and its content
/// closure is `@escaping`: SwiftUI only invokes it during a real render
/// pass, never merely from accessing `.body` (the same hazard Task 8 found
/// and fixed for `Canvas`'s renderer closure, in `CatCanvas`/`BadgeCanvas`).
/// So the tests above, alone, never walk `IslandBody`'s own layout — the
/// flank paddings, the notch spacer, the right-flank switch, the
/// `CatCanvas`/`BadgeCanvas` construction. These evaluate `IslandBody`
/// directly, the way the pre-restructure suite's `evaluate` helper did, so
/// that code actually runs regardless of which branch `IslandView` takes.
@MainActor private func islandBody(_ state: IslandState, count: Int,
                                   hovering: Bool = false,
                                   coat: Coat = .tabby,
                                   geometry: ScreenMetrics = mbp14) -> IslandBody {
    IslandBody(model: islandModel(state, count: count, hovering: hovering,
                                  coat: coat, geometry: geometry),
               now: t0)
}

@MainActor @Test func theBodyEvaluatesForEveryStateAndCoat() {
    for state in IslandState.allCases {
        for coat in Coat.allCases {
            _ = islandBody(state, count: state == .dormant ? 0 : 2, coat: coat).body
        }
    }
}

@MainActor @Test func theBodyEvaluatesForEveryRightHandContent() {
    // 0 (nothing), 1, a multi-digit count, and one past the display limit —
    // the last one is the regression `sessionCountText`'s clamp exists for
    // (see CollapsedLayoutTests.sessionCountTextClampsBeyondTheDisplayLimit):
    // rendering the raw count instead of the clamped text would overflow the
    // reserved width and clip against the silhouette.
    for count in [0, 1, 999, 1_000_000] {
        _ = islandBody(.running, count: count).body
    }
}

@MainActor @Test func theBodyEvaluatesWhileHoveringAndOnTheFallbackPill() {
    _ = islandBody(.waiting, count: 3, hovering: true).body
    _ = islandBody(.dormant, count: 0, geometry: externalDisplay).body
}

/// Design §9.1's trap, guarded directly: a single `.animation(_, value:
/// body.width)` can only pick one curve, so a hover-driven change and a
/// content-driven change compete for it. `IslandBody` avoids this by keeping
/// the two contributions to the width as separate properties driven by
/// different inputs, so each can carry its own `.animation(value:)`. This
/// pins both halves at the data level: `restingWidth` must depend only on
/// content, never on `model.hovering`; `hoverRevealWidth` must depend only on
/// `model.hovering`, never on session count; and together they must still
/// sum back to the real `body.width`, so the split can never silently
/// diverge from what `IslandGeometry` actually computes.
///
/// This test never evaluates `.body` itself, so it only protects against one
/// specific regression — these two properties being *deleted* so the two
/// halves are re-merged into reading `model.frames.body.width` directly
/// (that fails to compile, since the properties this test names would no
/// longer exist). It does NOT protect against `body` being reverted to the
/// pre-Task-10 single-animation shape while these properties are left in
/// place, unreferenced by anything that draws — nothing here would notice,
/// because nothing here reads `body`.
/// `bodyActuallyRoutesThroughBothHalvesOfTheWidthSplit` right below is what
/// closes that half of the gap.
@MainActor @Test func theWidthSplitsIntoAContentHalfAndAnIndependentHoverHalf() {
    let atRest = islandBody(.running, count: 3, hovering: false)
    let hovered = islandBody(.running, count: 3, hovering: true)
    let moreSessionsHovered = islandBody(.running, count: 30, hovering: true)

    // restingWidth must not move when only hovering changes.
    #expect(atRest.restingWidth == hovered.restingWidth)
    // hoverRevealWidth must not move when only content changes.
    #expect(hovered.hoverRevealWidth == moreSessionsHovered.hoverRevealWidth)
    // hoverRevealWidth is driven by hovering alone, by exactly hoverReveal.
    #expect(atRest.hoverRevealWidth == 0)
    #expect(hovered.hoverRevealWidth == CollapsedLayout.hoverReveal)
    // The split is faithful: it must sum back to the real geometry, in both
    // states, including the dormant-and-hovered case Task 10 fixed.
    #expect(atRest.restingWidth + atRest.hoverRevealWidth == atRest.model.frames.body.width)
    #expect(hovered.restingWidth + hovered.hoverRevealWidth == hovered.model.frames.body.width)
    let dormantHovered = islandBody(.dormant, count: 0, hovering: true)
    #expect(dormantHovered.restingWidth + dormantHovered.hoverRevealWidth
            == dormantHovered.model.frames.body.width)
}

/// Closes the gap the comment above names: proves `body` itself — not just
/// the two properties in isolation — still routes its width through both
/// halves. `.frame(width:)` takes a plain `CGFloat`, not an `@autoclosure` or
/// an escaping one, so evaluating `.body` evaluates `restingWidth +
/// hoverRevealWidth` eagerly as ordinary Swift — there is no
/// TimelineView/Canvas-style escaping-closure hazard here, unlike the
/// `IslandView`-level tests above. If `body` were reverted to
/// `.frame(width: body.width, ...)` with one `.animation(_, value:
/// body.width)`, while `restingWidth`/`hoverRevealWidth` were left sitting
/// here unreferenced, evaluating `.body` would never touch either getter and
/// both counters would stay at 0 — which is exactly what a temporary
/// mutation of `body` back to that shape proved (see the fix-round note in
/// the task report).
///
/// This proves the properties are *read* during `body`'s construction — not
/// that the two `.animation` modifiers are wired to the *correct* one of the
/// two, or that the curves themselves are `.spring`/`.easeOut`.
///
/// This comment used to say confirming more "would need a snapshot or
/// view-inspection dependency, which this project does not take." Half of that
/// was wrong: `ImageRenderer` is a snapshot facility in the standard library,
/// and IslandGoldenTests.swift now uses it to check that the split reaches the
/// pixels — that hovering widens the *painted* island by exactly the reveal.
///
/// The counter still earns its place, because the two tests fail on different
/// mutations. Reverting `body` to `.frame(width: body.width)` with a single
/// `.animation` renders **identically** — the sum is the same number — so the
/// golden test cannot see it, and only the read counts go to zero. The render
/// covers geometry reaching the frame; the counter covers which value the
/// animation is keyed on. Neither supersedes the other.
@MainActor @Test func bodyActuallyRoutesThroughBothHalvesOfTheWidthSplit() {
    for hovering in [false, true] {
        IslandBody.restingWidthReadCount = 0
        IslandBody.hoverRevealWidthReadCount = 0
        let instance = islandBody(.running, count: 3, hovering: hovering)
        _ = instance.body
        #expect(IslandBody.restingWidthReadCount > 0,
                "body (hovering=\(hovering)) never read restingWidth — the width spring's input may have reverted to body.width")
        #expect(IslandBody.hoverRevealWidthReadCount > 0,
                "body (hovering=\(hovering)) never read hoverRevealWidth — the hover reveal's input may have reverted to body.width")
    }
}

/// **Plan 6.3 Task 2: which of the two curves carries the open morph — and the
/// investigation could not tell, so this is the answer written down.**
///
/// `.animation(_:value:)` installs its animation only for a transaction in which
/// its `value` changed. `IslandBody` carries two, on the same subtree: the §9.1
/// width spring keyed to `restingWidth`, and the 280ms hover-reveal ease keyed to
/// `hoverRevealWidth`. When `drawerOpen` flips, only one of those two keys may
/// move, or the question "which curve is this" has no answer.
///
/// It is `restingWidth` — and only because Task 1 made that property tier-aware.
/// While it hardcoded `tier: .rest` **neither** key changed on the click (the
/// investigation's finding: `hoverRevealWidth` cannot change either, because
/// `NotchController.click()` never clears the hover tier, so `model.hovering`
/// stays true for the whole life of an open drawer). Two unchanged keys means no
/// `.animation(value:)` installs at all and the width is left to whatever
/// transaction the drawer-height spring one level up in `IslandView` happens to
/// establish — which is exactly the ambiguity that could not be measured from a
/// static render, and is why the endpoints being right was not the whole answer.
///
/// Would fail if: `restingWidth` reverted to `tier: .rest` (the first assertion —
/// the key stops moving, and the width goes back to riding whatever curve it can
/// find), or if `revealWidth`'s job were moved into `hoverRevealWidth` so that
/// property started reacting to the drawer too (the second — both curves would
/// then install on the same change and the later modifier would silently win).
@MainActor @Test func theWidthSpringIsTheCurveTheOpenMorphIsKeyedTo() {
    // Hovered, because that is the only state a click can arrive in:
    // `NotchPanel.acceptsClicks` is gated on `model.hovering`.
    let closed = islandBody(.waiting, count: 3, hovering: true)
    let open = islandBody(.waiting, count: 3, hovering: true)
    open.model.drawerOpen = true
    #expect(open.model.tier.openFace != nil, "setup: the fixture never opened")

    #expect(open.restingWidth != closed.restingWidth,
            "restingWidth is \(closed.restingWidth) closed and \(open.restingWidth) open — the width spring's own key does not move on the click, so nothing keys a curve to the morph")
    #expect(open.hoverRevealWidth == closed.hoverRevealWidth,
            "hoverRevealWidth moved from \(closed.hoverRevealWidth) to \(open.hoverRevealWidth) on a change of drawer alone — the 280ms reveal ease now competes with the width spring for the same transaction")

    // The reveal is nevertheless *dropped* from the laid-out width, and it is
    // `revealWidth` that does it — one property, two callers, so the silhouette's
    // frame and `RevealContent`'s cannot disagree (F1 of Plan 4's final review).
    #expect(closed.revealWidth == CollapsedLayout.hoverReveal)
    #expect(open.revealWidth == 0,
            "the reveal survived into the open island at \(open.revealWidth)pt — the open width depends on hover again")
}

/// **Plan 6.3 Task 2's real question: does the width ever move *backwards*
/// mid-morph?** Endpoints being right does not answer it, and a transient dip
/// would be plainly visible.
///
/// The laid-out width is `restingWidth + revealWidth`, one `.frame(width:)`, so
/// SwiftUI interpolates it as a single animatable value along the one curve
/// `theWidthSpringIsTheCurveTheOpenMorphIsKeyedTo` identifies. This samples that
/// trajectory at 2ms over a second and asks two things of it:
///
/// - it never falls below where it started (**no dip**), and in particular never
///   reaches the collapsed 273.1pt the island used to *end* at; and
/// - it does overshoot its target, so the sampling is not vacuously passing on a
///   curve that simply does not move — §9.1's "one body with mass" is carried by
///   that overshoot, and `IslandMotion`'s own doc comment measures it at 8.3%.
///
/// The endpoints are read off the model rather than written down, so this is a
/// test of the production widths and not of two literals beside them.
///
/// Would fail if: the `.drawer` arm of `IslandGeometry.frames` went back to the
/// flank sum — `to` becomes 273.1 against a `from` of 423.1 and every sample
/// after the first is a backwards step, which is precisely the reported defect;
/// or if `IslandMotion.widthDamping` reached 1.0 and the overshoot vanished.
///
/// What it does **not** prove: that SwiftUI's own `.spring` sampler agrees with
/// `Spring.value(target:time:)` frame for frame. That is the same curve type from
/// the same framework fed the same two parameters, and the direction and
/// monotonicity of a spring's step response do not depend on the sampler.
@MainActor @Test func theOpenMorphNeverMovesTheWidthBackwards() {
    let closed = islandBody(.waiting, count: 3, hovering: true)
    let open = islandBody(.waiting, count: 3, hovering: true)
    open.model.drawerOpen = true
    let from = closed.restingWidth + closed.revealWidth
    let to = open.restingWidth + open.revealWidth
    #expect(to > from,
            "the morph runs \(from) → \(to): opening still narrows the island, so there is no forward direction for the rest of this test to check")

    let spring = Spring(response: IslandMotion.response, dampingRatio: IslandMotion.widthDamping)
    var lowest = to, highest = from
    for step in 0...500 {
        let w = from + (to - from) * spring.value(target: 1.0, time: Double(step) * 0.002)
        lowest = min(lowest, w)
        highest = max(highest, w)
    }
    // A hair of slop for the sampler, not for the rule: a real dip is bounded
    // below by the collapsed width the old code ended at, 150pt away.
    #expect(lowest >= from - 0.01,
            "the width dipped to \(lowest)pt from a start of \(from)pt — the island narrows part-way through the gesture that should only widen it")
    #expect(highest > to,
            "the width peaked at \(highest)pt against a target of \(to)pt — it never overshoots, so §9.1's width-overshoots-more rule is not in this morph and the samples above prove nothing about a curve that has no shape")
}

/// `IslandBody`'s left- and right-flank padding is a respelling, in SwiftUI's
/// `.padding`/`.frame` vocabulary, of `IslandGeometry.leftFlank` and
/// `CollapsedLayout.padding`. Nothing in the type system keeps a respelling
/// in sync with the constant it repeats — this is the cheapest available
/// substitute for eyes on the actual island, catching the moment the two
/// diverge and content starts sliding under the cutout, before anyone has to
/// notice it visually.
@Test func leftAndRightFlankLiteralsAgreeWithTheGeometryConstants() {
    let left = IslandBody.LeftFlankLayout.leadingPadding
             + IslandBody.LeftFlankLayout.catWidth
             + IslandBody.LeftFlankLayout.gap
             + IslandBody.LeftFlankLayout.badgeWidth
             + IslandBody.LeftFlankLayout.trailingPadding
    #expect(left == IslandGeometry.leftFlank)

    let sessionCountPadding = IslandBody.RightFlankLayout.leadingPadding
                             + IslandBody.RightFlankLayout.trailingPadding
    #expect(sessionCountPadding == CollapsedLayout.padding)

    let iconTotal = IslandBody.RightFlankLayout.iconPadding * 2 + CollapsedLayout.iconWidth
    #expect(iconTotal == CollapsedLayout.padding + CollapsedLayout.iconWidth)
}
