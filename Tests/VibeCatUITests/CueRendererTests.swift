import Testing
import Foundation
@testable import VibeCatUI

// MARK: - CueRenderer

private let rate = 44_100.0

@Test func aRenderedCueIsAsLongAsItsLastNotePlusTheReleaseTail() {
    let buffer = CueRenderer.render(.ask, settings: SoundSettings(), sampleRate: rate)
    // `.ask`'s last note is `at: 0.30, 0.36` — 0.66s — plus the prototype's
    // 0.02 stop margin. Derived from the note table rather than a `0.66`
    // literal: `0.30 + 0.36` and `0.66` round to different Doubles
    // (0.6599999999999999 vs 0.68 after +0.02), which truncate to different
    // integers — a literal here would be measuring floating-point rounding,
    // not the renderer.
    let lastEnd = SoundPack.chiptune.notes(for: .ask).map(\.end).max()!
    #expect(buffer.count == Int((lastEnd + CueRenderer.releaseTail) * rate))
}

@Test func silenceIsEmptyRatherThanAZeroFilledBufferOfTheRightLength() {
    // A zero-filled buffer of the right length would pass a length assertion
    // and still cost the audio engine a scheduled play. The distinction is
    // observable and worth pinning.
    #expect(CueRenderer.render(.ask, settings: SoundSettings(pack: .silent),
                               sampleRate: rate).isEmpty)
    #expect(CueRenderer.render(.ask, settings: SoundSettings(enabled: false),
                               sampleRate: rate).isEmpty)
}

/// Renamed from `theBufferIsNotSilentAndPeaksNearTheNoteGainTimesTheVolume`,
/// which claimed a proximity it did not assert: `0.02 < peak < 0.5` is a 25×
/// range around a real peak of `0.072`, and the whole-branch review confirmed it
/// survives forcing every note to the wrong waveform, the wrong gain and the
/// wrong pitch. It is a smoke test — "something audible came out, and it will not
/// blow a speaker" — and now says so.
/// `theRendererUsesEachNotesOwnGainRatherThanOneLevel` below is the test that
/// actually pins the level.
@Test func theBufferIsAudibleAndNowhereNearClipping() {
    let buffer = CueRenderer.render(.ask, settings: SoundSettings(), sampleRate: rate)
    let peak = buffer.map(abs).max() ?? 0
    #expect(peak > 0.02, "rendered nothing audible: peak \(peak)")
    #expect(peak < 0.5, "peak \(peak) is far louder than a .07-gain note should be")
}

@Test func halvingTheVolumeHalvesEverySample() {
    // Two renders differing in exactly one input.
    let loud = CueRenderer.render(.done, settings: SoundSettings(volume: 0.80), sampleRate: rate)
    let soft = CueRenderer.render(.done, settings: SoundSettings(volume: 0.40), sampleRate: rate)
    #expect(loud.count == soft.count)
    let i = loud.indices.max(by: { abs(loud[$0]) < abs(loud[$1]) })!
    #expect(abs(Double(loud[i]) / 2 - Double(soft[i])) < 1e-6,
            "at the loudest sample: \(loud[i]) vs \(soft[i])")
}

