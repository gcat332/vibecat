import SwiftUI
import Testing
import CoreGraphics
import VibeCatCore
@testable import VibeCatUI

@MainActor @Test func theCatCanvasEvaluatesForEveryCoatMoodAndPhase() {
    let palette = CatPalette(accent: IslandState.running.accent)
    for coat in Coat.allCases {
        for mood in CatMood.allCases {
            for i in 0...4 {
                let cat = ResolvedCat(coat: coat, mood: mood, phase: Double(i) / 4.0)
                _ = CatCanvas(cat: cat, palette: palette, cellSize: 1, motion: .fullMotion).body
            }
        }
    }
}

@MainActor @Test func theCatCanvasEvaluatesForEveryStatesPalette() {
    for state in IslandState.allCases {
        let cat = ResolvedCat(coat: .tabby, mood: CatMood(state: state), phase: 0.5)
        _ = CatCanvas(cat: cat, palette: CatPalette(accent: state.accent), cellSize: 1,
                      motion: .fullMotion).body
    }
}

@MainActor @Test func theBadgeCanvasEvaluatesForEveryBadgeAndPhase() {
    for badge in Badge.allCases {
        for i in 0...4 {
            _ = BadgeCanvas(badge: badge, phase: Double(i) / 4.0,
                            tint: IslandState.waiting.accent, cellSize: 2,
                            motion: .fullMotion).body
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
        _ = BadgeCanvas(badge: .zzz, phase: Double(i) / 4.0, tint: tint, cellSize: 2,
                        motion: .fullMotion).body
    }
    #expect(BadgeCanvas.canvasDrawCount == beforeBody,
            "evaluating body five times moved the draw counter by \(BadgeCanvas.canvasDrawCount - beforeBody) — it is counting body builds, not draws, so no probe reading taken with it can distinguish a transform from a redraw")

    let beforeRender = BadgeCanvas.canvasDrawCount
    _ = try rasterise(BadgeCanvas(badge: .zzz, phase: 0, tint: tint, cellSize: 2,
                                  motion: .fullMotion))
    #expect(BadgeCanvas.canvasDrawCount > beforeRender,
            "a real render never reached the Canvas renderer, so the counter can never register a redraw either")
}

/// The measurement Plan 4.5's motion decisions rest on, and the correction of a
/// claim this codebase asserted for three plans without checking.
///
/// `ResolvedCat.verticalOffset` used to carry "Whole cells. Pixel art steps; a
/// fractional offset would blur the grid." **The opposite is true.** A translate
/// — whole *or* fractional, at 1× or 2× — leaves the sprite's palette exactly as
/// it is. It is `scale` that dissolves it, by an order of magnitude:
///
/// | transform | distinct colours @1× | @2× |
/// |---|---|---|
/// | `offset` 0 / −2 / −0.5 / −0.25 | 9 / 9 / 9 / 9 | 9 / 9 / 9 / 9 |
/// | `scaleEffect` 1.09 (the prototype's `callout`) | **95** | **130** |
/// | `scaleEffect` 1.12 (`catpop`'s peak) | 100 | 128 |
/// | `scaleEffect` 0.6 (`catpop`'s start) | 41 | 72 |
///
/// So the prototype's `translateY` motions can be matched exactly, and its
/// `scale`/`rotate` ones cannot without accepting a permanently soft sprite. That
/// is why `call` translates where the prototype scales, and why `happy` — alone —
/// is allowed to scale: it is a 540ms one-shot, so its blur ends.
///
/// **What this does and does not prove.** It measures `ImageRenderer`. The live
/// path is the render server transforming a cached layer, which cannot be sharper
/// than this and is very likely softer — the badge CPU probe measured 0 `Canvas`
/// draws during a repeating transform, which is direct evidence the bitmap is not
/// re-rendered at the scaled size. Treat these as a floor on the blur, not a
/// ceiling.
@MainActor @Test func theCatsGridSurvivesATranslateButNotAScale() throws {
    let cat = ResolvedCat(coat: .tabby, mood: .trot, phase: 0.6)
    let palette = CatPalette(accent: IslandState.running.accent)
    let sprite = CatCanvas(cat: cat, palette: palette, cellSize: 1, motion: .fullMotion)

    for scale in [CGFloat(1), 2] {
        let rest = try rasterise(sprite.padding(4), scale: scale).distinctColours.count
        for dy in [CGFloat(-2), -0.5, -0.25] {
            let moved = try rasterise(sprite.offset(y: dy).padding(4), scale: scale).distinctColours.count
            #expect(moved == rest,
                    "@\(Int(scale))x: translating by \(dy)pt took the palette from \(rest) colours to \(moved) — a translate must be exact, and `CatMood.pulse` chose translates on the strength of that")
        }
        let scaled = try rasterise(sprite.scaleEffect(1.09).padding(4), scale: scale).distinctColours.count
        #expect(scaled > rest * 5,
                "@\(Int(scale))x: scaling by the prototype's own 1.09 gave \(scaled) colours against \(rest) at rest — if a scale has stopped blurring, `call` and `dead` can match the prototype exactly and this decision should be revisited")
    }
}

/// A zero or negative cell size must not trap.
@MainActor @Test func aDegenerateCellSizeDoesNotTrap() {
    let cat = ResolvedCat(coat: .tabby, mood: .trot, phase: 0)
    let palette = CatPalette(accent: IslandState.idle.accent)
    _ = CatCanvas(cat: cat, palette: palette, cellSize: 0, motion: .fullMotion).body
    _ = BadgeCanvas(badge: .bang, phase: 0, tint: IslandState.idle.accent, cellSize: 0,
                    motion: .fullMotion).body
}
