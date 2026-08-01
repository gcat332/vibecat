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

@MainActor
private func evaluate(_ screen: ScreenMetrics, _ state: IslandState,
                      _ right: CollapsedLayout.RightContent,
                      hovering: Bool, tier: IslandTier) {
    let g = IslandGeometry(screen: screen)
    let layout = CollapsedLayout(right: right, hovering: hovering)
    let frames = g.frames(rightFlank: layout.rightFlankWidth, tier: tier)
    _ = IslandBody(state: state, layout: layout, aura: AuraTrigger(),
                   now: t0, geometry: g, frames: frames).body
}

@MainActor @Test func theBodyEvaluatesForEveryState() {
    for state in IslandState.allCases {
        evaluate(mbp14, state, .sessionCount(2), hovering: false, tier: .rest)
    }
}

@MainActor @Test func theBodyEvaluatesForEveryRightHandContent() {
    let variants: [CollapsedLayout.RightContent] =
        [.nothing, .agentIcon, .sessionCount(0), .sessionCount(1), .sessionCount(999)]
    for right in variants {
        evaluate(mbp14, .running, right, hovering: false, tier: .rest)
    }
}

@MainActor @Test func theBodyEvaluatesWhileHoveringAndWithTheDrawerOpen() {
    evaluate(mbp14, .waiting, .sessionCount(3), hovering: true, tier: .hover)
    evaluate(mbp14, .waiting, .sessionCount(3), hovering: false,
             tier: .drawer(height: 288))
}

/// A notchless display has a zero-width dead zone; the spacer must cope.
@MainActor @Test func theBodyEvaluatesOnTheFallbackPill() {
    evaluate(externalDisplay, .dormant, .nothing, hovering: false, tier: .rest)
}

/// The wrapper pauses its timeline unless a bloom is in flight.
@MainActor @Test func theWrapperEvaluatesBothPausedAndRunning() {
    let g = IslandGeometry(screen: mbp14)
    let layout = CollapsedLayout(right: .sessionCount(1), hovering: false)
    let frames = g.frames(rightFlank: layout.rightFlankWidth, tier: .rest)

    var blooming = AuraTrigger()
    _ = blooming.observe(.idle, now: t0)
    _ = blooming.observe(.failed, now: t0)
    #expect(blooming.isBlooming(at: t0))

    for aura in [AuraTrigger(), blooming] {
        _ = IslandView(state: .failed, layout: layout, aura: aura,
                       now: t0, geometry: g, frames: frames).body
    }
}