/// Renamed and re-commented after the whole-branch review, which showed the first
/// assertion could not fail for the reason its comment gave. The old comment
/// claimed "a renderer that ignored `at` and started every note at zero would
/// leave the tail loud and fail here" — it would not: with every `start = 0` the
/// longest note writes 20,286 frames and everything from 40,131 to the end is
/// *still* untouched zeros, so `allSatisfy` passes. The reviewer ran that mutation
/// and the failure came from line 72's local-peak comparison only. The old name
/// also promised "before the first note", and every note in every cue starts at or
/// after `0`, so there is nothing before the first note to examine.
///
/// What the first assertion does pin: no note writes past its own
/// `at + duration`. An off-by-one in the inner loop's bound is the defect shape it
/// catches, and that is a real one — the loop is `0..<count` with a separate
/// `frame < frameCount` break.
@Test func noNoteWritesPastItsOwnEndAndALaterNoteArrivesOnTime() {
    // `error`'s last note starts at 0.45 and runs 0.46, ending at 0.91, and the
    // buffer is 0.93 long. Everything past 0.91 is release margin the renderer
    // must never write into.
    let buffer = CueRenderer.render(.error, settings: SoundSettings(), sampleRate: rate)
    let lastNoteEnd = Int(0.91 * rate)
    #expect(buffer[lastNoteEnd...].allSatisfy { abs($0) < 1e-4 },
            "a note wrote past its own end, into the release margin")
    // And the note at 0.45 must be audible where the one before it has decayed.
    // A single sample is the wrong measurement here: the signal oscillates, so
    // one sample can land arbitrarily close to a zero crossing regardless of
    // how loud the note actually is — the comparison would be luck, not
    // measurement. Take the local peak over a short window on each side
    // instead (~1ms, derived from the sample rate, comfortably shorter than
    // either note's period so it stays "just before"/"just after" rather than
    // smearing across the whole overlap).
    let window = max(1, Int(0.001 * rate))
    let beforeIndex = Int(0.449 * rate)
    let afterIndex = Int(0.460 * rate)
    let before = buffer[(beforeIndex - window)..<beforeIndex].map(abs).max() ?? 0
    let after = buffer[afterIndex..<(afterIndex + window)].map(abs).max() ?? 0
    #expect(after > before, "the fourth note's attack must be louder than the third's tail: \(before) → \(after)")
}

@Test func theTwinIsQuieterThanThePrincipalRatherThanEqual() {
    // The prototype's twin runs at `gain * .6`. A twin at full gain doubles the
    // amplitude instead of thickening it. Rendering the same cue with the
    // detune stripped is the only way to see the twin's contribution at all.
    let withTwin = CueRenderer.render(.ask, settings: SoundSettings(), sampleRate: rate)
    let peakWith = withTwin.map(abs).max() ?? 0

    // The bound is derived, not picked: a hand-waved `0.046 * 2` upper bound
    // let a twin-at-full-gain mutation through (measured 0.088, comfortably
    // under 0.092). Derive `principal` — one voice's peak — from `.ask`'s own
    // held note (the longest, and the one the buffer's peak comes from) rather
    // than the frequency and gain typed as literals, so this keeps tracking
    // the source if either changes.
    let heldNote = SoundPack.chiptune.notes(for: .ask).max(by: { $0.end < $1.end })!
    let harmonics = Waveform.harmonicCount(frequency: heldNote.frequency, sampleRate: rate)
    let squarePeak = heldNote.waveform.sample(phase: 0.25, harmonics: harmonics)
    let principal = heldNote.gain * squarePeak * SoundSettings().volume

    // In-phase with a twin at factor k, the pair peaks at principal * (1 + k).
    // At k = .6 (the real value) that's 1.6×; at k = 1.0 (a twin at full gain,
    // the mutation this test exists to catch) it's 2.0×. 8 cents at ~1046Hz
    // beats at about 5Hz, so within the held note's 0.36s the two certainly
    // drift into phase — 1.8× sits roughly in the middle, with ~11% margin on
    // each side of both real cases.
    #expect(Double(peakWith) > principal * 1.3, "the twin contributes nothing: peak \(peakWith), principal \(principal)")
    #expect(Double(peakWith) < principal * 1.8, "the twin is at full gain, not 0.6: peak \(peakWith), principal \(principal)")
}

@Test func everyCueRendersWithoutANonFiniteSample() {
    // A NaN reaches the speakers as a click or as silence, and `log(0)` from an
    // unbent note is one guard away. Cheap, and it covers all five at once.
    for cue in Cue.allCases {
        let buffer = CueRenderer.render(cue, settings: SoundSettings(), sampleRate: rate)
        #expect(!buffer.isEmpty, "\(cue) rendered nothing")
        #expect(buffer.allSatisfy { $0.isFinite }, "\(cue) produced a non-finite sample")
    }
}

@Test func aDifferentSampleRateChangesTheCountButNotTheDuration() {
    let a = CueRenderer.render(.error, settings: SoundSettings(), sampleRate: 44_100)
    let b = CueRenderer.render(.error, settings: SoundSettings(), sampleRate: 48_000)
    #expect(b.count > a.count)
    let durationA = Double(a.count) / 44_100.0
    let durationB = Double(b.count) / 48_000.0
    #expect(abs(durationA - durationB) < 1e-6,
            "both must last 0.93s")
}

