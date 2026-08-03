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

/// `BadgeCanvas.canvasDrawCount` is the instrument `BadgeCPUProbe` reads to
/// answer the one question `Badge.pulse` records as unmeasured: does a
/// repeating `.scaleEffect`/`.opacity` re-invoke the `Canvas` renderer, or does
/// the render server run it without ever asking SwiftUI to draw again?
///
/// A probe reading is worth nothing unless the counter counts *draws*. So both
/// halves are asserted here, and the first is the one that matters: if merely
/// evaluating `body` incremented it, a growing count during the probe would
/// prove nothing about drawing, and this whole measurement would be the same
/// category of mistake as the one it exists to correct — pricing the wrong
/// mechanism.
///
/// Safe to read a shared counter despite the suite running in parallel: this
/// test is synchronous and `@MainActor`, so no other main-actor test code can
/// interleave inside it.
@MainActor @Test func theBadgeDrawCounterCountsDrawsRatherThanBodyEvaluations() throws {
    let tint = IslandState.dormant.accent

    let beforeBody = BadgeCanvas.canvasDrawCount
    for i in 0...4 {
        _ = BadgeCanvas(badge: .zzz, phase: Double(i) / 4.0, tint: tint, cellSize: 2).body
    }
    #expect(BadgeCanvas.canvasDrawCount == beforeBody,
            "evaluating body five times moved the draw counter by \(BadgeCanvas.canvasDrawCount - beforeBody) — it is counting body builds, not draws, so no probe reading taken with it can distinguish a transform from a redraw")

    let beforeRender = BadgeCanvas.canvasDrawCount
    _ = try rasterise(BadgeCanvas(badge: .zzz, phase: 0, tint: tint, cellSize: 2))
    #expect(BadgeCanvas.canvasDrawCount > beforeRender,
            "a real render never reached the Canvas renderer, so the counter can never register a redraw either")
}

/// A zero or negative cell size must not trap.
@MainActor @Test func aDegenerateCellSizeDoesNotTrap() {
    let cat = ResolvedCat(coat: .tabby, mood: .trot, phase: 0)
    let palette = CatPalette(accent: IslandState.idle.accent)
    _ = CatCanvas(cat: cat, palette: palette, cellSize: 0).body
    _ = BadgeCanvas(badge: .bang, phase: 0, tint: IslandState.idle.accent, cellSize: 0).body
}
