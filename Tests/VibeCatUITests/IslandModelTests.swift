import Foundation
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

@MainActor private func model(_ state: IslandState = .dormant,
                              count: Int = 0,
                              motion: MotionLevel = .full) -> IslandModel {
    let m = IslandModel(geometry: IslandGeometry(screen: mbp14),
                        motion: MotionPreference(chosen: motion, systemWantsReduced: false))
    m.state = state
    m.sessionCount = count
    return m
}

@MainActor @Test func theModelDerivesMoodAndBadgeFromState() {
    let m = model(.running, count: 1)
    #expect(m.mood == .trot)
    #expect(m.badge == .squares)
}

@MainActor @Test func theModelDerivesTheLayoutFromTheSessionCount() {
    // Dormant is the corner minimum, not zero — see
    // `anEmptyRightFlankIsTheCornerMinimumAndHoldsNothing`. Comparing widths
    // rather than reading `> 0`, which the floor now makes true either way.
    #expect(model(.dormant, count: 0).layout.rightFlankWidth
            == IslandGeometry.minimumRightFlank)
    #expect(model(.running, count: 2).layout.rightFlankWidth
            > model(.dormant, count: 0).layout.rightFlankWidth)
}

/// §6.2: "configurable: session count (default), agent icon, or nothing."
/// `RightFlank` (Task 1) is the stored preference; `layout.right` is what
/// `IslandView` actually draws. This is Task 5's mapping between them.
///
/// What would have to break for this to fail: `layout` ignoring `rightFlank`
/// and always deriving `.sessionCount` from `sessionCount` alone, which is
/// exactly the hardcoded ternary this replaced (`IslandModel.layout` used to
/// read `sessionCount > 0 ? .sessionCount(sessionCount) : .nothing` with no
/// preference in the picture at all).
@MainActor @Test func theRightFlankPreferenceSelectsWhatLayoutRightDraws() {
    let m = model(.running, count: 3)
    #expect(m.rightFlank == .sessionCount,
            "setup: the model's default must match Preferences.rightFlank's own default (§6.2: session count)")
    #expect(m.layout.right == .sessionCount(3))

    m.rightFlank = .agentIcon
    #expect(m.layout.right == .agentIcon)

    m.rightFlank = .nothing
    #expect(m.layout.right == .nothing)
}

/// Decision, recorded here rather than only in `IslandModel.layout`'s own
/// comment: `.sessionCount` passes `sessionCount` through unconditionally,
/// even at zero, rather than special-casing zero to `.nothing` the way the
/// hardcoded ternary this replaced did. `CollapsedLayout` already treats
/// `.sessionCount(0)` as indistinguishable from `.nothing` on every axis that
/// matters — nil `sessionCountText`, the same corner-minimum
/// `rightFlankWidth`, `hasRightContent == false` — pinned by
/// `CollapsedLayoutTests.aZeroCountCollapsesToNothing`. This test pins that
/// the *value* passed to `CollapsedLayout` is `.sessionCount(0)`, not merely
/// that the *effect* happens to match `.nothing`'s.
@MainActor @Test func sessionCountPassesThroughEvenAtZeroRatherThanBeingSpecialCased() {
    let m = model(.dormant, count: 0)
    #expect(m.layout.right == .sessionCount(0),
            "expected the raw .sessionCount(0), not a re-derived .nothing")
    #expect(m.layout.rightFlankWidth == IslandGeometry.minimumRightFlank,
            "a zero count must still measure at the corner minimum, matching .nothing's own width")
}

/// The switch that reaches 0.0% CPU. All three steady states belong here:
/// `.dormant`'s badge (`zzz`) used to be a continuous drift even though its
/// mood (`sleep`) was not, so dormant needed a timeline anyway — see the
/// `motion` case comment on `Badge.zzz` for why that cost 3.6–4.1% of a core
/// for an animation that did not read as one. Now that `zzz` is still too,
/// `.dormant` is as steady as `.failed` and `.idle`: neither its mood nor its
/// badge is continuous.
@MainActor @Test func aSteadyStateNeedsNoTimeline() {
    #expect(model(.dormant, count: 1).needsTimeline == false)
    #expect(model(.failed, count: 1).needsTimeline == false)
    #expect(model(.idle, count: 1).needsTimeline == false)
}

@MainActor @Test func anActiveStateNeedsATimeline() {
    #expect(model(.running, count: 1).needsTimeline)
    #expect(model(.waiting, count: 1).needsTimeline)
}

/// Dormant's cat and badge are both still now — `sleep`'s mood and `zzz`'s
/// badge motion are neither one continuous — so, unlike before `zzz` was
/// made still, neither alone nor together do they require redraws.
@MainActor @Test func aStillCatWithAStillBadgeNeedsNoTimeline() {
    #expect(CatMood.sleep.motion.isContinuous == false)
    #expect(Badge.zzz.motion.isContinuous == false)
    let m = model(.dormant)
    m.coat = .tabby
    #expect(m.activeProfile.isContinuous == false)
    #expect(m.needsTimeline == false)
}

/// A bloom must keep the timeline alive even in a steady state.
@MainActor @Test func anAuraInFlightNeedsATimeline() {
    let m = model(.failed, count: 1)
    #expect(m.needsTimeline == false)
    var aura = AuraTrigger()
    _ = aura.observe(.idle, now: t0)
    _ = aura.observe(.failed, now: Date())
    m.aura = aura
    #expect(m.needsTimeline)
}