// MARK: - What the assembly actually consults
//
// These six exist because of a specific, reproduced failure. The whole-branch
// review mutated `CueRenderer.render` three ways — every note forced to
// `Waveform.square`, every note forced to `gain: 0.07`, every note rendered at a
// fixed 440Hz instead of through `note.phase` — and **all eight tests above
// stayed green**. Tasks 1–4 each pinned their own piece; nothing pinned that the
// assembly reads the note's waveform, its gain or its frequency at all.
//
// The shape below is the one this repo's standards name: two renders differing in
// exactly one input. `CueRenderer.render(notes:volume:sampleRate:)` exists so the
// altered side can be built, and each mutation is caught precisely because it is
// the thing that makes the two renders identical.

/// One note with every property spelled out, so a test can change exactly one.
/// 440Hz over 0.20s at 44.1k is 88 cycles at 100 samples each — dense enough that
/// the rendered peak reaches the shape's own peak, which is what lets the level
/// assertions below be derived rather than guessed.
private func probe(frequency: Double = 440, gain: Double = 0.07,
                   waveform: Waveform = .square, bend: Double = 0) -> Note {
    Note(frequency, at: 0, 0.20, waveform: waveform, gain: gain, bend: bend)
}

private func forcedToSquare(_ n: Note) -> Note {
    Note(n.frequency, at: n.at, n.duration, waveform: .square, gain: n.gain,
         bend: n.bend, detuneCents: n.detuneCents)
}

private func largestDifference(_ a: [Float], _ b: [Float]) -> Double {
    guard a.count == b.count else { return .infinity }
    return zip(a, b).map { Double(abs($0 - $1)) }.max() ?? 0
}

private func rootMeanSquare(_ b: [Float]) -> Double {
    guard !b.isEmpty else { return 0 }
    return (b.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(b.count)).squareRoot()
}

/// Sign changes, ignoring exact zeros. A band-limited square crosses zero exactly
/// twice per cycle: the Gibbs ripple oscillates about ±1, not about 0, and the
/// odd-harmonic partial sum is strictly positive across the whole positive
/// half-cycle. So the count over a window is `2·f·Δt` — a spectral property only
/// the right frequency can produce.
private func zeroCrossings(_ b: ArraySlice<Float>) -> Int {
    var crossings = 0
    var lastSign = 0
    for sample in b {
        let sign = sample > 0 ? 1 : (sample < 0 ? -1 : 0)
        if sign != 0 {
            if lastSign != 0 && sign != lastSign { crossings += 1 }
            lastSign = sign
        }
    }
    return crossings
}

@Test func theRendererUsesEachNotesOwnWaveformRatherThanOneShape() {
    let settings = SoundSettings()
    // The control comes first, and it is doing real work: `.ask` is square
    // already, so squaring its notes must be a no-op. That is what proves the two
    // render entry points agree and that `forcedToSquare` alters nothing else.
    let ask = CueRenderer.render(.ask, settings: settings, sampleRate: rate)
    let askSquared = CueRenderer.render(notes: SoundPack.chiptune.notes(for: .ask).map(forcedToSquare),
                                       volume: settings.volume, sampleRate: rate)
    #expect(ask == askSquared, "squaring an already-square cue must change nothing")

    // `.error` is the only sawtooth cue and `.meow` the only triangle one, so for
    // each of them "force every note to square" is a one-property change.
    for cue in [Cue.error, Cue.meow] {
        let real = CueRenderer.render(cue, settings: settings, sampleRate: rate)
        let squared = CueRenderer.render(notes: SoundPack.chiptune.notes(for: cue).map(forcedToSquare),
                                         volume: settings.volume, sampleRate: rate)
        let peak = Double(real.map(abs).max() ?? 0)
        #expect(largestDifference(real, squared) > 0.1 * peak,
                "\(cue) renders identically to a square: the note's waveform is being ignored")
    }
}

