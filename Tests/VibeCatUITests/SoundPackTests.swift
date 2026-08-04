import Testing
import Foundation
import VibeCatCore
@testable import VibeCatUI

// MARK: - SoundPack

@Test func everyCueLastsWhatTheSpecTableSays() {
    // §12's durations are not independent data — they are `at + duration` of
    // each cue's last note. Asserting them turns any transcription slip in the
    // offsets into a red test, which is the only thing that catches a digit.
    let expected: [Cue: TimeInterval] = [
        .ask: 0.66, .askMulti: 0.74, .done: 0.81, .error: 0.91, .meow: 0.63,
    ]
    for (cue, total) in expected {
        let notes = SoundPack.chiptune.notes(for: cue)
        let end = notes.map(\.end).max() ?? 0
        #expect(abs(end - total) < 1e-9, "\(cue) ran \(end)s, §12 says \(total)s")
    }
}

@Test func theTwoAskCuesShareAnOpeningAndDivergeAtTheThirdNote() {
    // §12: "the figure doubled". Both open G5→C6; ask then climbs to E6 while
    // askMulti returns to G5. Asserting the divergence point is what makes this
    // fail if someone pastes one cue's array into the other.
    let ask = SoundPack.chiptune.notes(for: .ask)
    let multi = SoundPack.chiptune.notes(for: .askMulti)
    #expect(ask[0].frequency == Pitch.g5 && multi[0].frequency == Pitch.g5)
    #expect(ask[1].frequency == Pitch.c6 && multi[1].frequency == Pitch.c6)
    #expect(ask[2].frequency == Pitch.e6, "ask climbs")
    #expect(multi[2].frequency == Pitch.g5, "askMulti restates")
    #expect(ask.last?.frequency == Pitch.c6, "ask is held on C6")
    #expect(multi.last?.frequency == Pitch.e6, "askMulti resolves on E6")
}

@Test func allThreeAlertCuesCarryTheDetunedTwinIncludingTheTwoTheSpecTableOmits() {
    // The written decision in this plan: §12's Voice column says bare "pulse"
    // for askMulti and done, but the prototype passes duty:8 and duty:6. If
    // someone later "fixes" the code back to the table, this fails.
    #expect(SoundPack.chiptune.notes(for: .ask).allSatisfy { $0.detuneCents == 8 })
    #expect(SoundPack.chiptune.notes(for: .askMulti).allSatisfy { $0.detuneCents == 8 })
    #expect(SoundPack.chiptune.notes(for: .done).allSatisfy { $0.detuneCents == 6 })
    // And the two that genuinely have no twin still have none.
    #expect(SoundPack.chiptune.notes(for: .error).allSatisfy { $0.detuneCents == 0 })
    #expect(SoundPack.chiptune.notes(for: .meow).allSatisfy { $0.detuneCents == 0 })
}

@Test func doneClimbsTwoOctavesAndHoldsTheTopNoteQuieter() {
    let notes = SoundPack.chiptune.notes(for: .done)
    #expect(notes.count == 6)
    #expect(notes.prefix(5).map(\.frequency) == [Pitch.c5, Pitch.e5, Pitch.g5, Pitch.c6, Pitch.e6])
    // The arpeggio is evenly spaced at 0.07 — a hand-typed list drifts.
    for (i, n) in notes.prefix(5).enumerated() {
        #expect(abs(n.at - Double(i) * 0.07) < 1e-9, "note \(i) sits at \(n.at)")
    }
    let held = notes[5]
    #expect(held.frequency == Pitch.g6)
    #expect(held.duration == 0.46, "the top note is held")
    #expect(held.gain == 0.06, "and it is held quieter than the run below it")
    #expect(notes[0].gain == 0.07)
}

@Test func errorFallsAndItsLastNoteSagsOnASaw() {
    let notes = SoundPack.chiptune.notes(for: .error)
    let pitches = notes.map(\.frequency)
    #expect(pitches == pitches.sorted(by: >), "every note must be lower than the last: \(pitches)")
    #expect(notes.allSatisfy { $0.waveform == .sawtooth })
    #expect(notes.last?.bend == 0.80, "§12's 'sagging at the end' is a downward bend")
    #expect(notes.dropLast().allSatisfy { $0.bend == 0 }, "only the last note sags")
}

@Test func meowIsUntunedOnPurpose() {
    let notes = SoundPack.chiptune.notes(for: .meow)
    #expect(notes.map(\.frequency) == [600, 1040])
    #expect(notes.allSatisfy { $0.waveform == .triangle })
    #expect(notes[0].bend == 1.75, "the first syllable rises")
    #expect(notes[1].bend == 0.52, "the second falls")
    // Neither is a named pitch, and that is deliberate — a cat is not in tune.
    #expect(!Set([Pitch.d5, Pitch.e5, Pitch.f5, Pitch.g5, Pitch.a5, Pitch.b5, Pitch.c6]).contains(600))
}

@Test func theSilentPackHasNoNotesForAnyCue() {
    for cue in Cue.allCases {
        #expect(SoundPack.silent.notes(for: cue).isEmpty, "\(cue) must be silent")
    }
}
