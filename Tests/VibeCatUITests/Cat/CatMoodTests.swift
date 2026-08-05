import Testing
import VibeCatCore
@testable import VibeCatUI

@Test func eachIslandStateMapsToItsMood() {
    #expect(CatMood(state: .dormant) == .sleep)
    #expect(CatMood(state: .running) == .trot)
    #expect(CatMood(state: .waiting) == .call)
    #expect(CatMood(state: .idle) == .happy)
    #expect(CatMood(state: .failed) == .dead)
}

/// The spike's finding, encoded: any live timeline costs ~6% of a core, and
/// only removing it reaches 0.0%. Steady states must not have one.
@Test func onlyTheActiveMoodsAnimateContinuously() {
    #expect(CatMood.trot.motion.isContinuous)
    #expect(CatMood.call.motion.isContinuous)
    #expect(CatMood.sleep.motion.isContinuous == false)
    #expect(CatMood.dead.motion.isContinuous == false)
    #expect(CatMood.happy.motion.isContinuous == false)
}

/// 8–12 fps: authentic for pixel art, and 3x cheaper than 30.
@Test func continuousMoodsRunInThePixelArtRange() {
    for mood in CatMood.allCases where mood.motion.isContinuous {
        #expect(mood.motion.framesPerSecond >= 8)
        #expect(mood.motion.framesPerSecond <= 12)
    }
}

@Test func cycleLengthsMatchTheDesign() {
    #expect(CatMood.sleep.motion.cycle == 3.0)
    #expect(CatMood.trot.motion.cycle == 1.0)
    #expect(CatMood.call.motion.cycle == 1.1)
    #expect(CatMood.dead.motion.cycle == 2.4)
}

/// Design §7.2 — every mood must look different, but not always via the
/// eyes: `trot` and `call` are both "open"-eyed, distinguished only by
/// `call`'s open mouth (row 11). Comparing rows 7...9 alone asked the eyes to
/// carry a distinction the spec assigns to the mouth instead — widened to
/// rows 7...11 (eyes, nose, mouth) so the comparison matches what actually
/// varies between moods.
///
/// On this toolchain (swift-testing 1902), a bare `!` wrapped directly around
/// `.contains(_:)` mis-evaluates when the receiver holds optionals (see the
/// comment above `plainRemovesEveryShadowMarking` in CatGridTests.swift) — use
/// `== false`, not `!...contains(...)`, here too.
@Test func eachMoodGivesTheCatADifferentFace() {
    func faceRows(_ mood: CatMood) -> [[Tone?]] {
        let c = ResolvedCat(coat: .tabby, mood: mood, phase: 0).cells
        return Array(c[7...11])
    }
    var seen: [[[Tone?]]] = []
    for mood in CatMood.allCases {
        let rows = faceRows(mood)
        #expect(seen.contains(rows) == false, "\(mood) has the same face as an earlier mood")
        seen.append(rows)
    }
}

/// Design §7.2 names two different motions: a "quick bob" for `trot` and an
/// "attention pulse" for `call`. `offset` took the mood as a parameter but
/// used it only for the `isContinuous` guard, so both moods got the identical
/// one-cell step and the only thing telling them apart was the mouth.
///
/// Inequality of the two sequences is not enough on its own — a pure phase
/// shift would satisfy it while still being the same motion. Time spent
/// raised is the shape-sensitive part: trot is up for half its cycle in two
/// beats, call for a sixth of it in one.
/// **Superseded 2026-08-03 by `trotAndCallStillMoveDifferently`.** This asserted
/// on `ResolvedCat.verticalOffset`, the phase-driven whole-cell step that Plan 4.5
/// replaced with a view-level transform — so there is no per-phase step sequence
/// left to compare. The claim it defended is unchanged and still tested; only the
/// mechanism it read moved.
@Test func trotAndCallMoveToDifferentRhythms() throws {
    let trot = try #require(CatMood.trot.pulse)
    let call = try #require(CatMood.call.pulse)
    #expect(trot.period != call.period || trot.rise != call.rise,
            "trot and call move identically — they share one motion")
}

/// The mood-to-mood counterpart of `everyPairOfCoatsIsTellableApart`, and for
/// the same reason: `eachMoodGivesTheCatADifferentFace` above asserts `!=`,
/// which `call` satisfied with a two-cell mouth that widened an existing dark
/// mark rather than making a new shape.
///
/// The pair this exists for is `call` against `trot`, whose eyes are identical
/// by design — §7.2 distinguishes them by the mouth, so the mouth has to carry
/// the whole difference.
@Test func everyPairOfMoodsIsTellableApart() {
    let floor = 4
    let all = CatMood.allCases
    for i in all.indices {
        for j in all.indices where j > i {
            let a = ResolvedCat(coat: .tabby, mood: all[i], phase: 0).cells
            let b = ResolvedCat(coat: .tabby, mood: all[j], phase: 0).cells
            let differing = zip(a.joined(), b.joined()).count { $0 != $1 }
            #expect(differing >= floor,
                    "\(all[i]) and \(all[j]) differ by only \(differing) cells — under the \(floor)-cell floor, one reads as the other")
        }
    }
}