@Test func theRendererUsesEachNotesOwnGainRatherThanOneLevel() {
    // The shape's own peak, computed from `Waveform` rather than from a Gibbs
    // figure typed in by hand, so this keeps tracking the series if it changes.
    let harmonics = Waveform.harmonicCount(frequency: 440, sampleRate: rate)
    let shapePeak = (0..<2000).map { abs(Waveform.square.sample(phase: Double($0) / 2000,
                                                                harmonics: harmonics)) }.max()!

    let quiet = CueRenderer.render(notes: [probe(gain: 0.03)], volume: 1, sampleRate: rate)
    let loud = CueRenderer.render(notes: [probe(gain: 0.12)], volume: 1, sampleRate: rate)
    let quietPeak = Double(quiet.map(abs).max() ?? 0)
    let loudPeak = Double(loud.map(abs).max() ?? 0)

    // Proportionality. The envelope's peak is `gain` to within a part in a
    // thousand (it is reached one sample after the 6ms attack ends, and the
    // exponential tail has 0.194s to run), so 4× the gain is 4× the peak. Any
    // renderer that substitutes a constant makes this ratio 1.
    #expect(abs(loudPeak / quietPeak - 4) < 0.2,
            "gain is not proportional: \(quietPeak) at .03 against \(loudPeak) at .12")
    // And an exact ceiling: the envelope never exceeds `gain` and the shape never
    // exceeds `shapePeak`, so a peak above their product is arithmetically
    // impossible — which is what catches a constant substituted *upward*.
    #expect(quietPeak <= 0.03 * shapePeak,
            "peak \(quietPeak) exceeds what a .03 gain can produce (\(0.03 * shapePeak))")
    // The other side: 0.20s at 100 samples per cycle does reach the shape's peak.
    #expect(quietPeak > 0.03 * shapePeak * 0.85,
            "peak \(quietPeak) is far below a .03 gain's \(0.03 * shapePeak)")
}

@Test func aNoteIsRenderedAtItsOwnFrequency() {
    // Absolute, not comparative: the count is derived from the note's frequency
    // and the window's length. The window starts after the attack and ends before
    // the envelope has decayed into the noise floor.
    let from = Int(0.02 * rate), to = Int(0.18 * rate)
    let span = Double(to - from) / rate
    for frequency in [440.0, 880.0] {
        let buffer = CueRenderer.render(notes: [probe(frequency: frequency)],
                                        volume: 1, sampleRate: rate)
        let counted = zeroCrossings(buffer[from..<to])
        let expected = 2 * frequency * span
        #expect(abs(Double(counted) - expected) <= 4,
                "a \(frequency)Hz note crossed zero \(counted) times in \(span)s, not \(expected)")
    }
}

/// **Both pairs are chosen so the two renders share a harmonic count**, and that
/// is the whole reason they are probe notes rather than a real cue transposed.
///
/// The first draft of this test compared `.done` against `.done` an octave up, and
/// the 440Hz mutation *did not break it* — because `harmonicCount` is a function of
/// frequency, so transposing changes how many partials each note gets even when the
/// phase is frozen, and the two buffers then differ for a reason that has nothing to
/// do with pitch. It passed for the wrong reason, which is the exact defect class
/// this whole pass exists to close. Asserting the shared count below is what makes
/// the measured difference attributable to phase alone.
///
/// The second thing that had to be got right is *where* in the note to look. A
/// frequency or bend difference accumulates phase over time, but the envelope decays
/// from `gain` to `0.0001` across the same time — so a difference that is large in
/// phase can be vanishingly small in samples. A `1.001` bend measured `0.0087`
/// against a `0.0375` bar for exactly that reason. The pairs below are spaced far
/// enough apart to decorrelate while the envelope is still loud: measured `1.97×`
/// and `1.54×` the peak, against a bar of `0.5×`.
@Test func theRendererUsesEachNotesOwnPitchAndBend() {
    // 433 and 441 both admit `Int(22050/f) == 50` partials, so only the phase
    // differs. 8Hz over 0.20s is 1.6 cycles of drift, and a square's value either
    // side of a transition differs by twice its amplitude.
    #expect(Waveform.harmonicCount(frequency: 433, sampleRate: rate)
            == Waveform.harmonicCount(frequency: 441, sampleRate: rate),
            "the pair must share a band limit or this measures the limit, not the pitch")
    let at433 = CueRenderer.render(notes: [probe(frequency: 433)], volume: 1, sampleRate: rate)
    let at441 = CueRenderer.render(notes: [probe(frequency: 441)], volume: 1, sampleRate: rate)
    let peak = Double(at441.map(abs).max() ?? 0)
    #expect(largestDifference(at433, at441) > 0.5 * peak,
            "433Hz renders the same as 441Hz: the note's frequency is being ignored")

    // Bend, isolated the same way. 5000Hz admits 4 partials and so does 5500, so a
    // `1.10` rising bend leaves the band limit alone and changes only the phase
    // integral — `f₀·D·(b^(t/D) − 1)/ln b` against `f₀·t`.
    let flatNote = probe(frequency: 5000), bentNote = probe(frequency: 5000, bend: 1.10)
    #expect(Waveform.harmonicCount(frequency: bentNote.peakFrequency, sampleRate: rate)
            == Waveform.harmonicCount(frequency: flatNote.frequency, sampleRate: rate),
            "the bend must not move the band limit or this measures the limit, not the bend")
    let flat = CueRenderer.render(notes: [flatNote], volume: 1, sampleRate: rate)
    let bent = CueRenderer.render(notes: [bentNote], volume: 1, sampleRate: rate)
    #expect(largestDifference(flat, bent) > 0.5 * Double(flat.map(abs).max() ?? 0),
            "a bent note renders the same as an unbent one: the bend is being ignored")
}

