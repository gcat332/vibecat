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
