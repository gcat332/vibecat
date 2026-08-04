import Foundation

/// A pack is "a handful of oscillator settings rather than a folder of files"
/// (§12). Only the identity lives here in Core — `Preferences.pack` needs a
/// visible type and Core may never import `VibeCatUI` — while the oscillator
/// maths that turns a pack and a `Cue` into notes stays in
/// `VibeCatUI/Sound/SoundPack.swift` as an extension, since `Cue` and `Note`
/// are both UI-level.
///
/// **Only `chiptune` and `silent` exist, deliberately.** `settings.html` offers
/// Chiptune / Soft / System / Silent and per-cue alternatives Blip / Meow /
/// None, but nothing in this repo defines what Soft, System or Blip sound like
/// — no frequencies, no waveforms, nothing. Inventing them would be inventing
/// design rather than implementing it. Adding a case later is additive.
public enum SoundPack: String, Sendable, CaseIterable {
    case chiptune, silent
}
