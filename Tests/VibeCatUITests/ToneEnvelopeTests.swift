import Testing
import Foundation
@testable import VibeCatUI

// MARK: - ToneEnvelope

@Test func theAttackReachesFullGainAtSixMillisecondsAndNotBefore() {
    let g = 0.07
    #expect(abs(ToneEnvelope.amplitude(at: 0.006, duration: 0.11, gain: g) - g) < 1e-9)
    // Halfway through the attack an exponential ramp is the geometric mean,
    // which is far below the arithmetic half a linear ramp would give.
    let mid = ToneEnvelope.amplitude(at: 0.003, duration: 0.11, gain: g)
    let geometric = (ToneEnvelope.floor * g).squareRoot()
    #expect(abs(mid - geometric) < 1e-9, "expected \(geometric), got \(mid) — is this ramp linear?")
    #expect(mid < g / 2, "an exponential attack must sit below the linear midpoint")
}

@Test func theEnvelopeStartsAndEndsOnTheFloorRatherThanZero() {
    // Not cosmetic: an exponential ramp cannot reach zero, and ending at zero
    // is an audible click. If someone "simplifies" the floor away, this fails.
    #expect(ToneEnvelope.amplitude(at: 0, duration: 0.11, gain: 0.07) == ToneEnvelope.floor)
    let end = ToneEnvelope.amplitude(at: 0.11, duration: 0.11, gain: 0.07)
    #expect(abs(end - ToneEnvelope.floor) < 1e-12)
    #expect(end > 0, "a floor of zero would make the whole ramp collapse")
}

@Test func theDecayIsMonotonicAcrossTheWholeTail() {
    let samples = stride(from: 0.006, through: 0.46, by: 0.01).map {
        ToneEnvelope.amplitude(at: $0, duration: 0.46, gain: 0.06)
    }
    #expect(samples == samples.sorted(by: >), "the tail must fall throughout")
}

@Test func aLongerNoteDecaysMoreSlowlyAtTheSameInstant() {
    // The decay is stretched to the note's own duration, so the held 0.46s note
    // must still be loud where the 0.09s note has already finished. Two renders
    // differing in exactly one input.
    let short = ToneEnvelope.amplitude(at: 0.08, duration: 0.09, gain: 0.07)
    let long  = ToneEnvelope.amplitude(at: 0.08, duration: 0.46, gain: 0.07)
    #expect(long > short * 10, "got short=\(short) long=\(long)")
}

@Test func anEnvelopeShorterThanItsOwnAttackStillFallsToTheFloor() {
    // No cue in the chiptune pack is this short, but a future pack could be,
    // and a `duration - attack` of zero or less must not divide by zero.
    let a = ToneEnvelope.amplitude(at: 0.004, duration: 0.004, gain: 0.07)
    #expect(a.isFinite, "got \(a)")
    #expect(abs(a - ToneEnvelope.floor) < 1e-12, "a note that ends inside its attack ends at the floor")
}
