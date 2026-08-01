import Foundation
import Testing
import CoreGraphics
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
    #expect(model(.dormant, count: 0).layout.rightFlankWidth == 0)
    #expect(model(.running, count: 2).layout.rightFlankWidth > 0)
}

/// The switch that reaches 0.0% CPU.
///
/// `.dormant` is deliberately not one of these: its badge (`zzz`) is
/// continuous even though its mood (`sleep`) is not, so it needs a timeline
/// too — see `aStillCatWithADriftingBadgeStillNeedsATimeline` below. `.failed`
/// and `.idle` are genuinely steady: neither mood nor badge is continuous.
@MainActor @Test func aSteadyStateNeedsNoTimeline() {
    #expect(model(.failed, count: 1).needsTimeline == false)
    #expect(model(.idle, count: 1).needsTimeline == false)
}

@MainActor @Test func anActiveStateNeedsATimeline() {
    #expect(model(.running, count: 1).needsTimeline)
    #expect(model(.waiting, count: 1).needsTimeline)
}

/// Dormant's badge is a drifting zzz, which does animate even though the cat
/// does not — so the timeline decision must consider both.
@MainActor @Test func aStillCatWithADriftingBadgeStillNeedsATimeline() {
    #expect(CatMood.sleep.motion.isContinuous == false)
    #expect(Badge.zzz.motion.isContinuous)
    let m = model(.dormant)
    m.coat = .tabby
    // The badge alone is enough to require redraws.
    #expect(m.activeProfile.isContinuous == Badge.zzz.motion.isContinuous)
    #expect(m.needsTimeline)
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
