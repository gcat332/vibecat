import Foundation
import VibeCatCore

/// What the Sound section of §14 controls, as values.
///
/// **No persistence here on purpose.** `settings.html`'s Sound section is Plan
/// 6.4's; this type exists so the player can be built and tested before the
/// sheet exists. Defaults are the prototype's own, from `settings.html:341-360`:
/// the volume slider's `value="60"`, the Do Not Disturb switch's
/// `aria-checked="true"`, and `Chiptune (default)`.
public struct SoundSettings: Sendable, Equatable {
    public var enabled: Bool
    /// `0…1`, from `settings.html`'s `0…100` slider. Always clamped — see
    /// `clampedVolume`.
    public var volume: Double {
        didSet { volume = Self.clampedVolume(volume) }
    }
    public var quietDuringDoNotDisturb: Bool
    public var pack: SoundPack
    /// §14's three per-cue overrides (`settings.html:344-357`), Plan 6.5 Task
    /// 6's own addition. Each governs more than the one `Cue` its name
    /// suggests: `.ask` and `.askMulti` both read `choiceForNeedsAnswer`,
    /// because the prototype gives multi-question demand no picker of its
    /// own — see `SoundSettings.notes(for:)` in `SoundPack.swift`, the one
    /// place these are actually consulted.
    public var choiceForNeedsAnswer: CueChoice
    public var choiceForFinish: CueChoice
    public var choiceForFail: CueChoice

    /// The one clamp, applied at every boundary a volume can enter through, in the
    /// same shape as `SocketClient.clamped`.
    ///
    /// Nothing today can set a volume out of range, and that is exactly when to add
    /// this: **Plan 6.4 owns `UserDefaults`**, and a persisted value is a value
    /// anything running as this user can write. `CueRenderer` multiplies every
    /// sample by it, so a stored `7` clips the whole cue into a buzz and a stored
    /// `-1` inverts every waveform. This repo has been here before — `AppModel
    /// .ingest` was hardened for an `answerDeadline` decoded off a channel the user
    /// can write to, and the reasoning is the same one: the type cannot tell who
    /// wrote the bytes it was initialised from.
    ///
    /// `NaN` is folded to the default rather than to `0`: `min`/`max` propagate it,
    /// a `NaN` volume renders a silent cue with no error, and silence passes any
    /// test that only counts samples.
    public static func clampedVolume(_ value: Double) -> Double {
        guard value.isFinite else { return defaultVolume }
        return min(1, max(0, value))
    }

    /// `settings.html`'s volume slider ships at `value="60"`.
    public static let defaultVolume: Double = 0.60

    public init(enabled: Bool = true, volume: Double = SoundSettings.defaultVolume,
                quietDuringDoNotDisturb: Bool = true, pack: SoundPack = .chiptune,
                choiceForNeedsAnswer: CueChoice = .standard,
                choiceForFinish: CueChoice = .standard,
                choiceForFail: CueChoice = .standard) {
        self.enabled = enabled
        self.volume = Self.clampedVolume(volume)
        self.quietDuringDoNotDisturb = quietDuringDoNotDisturb
        self.pack = pack
        self.choiceForNeedsAnswer = choiceForNeedsAnswer
        self.choiceForFinish = choiceForFinish
        self.choiceForFail = choiceForFail
    }
}

public extension SoundSettings {
    /// Everything in `Preferences` that this type is the runtime home of.
    ///
    /// **This initialiser exists because two of the three were persisted and never
    /// read.** `main.swift` built `SoundSettings(enabled: preferences.load()
    /// .soundEnabled)` and stopped there, so `volume` and `quietDuringDoNotDisturb`
    /// fell back to this type's own defaults on every launch. `volume` was inert
    /// (both defaults happen to be `0.60`); `quietDuringDoNotDisturb` was not —
    /// `SoundPlayer.wantsSilence` gates every cue on it, so the plist could say
    /// `false` and Focus suppression carried on regardless.
    ///
    /// It is an initialiser in a library rather than three more lines in
    /// `main.swift` for the reason 85e69fb cost a plan to learn: **no test runs
    /// `main.swift`**, because an `executableTarget` with a `main.swift` cannot be
    /// `@testable import`ed. Wiring that has to be right belongs behind something a
    /// test can call.
    ///
    /// **`pack` and the three per-cue choices were the same "persisted but never
    /// read" gap this initialiser already closed twice, a third time.** Plan 6.5
    /// Task 1 gave `Preferences` `pack`/`choiceForNeedsAnswer`/`choiceForFinish`/
    /// `choiceForFail` and `UserDefaultsPreferenceStore` has saved and loaded them
    /// since — but until Task 6, nothing mapped them into the `SoundSettings` the
    /// running engine actually reads, so a pack chosen last session came back to
    /// `.chiptune` on every launch regardless of what was on disk. Exactly the
    /// shape `volume`/`quietDuringDoNotDisturb`/`selectedPage` shipped through six
    /// task reviews before this comment existed to name it.
    init(_ preferences: Preferences) {
        self.init(enabled: preferences.soundEnabled,
                  volume: preferences.volume,
                  quietDuringDoNotDisturb: preferences.quietDuringDoNotDisturb,
                  pack: preferences.pack,
                  choiceForNeedsAnswer: preferences.choiceForNeedsAnswer,
                  choiceForFinish: preferences.choiceForFinish,
                  choiceForFail: preferences.choiceForFail)
    }
}
