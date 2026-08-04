import Foundation
import VibeCatCore

/// §12's five cues. `ask`, `askMulti`, `done` and `error` fire from a state
/// change; `meow` never does — it exists for the Settings sheet's per-cue
/// alternatives and for the prototype's own meow button.
public enum Cue: String, Sendable, CaseIterable {
    case ask, askMulti, done, error, meow
}

/// The oscillator maths for `SoundPack`. **The enum itself now lives in
/// `VibeCatCore/SoundPack.swift`** — `Preferences.pack` needed it visible from
/// Core, and Core may never import `VibeCatUI` — so this is an extension: the
/// pack's *identity* is data Core can hold, its *sound* stays here because
/// `Cue` and `Note` are both UI-level.
public extension SoundPack {
    /// Transcribed from `island-motion.html:894-912`. Every offset, duration,
    /// gain and detune below is from that block. §12's durations are the
    /// arithmetic consequence of the last note's `at + duration` and are
    /// asserted in `everyCueLastsWhatTheSpecTableSays`.
    func notes(for cue: Cue) -> [Note] {
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

/// Plan 6.5 Task 6: resolving `Cue` through the Notifications page's per-cue
/// overrides before the pack's own table is consulted at all.
///
/// **Lives here, not in `CueRenderer.swift`, for the same reason `SoundPack
/// .notes(for:)` does** — `Cue` is UI-level, and this is the second (and, for
/// now, last) place anything maps a `Cue` onto a concrete note list.
/// `CueRenderer.render` calls this instead of `settings.pack.notes(for:)`
/// directly, which is the one-line change that makes `choiceForNeedsAnswer`/
/// `Finish`/`Fail` real rather than merely persisted.
public extension SoundSettings {
    /// `.ask` and `.askMulti` both read `choiceForNeedsAnswer` — the prototype
    /// gives multi-question demand no picker of its own (`settings.html:339-361`
    /// has three per-cue rows, not four), so both share the row that already
    /// exists. `.meow` is not one of the three overridable rows and always
    /// plays its own table regardless of any choice.
    func notes(for cue: Cue) -> [Note] {
        switch cue {
        case .ask, .askMulti: return notes(resolving: choiceForNeedsAnswer, standard: cue)
        case .done:            return notes(resolving: choiceForFinish, standard: cue)
        case .error:           return notes(resolving: choiceForFail, standard: cue)
        case .meow:            return pack.notes(for: .meow)
        }
    }

    /// `.standard` is the cue's own table; `.meow` substitutes the meow cue's
    /// table wholesale; `.none` — written decision 1's third case — renders
    /// nothing, which `CueRenderer.render` already treats as silence for an
    /// empty note list (the same path an empty `SoundPack.silent` table takes).
    private func notes(resolving choice: CueChoice, standard cue: Cue) -> [Note] {
        switch choice {
        case .standard: return pack.notes(for: cue)
        case .meow:     return pack.notes(for: .meow)
        case .none:     return []
        }
    }
}
