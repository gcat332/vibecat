import Foundation
import SwiftUI
import Testing
import VibeCatCore
@testable import VibeCatUI

/// The reveal has 150pt for a project name *and* a duration, so the duration
/// has to be short: "5m", never "5 minutes ago". Boundaries are the whole test
/// — a formatter that reads well at 90s and lies at 3600s is the usual failure.
@Test func elapsedIsCompactAtEveryBoundary() {
    #expect(RevealContent.elapsed(0) == "0s")
    #expect(RevealContent.elapsed(59) == "59s")
    #expect(RevealContent.elapsed(60) == "1m")
    #expect(RevealContent.elapsed(3599) == "59m")
    #expect(RevealContent.elapsed(3600) == "1h")
    #expect(RevealContent.elapsed(86_399) == "23h")
    #expect(RevealContent.elapsed(86_400) == "1d")
}

/// §11's row wants two units where the reveal wants one — `state:'2m 14s'` and
/// `state:'0m 38s'` in the mockup's own `SESSIONS` — and it asks for them as a
/// **granularity on this formatter** rather than by growing a second one, so the
/// collapsed bar and the list can never come to disagree about what two minutes
/// looks like.
///
/// The last three expectations are the ones with teeth: they pin that asking for
/// the finer form does not change the coarse one, which is what "do not widen the
/// reveal to fix the row" means in practice. Mutation-verified: making `.fine` the
/// default parameter fails all three; dropping the `s < 3600` branch's `% 60` term
/// makes `0m 38s` read `0m 38s`… at 98 seconds too, and fails the second.
@Test func theFinerElapsedFormatIsTheRowsAndLeavesTheRevealsAlone() {
    #expect(RevealContent.elapsed(134, precision: .fine) == "2m 14s")
    #expect(RevealContent.elapsed(38, precision: .fine) == "0m 38s")
    #expect(RevealContent.elapsed(3599, precision: .fine) == "59m 59s")
    #expect(RevealContent.elapsed(3600, precision: .fine) == "1h 0m")
    #expect(RevealContent.elapsed(86_400, precision: .fine) == "1d 0h")
    #expect(RevealContent.elapsed(-5, precision: .fine) == "0m 0s")

    #expect(RevealContent.elapsed(134) == "2m", "the reveal's own format widened")
    #expect(RevealContent.elapsed(38) == "38s", "the reveal's own format widened")
    #expect(RevealContent.elapsed(3600) == "1h", "the reveal's own format widened")
}

/// Never a negative or an absurd string from a clock that went backwards — the
/// hook's `now` and the app's are two different clocks, and a session whose
/// `updatedAt` is a moment in this render's future is not a bug worth showing
/// a person "-0s" over.
@Test func elapsedNeverGoesBackwards() {
    #expect(RevealContent.elapsed(-5) == "0s")
}

/// The reveal must actually *reveal*: revealing nothing is the state this has
/// been in since Plan 2. Two renders differing only in `hovering`, and the
/// hovered one has to draw more.
///
/// `scale: 2`, not the `rasterise` default of 1 — measured: at scale 1 a
/// three-letter project name at 12.5pt anti-aliases so diffusely over the
/// near-black ground that only ~39 pixels land within `pixelCount(near:)`'s
/// tolerance of the exact bone value, short of this test's own 100-pixel
/// floor even though the label is genuinely painting. At scale 2 — the real
/// resolution every actual `mbp14` is Retina at — the same glyphs leave 215.
/// `AuraVisibilityTests` hits the identical need for the identical reason
/// (fine colour-threshold precision) and already sets `scale: 2` rather than
/// loosening its own tolerance or floor.
@MainActor @Test func hoveringRevealsTheProjectNameAndElapsedTime() throws {
    let model = IslandModel(geometry: IslandGeometry(screen: IslandGoldenTests.mbp14),
                            motion: MotionPreference(chosen: .full, systemWantsReduced: false))
    model.state = .running
    model.sessionCount = 1
    model.revealed = Session(event: VibeEvent(id: "e", cli: "claude-code", kind: .running,
                                              session: "s", cwd: "/Users/dev/api"),
                             now: Date(timeIntervalSince1970: 1_000_000))

    model.hovering = false
    let atRest = try rasterise(IslandBody(model: model, now: Date(timeIntervalSince1970: 1_000_030)), scale: 2)
    model.hovering = true
    let hovered = try rasterise(IslandBody(model: model, now: Date(timeIntervalSince1970: 1_000_030)), scale: 2)

    #expect(hovered.pixelCount(near: boneColour) > atRest.pixelCount(near: boneColour) + 100,
            "hovering added only \(hovered.pixelCount(near: boneColour) - atRest.pixelCount(near: boneColour)) --bone pixels — the reveal is still empty ground")
}
