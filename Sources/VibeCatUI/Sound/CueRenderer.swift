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
        let notes = settings.pack.notes(for: cue)
        guard let last = notes.map(\.end).max() else { return [] }

        let frameCount = Int((last + releaseTail) * sampleRate)
        var buffer = [Float](repeating: 0, count: frameCount)

        for note in notes {
            let start = Int(note.at * sampleRate)
            let count = Int(note.duration * sampleRate)
            let harmonics = Waveform.harmonicCount(frequency: note.frequency,
                                                   sampleRate: sampleRate)
            // A twin's own frequency is higher, so it fits fewer harmonics.
            // Reusing the principal's count would push its top partial past
            // Nyquist — the exact aliasing `Waveform` exists to avoid.
            let twinHarmonics = note.detuneCents == 0 ? harmonics
                : Waveform.harmonicCount(frequency: note.frequency * pow(2, note.detuneCents / 1200),
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
                buffer[frame] += Float(value * settings.volume)
            }
        }
        return buffer
    }
}
