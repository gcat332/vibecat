import Foundation
import SwiftUI
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
