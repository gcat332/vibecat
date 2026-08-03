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

@Test func theBufferIsNotSilentAndPeaksNearTheNoteGainTimesTheVolume() {
    let buffer = CueRenderer.render(.ask, settings: SoundSettings(), sampleRate: rate)
    let peak = buffer.map(abs).max() ?? 0
    // gain .07, doubled by a twin at .6 of it, Gibbs overshoot, all × volume
    // .60 — comfortably audible and nowhere near clipping.
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

@Test func nothingSoundsBeforeTheFirstNoteOrAfterTheLast() {
    // `error`'s last note starts at 0.45 and runs 0.46, ending at 0.91, and the
    // buffer is 0.93 long. Everything past 0.91 must be the release margin
    // only — so a renderer that ignored `at` and started every note at zero
    // would leave the tail loud and fail here.
    let buffer = CueRenderer.render(.error, settings: SoundSettings(), sampleRate: rate)
    let lastNoteEnd = Int(0.91 * rate)
    #expect(buffer[lastNoteEnd...].allSatisfy { abs($0) < 1e-4 },
            "the release margin must be quiet")
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
    // A single unbent 0.07-gain square with volume .60 peaks near .046; the twin
    // adds up to 60% of that, so the pair must land between the two.
    #expect(peakWith > 0.046, "the twin contributes nothing: peak \(peakWith)")
    #expect(peakWith < 0.046 * 2, "the twin is at full gain, not 0.6: peak \(peakWith)")
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
