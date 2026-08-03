import Foundation

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
                quietDuringDoNotDisturb: Bool = true, pack: SoundPack = .chiptune) {
        self.enabled = enabled
        self.volume = Self.clampedVolume(volume)
        self.quietDuringDoNotDisturb = quietDuringDoNotDisturb
        self.pack = pack
    }
}
