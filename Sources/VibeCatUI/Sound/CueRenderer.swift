import Foundation

/// A cue, as samples. Pure, so the thing that decides what VibeCat sounds like
/// is testable without an audio device — which matters more here than usual: an
/// `AVAudioSourceNode` render callback, like a `Canvas` renderer, never runs
/// during a property read, so a test that only touched the player would prove
/// nothing at all.
public struct CueRenderer: Sendable {
    /// The prototype stops each oscillator at `t0 + dur + .02`, so a rendered
    /// cue carries the same 20ms of release past its last note.
    public static let releaseTail: TimeInterval = 0.02

    public static func render(_ cue: Cue, settings: SoundSettings,
                             sampleRate: Double) -> [Float] {
        guard settings.enabled else { return [] }
        return render(notes: settings.pack.notes(for: cue),
                      volume: settings.volume, sampleRate: sampleRate)
    }

    /// The assembly, over an arbitrary note list.
    ///
    /// **This seam exists because of a defect, and the defect is worth naming.**
    /// The whole-branch review mutated this function three ways — every note
    /// forced to `Waveform.square`, every note forced to `gain: 0.07`, every note
    /// rendered at a fixed 440Hz instead of through `note.phase` — and all eight
    /// of the renderer's tests stayed green. Tasks 1–4 each pinned their own piece
    /// (`Waveform`, `ToneEnvelope`, `Note.phase`, `SoundPack`); nothing pinned
    /// that the assembly *consults* any of them. Aggregate properties — length,
    /// finiteness, a peak bound, sample-rate independence — all survive a
    /// renderer that ignores the pack almost entirely.
    ///
    /// Rendering an arbitrary list is what lets a test do the thing this repo's
    /// standards actually ask for: two renders differing in exactly one input.
    /// A cue's real notes against the same notes with one property altered is a
    /// comparison a mutation cannot survive, because the mutation is precisely
    /// what makes the two renders identical.
    static func render(notes: [Note], volume: Double, sampleRate: Double) -> [Float] {
        guard let last = notes.map(\.end).max() else { return [] }

        let frameCount = Int((last + releaseTail) * sampleRate)
        var buffer = [Float](repeating: 0, count: frameCount)

        for note in notes {
            let start = Int(note.at * sampleRate)
            let count = Int(note.duration * sampleRate)
            // `peakFrequency`, not `frequency`: a bent note's instantaneous
            // frequency changes across it, and a rising bend takes the top
            // partial of a limit computed from the *starting* pitch above
            // Nyquist. `meow`'s first syllable is the real case — 600Hz bent by
            // 1.75, so a limit of 36 partials keeps odd partials up to k=35,
            // which by the end of the note sit at 24k…36kHz and fold back to
            // 20k…7kHz. Web Audio re-selects its band-limited table per
            // instantaneous frequency, so the prototype does not do this.
            // Inaudible at −56dB, but `Waveform`'s doc claims band-limiting is
            // exact and that claim should be true.
            let harmonics = Waveform.harmonicCount(frequency: note.peakFrequency,
                                                   sampleRate: sampleRate)
            // A twin's own frequency is higher, so it fits fewer harmonics.
            // Reusing the principal's count would push its top partial past
            // Nyquist — the exact aliasing `Waveform` exists to avoid.
            let twinHarmonics = note.detuneCents == 0 ? harmonics
                : Waveform.harmonicCount(frequency: note.peakFrequency * pow(2, note.detuneCents / 1200),
                                         sampleRate: sampleRate)

            for i in 0..<count {
                let frame = start + i
                guard frame < frameCount else { break }
                let t = Double(i) / sampleRate
                let amp = ToneEnvelope.amplitude(at: t, duration: note.duration, gain: note.gain)
                var value = note.waveform.sample(phase: note.phase(at: t, detuned: false),
                                                 harmonics: harmonics) * amp
                if note.detuneCents != 0 {
                    // The prototype's second pulse channel: same shape, detuned,
                    // at 60% of the principal's gain — thickening the tone
                    // rather than doubling its amplitude.
                    let twinAmp = ToneEnvelope.amplitude(at: t, duration: note.duration,
                                                         gain: note.gain * 0.6)
                    value += note.waveform.sample(phase: note.phase(at: t, detuned: true),
                                                  harmonics: twinHarmonics) * twinAmp
                }
                buffer[frame] += Float(value * volume)
            }
        }
        return buffer
    }
}