/// The eyes always win over a marking — §7.3. Scoped to the actual eye-box
/// cells (cols 3...5 and 12...14, the ones a mood's `setEyes` writes), not
/// the whole row: cells beside the eyes are ordinary fur, and a coat (e.g.
/// `.patched`, whose patch spans cols 12...16) is allowed to mark those —
/// see `noCoatTouchesTheEyes` in CatGridTests.swift, which scopes the same
/// way by tone rather than by column range.
@Test func moodOverridesBeatCoatMarkings() {
    let eyeCols = Array(3...5) + Array(12...14)
    for coat in Coat.allCases {
        let sleeping = ResolvedCat(coat: coat, mood: .sleep, phase: 0).cells
        let tabbySleeping = ResolvedCat(coat: .tabby, mood: .sleep, phase: 0).cells
        for row in 7...9 {
            for col in eyeCols {
                #expect(sleeping[row][col] == tabbySleeping[row][col],
                        "\(coat) changed the eye cell at \(col),\(row) under mood .sleep")
            }
        }
    }
}

/// Plan 4.5. The prototype's own keyframes, quoted from `island-motion.html`:
///
/// ```css
/// .cat.trot   {animation:trot 1s var(--ease) infinite}
/// @keyframes trot {0%,100%{transform:translateY(0)} 50%{transform:translateY(-2px)}}
/// ```
///
/// So `trot` is a **2pt** translate over a **1s** cycle, one beat, reversing.
/// Ours was a 1-cell step with *two* beats per cycle — half the amplitude and
/// twice the rhythm. The plan file caught the amplitude and not the rhythm.
///
/// `period` is the whole cycle; `CatCanvas` halves it for `autoreverses`, which
/// is what the prototype's `0%,100% … 50%` shape means.
@Test func trotTravelsThePrototypesTwoPointsOverItsOwnSecond() throws {
    let trot = try #require(CatMood.trot.pulse, "trot must move at all")
    #expect(trot.rise == -2, "the prototype translates -2px; this rises \(trot.rise)")
    #expect(trot.period == 1.0, "the prototype's trot cycle is 1s; this is \(trot.period)")
    #expect(trot.sway == 0, "trot is vertical only")
}

/// §7.2 names two *different* motions — a "quick bob" for `trot` and an
/// "attention pulse" for `call` — so they must not become the same motion now
/// that both are translates. The prototype distinguished them by transform kind
/// (`translateY` against `scale(1.09)`); we cannot use scale (see
/// `theCatsGridSurvivesATranslateButNotAScale`), so the distinction has to live
/// in the numbers instead.
@Test func trotAndCallStillMoveDifferently() throws {
    let trot = try #require(CatMood.trot.pulse)
    let call = try #require(CatMood.call.pulse)
    #expect(trot != call, "trot and call share one motion — the moods differ only by the mouth again")
    #expect(abs(call.rise) > abs(trot.rise),
            "call is the more urgent state and must read as the larger movement: \(call.rise) against trot's \(trot.rise)")
}

/// `dead` wobbles horizontally rather than rotating, and that is deliberate —
/// see `CatMood.pulse`'s own comment for the measurement behind it. What matters
/// here is that it moves *sideways only*, because a vertical `dead` would be a
/// slower `trot`.
@Test func deadWobblesSidewaysRatherThanBobbing() throws {
    let dead = try #require(CatMood.dead.pulse, "§7.2 gives dead a slow wobble")
    #expect(dead.sway != 0 && dead.rise == 0,
            "dead moves rise=\(dead.rise) sway=\(dead.sway) — a vertical wobble is just a slow trot")
    #expect(dead.period == 2.4, "the prototype's wobble is 2.4s; this is \(dead.period)")
}

/// `sleep` drowses downward, matching the prototype's
/// `@keyframes drowse {0%,100%{translateY(0)} 50%{translateY(2px)}}` over 3s.
///
/// **Down, not up** — it is the one mood that sinks, and it is the whole reading
/// of "asleep". A sign error here would make a sleeping cat bob like a trotting
/// one, which no cell assertion elsewhere in this file would catch.
///
/// That this animates at all rests on a measurement, not a preference: Plan 3
/// made it still on a real figure that priced the cell-swapping mechanism, and a
/// transform's marginal cost on an island already animating measured ~0.75pp. See
/// `CatMood.pulse`.
@Test func sleepDrowsesDownwardOnThePrototypesThreeSecondCycle() throws {
    let sleep = try #require(CatMood.sleep.pulse, "sleep drowses — see the pulse comment")
    #expect(sleep.rise == 2, "drowse sinks 2px; this moves \(sleep.rise) — negative would make it bob awake")
    #expect(sleep.period == 3.0, "the prototype's drowse is 3s; this is \(sleep.period)")
}

/// `happy` carries no *repeating* pulse: §7.2 gives it "one spring pop", and
/// `CatCanvas` renders that as a transient overshoot rather than something that
/// runs forever. It is also the only mood allowed to scale, because a 540ms blur
/// ends and a permanent one does not.
@Test func happyIsAOneShotRatherThanARepeatingPulse() {
    #expect(CatMood.happy.pulse == nil, "happy is a one-shot pop, not a repeating pulse")
}

@Test func resolvingIsStableForTheSameInput() {
    let a = ResolvedCat(coat: .siamese, mood: .trot, phase: 0.25)
    let b = ResolvedCat(coat: .siamese, mood: .trot, phase: 0.25)
    #expect(a == b)
}