/// Motion off is the 0.0% case, whatever the state — even mid-bloom, which is
/// otherwise the one thing that keeps a steady state's timeline alive (see
/// `anAuraInFlightNeedsATimeline`). The aura must actually be blooming here:
/// a fresh, never-fired `AuraTrigger` would pass this assertion whether or
/// not `needsTimeline`'s `motion.effective == .off` short circuit runs at
/// all, since `activeProfile` is already forced non-continuous by
/// `MotionPreference.resolve` at `.off` — so it would prove nothing about
/// that circuit being load-bearing (Step 5).
@MainActor @Test func motionOffNeedsNoTimelineInAnyState() {
    for state in IslandState.allCases {
        let m = model(state, count: 1, motion: .off)
        var aura = AuraTrigger()
        _ = aura.observe(.idle, now: t0)
        _ = aura.observe(.running, now: Date())
        m.aura = aura
        #expect(m.needsTimeline == false, "\(state) still wants a timeline with motion off")
    }
}

@MainActor @Test func hoveringWidensTheDerivedLayout() {
    let m = model(.running, count: 2)
    let rest = m.layout.rightFlankWidth
    m.hovering = true
    #expect(m.layout.rightFlankWidth == rest + CollapsedLayout.hoverReveal)
}

/// Finding 5 of the final whole-branch review, at the data level:
/// `drawerWidth` must not move when `hovering` does, unlike `frames.body
/// .width` right above it — the whole point being that the drawer's own
/// width holds steady regardless of where the cursor drifts while a
/// question is open, which is the state an open drawer spends most of its
/// life in. `theDrawersContentDoesNotShiftWhenOnlyHoverChanges` in
/// DrawerGoldenTests.swift is the render-level version of the same claim.
@MainActor @Test func drawerWidthDoesNotDependOnHovering() {
    let m = model(.running, count: 3)
    let atRest = m.drawerWidth
    m.hovering = true
    #expect(m.drawerWidth == atRest,
            "drawerWidth moved from \(atRest) to \(m.drawerWidth)pt when only hovering changed")

    // Independently derived — the prototype's own literal for the face that is
    // showing, not read back off `m.drawerWidth`, which is the value under test.
    //
    // Plan 6.3 Task 1 replaced what stood here: `leftFlank + notch.width +
    // CollapsedLayout(hovering: false).rightFlankWidth`, which was the collapsed
    // island's width and is exactly the defect (§6.3 corrected 2026-08-05). It
    // passed for the whole of Plan 5 while the drawer was 287pt too narrow to
    // draw its own second line, because it restated the implementation's rule
    // instead of the design's number.
    #expect(m.drawerWidth == m.face.width,
            "drawerWidth is \(m.drawerWidth), expected the open face's own \(m.face.width)")
    #expect(m.drawerWidth == 560,
            "drawerWidth is \(m.drawerWidth) against the prototype's flat 560 (island-motion.html:162–164)")
}

/// **A face width, not a content width.** The measurement that opened Plan 6.3:
/// 1 and 3 sessions gave byte-identical open widths (273.1pt) and 12 gained 8.1pt
/// only because the tally reached two digits — so the drawer's width was a
/// function of digit count and nothing else.
///
/// 1 / 3 / 12 are the investigation's own counts, kept so the numbers in the plan
/// and the numbers here are the same numbers. 999 is added because it is the
/// clamp `CollapsedLayout.maxDisplayedSessions` enforces, and the widest the
/// collapsed flank can ever be.
///
/// Would fail if: `drawerWidth` went back to a `CollapsedLayout`-derived width,
/// or `DrawerFace.width` were made to consult a count.
@MainActor @Test func theOpenWidthIsTheSameAtEverySessionCount() {
    let widths = [1, 3, 12, 999].map { count -> CGFloat in
        let m = model(.waiting, count: count)
        m.drawerOpen = true
        return m.drawerWidth
    }
    #expect(Set(widths).count == 1,
            "the open width moved with the session count: \(widths) at 1 / 3 / 12 / 999")
    #expect(widths[0] == 560)
}

/// The tier is the one place the drawer's two dimensions come from, and it reaches
/// both of `frames`'s outputs.
///
/// Asserted through `model.frames` rather than `geometry.frames` directly, because
/// the model is what the view reads and `IslandModel.tier` is what assembles the
/// face — a `.drawer` arm that worked in the geometry but was never reached from
/// the model would leave the island exactly as broken as before.
///
/// Would fail if: `IslandModel.tier` returned `.rest`/`.hover` with `drawerOpen`
/// set, or `frames` stopped passing `tier` on.
@MainActor @Test func theModelsOwnFramesCarryBothOfTheOpenFacesDimensions() {
    let m = model(.waiting, count: 3)
    let closed = m.frames.body
    m.drawerOpen = true
    let open = m.frames.body

    #expect(m.face == .sessionList, "setup: no question, so the face should be the list")
    #expect(open.width == DrawerFace.sessionList.width,
            "the model's open body is \(open.width)pt, not the face's \(DrawerFace.sessionList.width)")
    #expect(open.height == closed.height + DrawerFace.sessionList.height,
            "the model's open body grew by \(open.height - closed.height)pt, not the face's \(DrawerFace.sessionList.height)")
    #expect(open.minX == closed.minX,
            "opening moved the left edge from \(closed.minX) to \(open.minX) — §5.3")
}
