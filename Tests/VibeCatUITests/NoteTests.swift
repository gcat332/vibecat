import Testing
import Foundation
@testable import VibeCatUI

// MARK: - Note

@Test func anUnbentNotesPhaseAdvancesAtItsOwnFrequency() {
    let n = Note(Pitch.g5, at: 0, 0.11)
    #expect(n.phase(at: 0, detuned: false) == 0)
    // One second at 783.99Hz is 783.99 cycles. Nothing else can produce this.
    #expect(abs(n.phase(at: 1, detuned: false) - 783.99) < 1e-9)
}

@Test func aBendOfZeroIsTreatedAsNoBendRatherThanAsSilence() {
    // The prototype spells "no bend" as `bend: 0`, and log(0) is -inf. A
    // straight application of the closed form would make every unbent note in
    // the pack NaN, which would render as silence and pass any test that only
    // counted samples.
    let n = Note(Pitch.c6, at: 0, 0.11, bend: 0)
    let φ = n.phase(at: 0.05, detuned: false)
    #expect(φ.isFinite, "got \(φ)")
    #expect(abs(φ - Pitch.c6 * 0.05) < 1e-9)
}

@Test func aRisingBendEndsAtItsTargetFrequency() {
    // meow's first syllable: 600Hz bent up by 1.75 over 0.20s. Differentiating
    // the phase numerically is what proves the *frequency* ramped, not just
    // that some number grew.
    let n = Note(600, at: 0, 0.20, waveform: .triangle, gain: 0.09, bend: 1.75)
    let dt = 1e-6
    let fEnd = (n.phase(at: 0.20, detuned: false) - n.phase(at: 0.20 - dt, detuned: false)) / dt
    #expect(abs(fEnd - 600 * 1.75) < 1.0, "expected 1050Hz at the end, got \(fEnd)")
    let fStart = n.phase(at: dt, detuned: false) / dt
    #expect(abs(fStart - 600) < 1.0, "expected 600Hz at the start, got \(fStart)")
}

@Test func aFallingBendEndsBelowWhereItStarted() {
    // error's last note sags: Bb3 bent by 0.80. Same shape as the rising case
    // with one input changed, so a sign error cannot survive both.
    let n = Note(Pitch.bFlat3, at: 0, 0.46, waveform: .sawtooth, gain: 0.06, bend: 0.80)
    let dt = 1e-6
    let fEnd = (n.phase(at: 0.46, detuned: false) - n.phase(at: 0.46 - dt, detuned: false)) / dt
    #expect(abs(fEnd - Pitch.bFlat3 * 0.80) < 1.0, "expected \(Pitch.bFlat3 * 0.80), got \(fEnd)")
}

@Test func detuningRaisesTheTwinByItsCents() {
    // Eight cents is 2^(8/1200) ≈ 1.00463. A twin that is not detuned produces
    // no beating and the thickened tone §12 asks for disappears.
    let n = Note(Pitch.g5, at: 0, 0.11, detuneCents: 8)
    let plain = n.phase(at: 1, detuned: false)
    let twin  = n.phase(at: 1, detuned: true)
    #expect(abs(twin / plain - pow(2, 8.0 / 1200)) < 1e-9, "got ratio \(twin / plain)")
}

@Test func theNoteTableIsEqualTemperamentAboveA440() {
    // A5 is the reference; every other entry must be a semitone multiple of it.
    // Copying a frequency wrongly by a digit is the likeliest transcription
    // error in this whole plan, and it is inaudible against a chord you have
    // never heard.
    #expect(Pitch.a5 == 880)
    let semitone = pow(2.0, 1.0 / 12)
    #expect(abs(Pitch.c6 - Pitch.a5 * pow(semitone, 3)) < 0.05)
    #expect(abs(Pitch.e6 - Pitch.a5 * pow(semitone, 7)) < 0.05)
    #expect(abs(Pitch.g6 - Pitch.a5 * pow(semitone, 10)) < 0.05)
    #expect(abs(Pitch.c5 - Pitch.a5 * pow(semitone, -9)) < 0.05)
    #expect(abs(Pitch.bFlat3 - Pitch.a5 * pow(semitone, -23)) < 0.05)
}