@Test func aRisingBendsBandLimitIsTakenFromWhereTheNoteEndsNotWhereItStarts() {
    // The whole-branch review's minor 8. Chosen so the difference is loud rather
    // than the −56dB it is for `meow`: 8000Hz admits `Int(22050/8000) == 2`
    // harmonics, and bent by 1.5 the note ends at 12000Hz, which admits 1. So the
    // second partial must be absent from the bent render.
    //
    // A sawtooth's RMS is `(2/π)·√(Σ 1/n²)`: `√0.5` with one partial, `√0.625`
    // with two, a ratio of 0.894. Both notes carry the same envelope, and at
    // 8000Hz the waveform oscillates far faster than the envelope, so the ratio
    // of the buffers' RMS is the ratio of the waveforms'.
    let bent = CueRenderer.render(notes: [probe(frequency: 8000, gain: 1, waveform: .sawtooth, bend: 1.5)],
                                  volume: 1, sampleRate: rate)
    let unbent = CueRenderer.render(notes: [probe(frequency: 8000, gain: 1, waveform: .sawtooth)],
                                    volume: 1, sampleRate: rate)
    let ratio = rootMeanSquare(bent) / rootMeanSquare(unbent)
    #expect(ratio < 0.95,
            "the bent note keeps its second partial past Nyquist: RMS ratio \(ratio), expected ≈0.894")
}

// MARK: - The volume boundary

@Test func aVolumeIsClampedWhereverItEntersFrom() {
    // Plan 6.4 reads this from `UserDefaults`, where anything running as this user
    // can write it, and `CueRenderer` multiplies every sample by it. Both entry
    // points are checked, because a clamp in the initialiser alone leaves
    // `settings.volume = 7` open and vice versa.
    #expect(SoundSettings(volume: 7).volume == 1)
    #expect(SoundSettings(volume: -1).volume == 0)
    var settings = SoundSettings()
    settings.volume = 7
    #expect(settings.volume == 1)
    settings.volume = -1
    #expect(settings.volume == 0)
    // In range is left exactly alone: a clamp that rounded or quantised would be a
    // different bug.
    settings.volume = 0.37
    #expect(settings.volume == 0.37)
}

@Test func aNonFiniteVolumeFallsBackToTheDefaultRatherThanToSilence() {
    // `min`/`max` propagate NaN, so a naive clamp lets it through, and a NaN volume
    // renders a cue of NaN samples — which reaches the speakers as a click or as
    // nothing, and passes any assertion that only counts samples.
    #expect(SoundSettings(volume: .nan).volume == SoundSettings.defaultVolume)
    #expect(SoundSettings(volume: .infinity).volume == SoundSettings.defaultVolume)
    let buffer = CueRenderer.render(.ask, settings: SoundSettings(volume: .nan), sampleRate: rate)
    #expect(buffer.allSatisfy { $0.isFinite }, "a NaN volume reached the samples")
}
