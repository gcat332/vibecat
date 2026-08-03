import Foundation

/// §12's five cues. `ask`, `askMulti`, `done` and `error` fire from a state
/// change; `meow` never does — it exists for the Settings sheet's per-cue
/// alternatives and for the prototype's own meow button.
public enum Cue: String, Sendable, CaseIterable {
    case ask, askMulti, done, error, meow
}

/// A pack is "a handful of oscillator settings rather than a folder of files"
/// (§12), which is why this is an enum returning arrays rather than a resource
/// bundle.
///
/// **Only `chiptune` and `silent` exist, deliberately.** `settings.html` offers
/// Chiptune / Soft / System / Silent and per-cue alternatives Blip / Meow /
/// None, but nothing in this repo defines what Soft, System or Blip sound like —
/// no frequencies, no waveforms, nothing. Inventing them would be inventing
/// design rather than implementing it. Adding a case later is additive.
public enum SoundPack: String, Sendable, CaseIterable {
    case chiptune, silent

    /// Transcribed from `island-motion.html:894-912`. Every offset, duration,
    /// gain and detune below is from that block. §12's durations are the
    /// arithmetic consequence of the last note's `at + duration` and are
    /// asserted in `everyCueLastsWhatTheSpecTableSays`.
    public func notes(for cue: Cue) -> [Note] {
        switch self {
        case .silent: return []
        case .chiptune: break
        }
        switch cue {
        // A rising call that lands on a held note — a phrase, not a beep.
        case .ask:
            return [Note(Pitch.g5, at: 0,    0.11, detuneCents: 8),
                    Note(Pitch.c6, at: 0.10, 0.11, detuneCents: 8),
                    Note(Pitch.e6, at: 0.20, 0.11, detuneCents: 8),
                    Note(Pitch.c6, at: 0.30, 0.36, detuneCents: 8)]
        // The same figure doubled before it resolves — more voices, more urgency.
        case .askMulti:
            return [Note(Pitch.g5, at: 0,    0.10, detuneCents: 8),
                    Note(Pitch.c6, at: 0.09, 0.10, detuneCents: 8),
                    Note(Pitch.g5, at: 0.20, 0.10, detuneCents: 8),
                    Note(Pitch.c6, at: 0.29, 0.10, detuneCents: 8),
                    Note(Pitch.e6, at: 0.40, 0.34, detuneCents: 8)]
        // The item-collected jingle: a major arpeggio over two octaves, held at
        // the top. The run is evenly spaced at 0.07 — the prototype writes it as
        // `i * .07`, so the spacing is structural, not five typed numbers.
        case .done:
            let run = [Pitch.c5, Pitch.e5, Pitch.g5, Pitch.c6, Pitch.e6]
            return run.enumerated().map { i, f in
                Note(f, at: Double(i) * 0.07, 0.09, detuneCents: 6)
            } + [Note(Pitch.g6, at: 0.35, 0.46, gain: 0.06, detuneCents: 6)]
        // Falling minor thirds on a saw, sagging at the end.
        case .error:
            return [Note(Pitch.g4,     at: 0,    0.14, waveform: .sawtooth, gain: 0.06),
                    Note(Pitch.eFlat4, at: 0.13, 0.16, waveform: .sawtooth, gain: 0.06),
                    Note(Pitch.c4,     at: 0.28, 0.18, waveform: .sawtooth, gain: 0.06),
                    Note(Pitch.bFlat3, at: 0.45, 0.46, waveform: .sawtooth, gain: 0.06,
                         bend: 0.80)]
        // Two syllables of pitch-bent triangle. 600 and 1040Hz are not named
        // pitches on purpose — a cat is not in tune, and the prototype leaves
        // them raw.
        case .meow:
            return [Note(600,  at: 0,    0.20, waveform: .triangle, gain: 0.09, bend: 1.75),
                    Note(1040, at: 0.19, 0.44, waveform: .triangle, gain: 0.09, bend: 0.52)]
        }
    }
}
