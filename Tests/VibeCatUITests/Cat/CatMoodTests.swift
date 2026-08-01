import Testing
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
@Test func trotAndCallMoveToDifferentRhythms() {
    let phases = stride(from: 0.0, to: 1.0, by: 0.01).map { $0 }
    func steps(_ mood: CatMood) -> [Int] {
        phases.map { ResolvedCat(coat: .tabby, mood: mood, phase: $0).verticalOffset }
    }
    let trot = steps(.trot), call = steps(.call)
    #expect(trot != call, "trot and call step identically — they share one motion")
    #expect(trot.count { $0 != 0 } != call.count { $0 != 0 },
            "trot and call spend the same share of the cycle raised — one is only a phase shift of the other, not a different motion")
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

/// Pixel art steps. A fractional offset would blur the grid.
@Test func theVerticalOffsetIsAlwaysAWholeNumberOfCells() {
    for mood in CatMood.allCases {
        for i in 0...20 {
            let phase = Double(i) / 20.0
            let cat = ResolvedCat(coat: .tabby, mood: mood, phase: phase)
            #expect(abs(cat.verticalOffset) <= 1, "\(mood) bobs more than one cell")
        }
    }
}

@Test func aStillMoodDoesNotMoveAcrossThePhase() {
    let a = ResolvedCat(coat: .tabby, mood: .dead, phase: 0.0).verticalOffset
    let b = ResolvedCat(coat: .tabby, mood: .dead, phase: 0.5).verticalOffset
    #expect(a == b || CatMood.dead.motion.isContinuous)
}

@Test func resolvingIsStableForTheSameInput() {
    let a = ResolvedCat(coat: .siamese, mood: .trot, phase: 0.25)
    let b = ResolvedCat(coat: .siamese, mood: .trot, phase: 0.25)
    #expect(a == b)
}
