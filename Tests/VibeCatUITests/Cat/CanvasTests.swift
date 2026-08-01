import SwiftUI
import Testing
import CoreGraphics
@testable import VibeCatUI

@MainActor @Test func theCatCanvasEvaluatesForEveryCoatMoodAndPhase() {
    let palette = CatPalette(accent: IslandState.running.accent)
    for coat in Coat.allCases {
        for mood in CatMood.allCases {
            for i in 0...4 {
                let cat = ResolvedCat(coat: coat, mood: mood, phase: Double(i) / 4.0)
                _ = CatCanvas(cat: cat, palette: palette, cellSize: 1).body
            }
        }
    }
}

@MainActor @Test func theCatCanvasEvaluatesForEveryStatesPalette() {
    for state in IslandState.allCases {
        let cat = ResolvedCat(coat: .tabby, mood: CatMood(state: state), phase: 0.5)
        _ = CatCanvas(cat: cat, palette: CatPalette(accent: state.accent), cellSize: 1).body
    }
}

@MainActor @Test func theBadgeCanvasEvaluatesForEveryBadgeAndPhase() {
    for badge in Badge.allCases {
        for i in 0...4 {
            _ = BadgeCanvas(badge: badge, phase: Double(i) / 4.0,
                            tint: IslandState.waiting.accent, cellSize: 2).body
        }
    }
}

/// A zero or negative cell size must not trap.
@MainActor @Test func aDegenerateCellSizeDoesNotTrap() {
    let cat = ResolvedCat(coat: .tabby, mood: .trot, phase: 0)
    let palette = CatPalette(accent: IslandState.idle.accent)
    _ = CatCanvas(cat: cat, palette: palette, cellSize: 0).body
    _ = BadgeCanvas(badge: .bang, phase: 0, tint: IslandState.idle.accent, cellSize: 0).body
}
