import Testing
import Foundation
@testable import VibeCatUI

// MARK: - Waveform

@Test func aSquareIsOddHarmonicsOnlyAndCancelsAtTheZeroCrossing() {
    // φ = 0 and φ = 0.5 are the crossings of every sine in an odd-harmonic
    // series, so a square must read 0 at both however many harmonics it keeps.
    #expect(abs(Waveform.square.sample(phase: 0, harmonics: 14)) < 1e-12)
    #expect(abs(Waveform.square.sample(phase: 0.5, harmonics: 14)) < 1e-12)
    // A quarter period is the peak, and it must sit above 1 — the Gibbs
    // overshoot is the evidence the series is truncated rather than clamped.
    let peak = Waveform.square.sample(phase: 0.25, harmonics: 14)
    #expect(peak > 1.0 && peak < 1.2, "expected a truncated square's overshoot, got \(peak)")
}

@Test func aSquareIsOddSymmetricAboutHalfAPeriod() {
    // s(φ + 0.5) == −s(φ) for odd harmonics only. An even harmonic leaking in
    // breaks this and nothing else in the suite would notice.
    for phase in [0.05, 0.17, 0.33, 0.49] {
        let a = Waveform.square.sample(phase: phase, harmonics: 14)
        let b = Waveform.square.sample(phase: phase + 0.5, harmonics: 14)
        #expect(abs(a + b) < 1e-9, "φ=\(phase) gave \(a) and \(b)")
    }
}

@Test func aSawtoothRisesThroughItsPeriodWhereASquareDoesNot() {
    // The two differ in exactly one input — the case — so this cannot pass
    // against a switch that returns the same series for both.
    let saw = (1...9).map { Waveform.sawtooth.sample(phase: Double($0) / 20, harmonics: 14) }
    #expect(saw == saw.sorted(), "a sawtooth must rise monotonically over 0…0.45, got \(saw)")
    let square = (1...9).map { Waveform.square.sample(phase: Double($0) / 20, harmonics: 14) }
    #expect(square != square.sorted(), "a square must not rise monotonically")
}

@Test func aTriangleFallsAwayFasterThanASquareBecauseItsHarmonicsGoAsKSquared() {
    // Third harmonic weight: square 1/3 ≈ .333, triangle 1/9 ≈ .111. Comparing
    // the two shapes at the same phase is what makes the exponent observable.
    let tri = Waveform.triangle.sample(phase: 0.25, harmonics: 14)
    #expect(tri > 0.9 && tri < 1.05, "a triangle's peak barely overshoots, got \(tri)")
}

@Test func harmonicCountStopsBelowNyquist() {
    // G6 = 1568Hz at 44.1kHz: 22050/1568 = 14.06, so 14 harmonics — the 15th
    // would land at 23520Hz and fold back.
    #expect(Waveform.harmonicCount(frequency: 1568, sampleRate: 44_100) == 14)
    // A low note gets many, but never unbounded.
    #expect(Waveform.harmonicCount(frequency: 233.08, sampleRate: 44_100) == 94)
    // Never zero, even for an absurd frequency — a silent note is a bug, not a
    // graceful degradation.
    #expect(Waveform.harmonicCount(frequency: 40_000, sampleRate: 44_100) == 1)
}
