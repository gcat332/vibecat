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
    /// `0…1`, from `settings.html`'s `0…100` slider.
    public var volume: Double
    public var quietDuringDoNotDisturb: Bool
    public var pack: SoundPack

    public init(enabled: Bool = true, volume: Double = 0.60,
                quietDuringDoNotDisturb: Bool = true, pack: SoundPack = .chiptune) {
        self.enabled = enabled
        self.volume = volume
        self.quietDuringDoNotDisturb = quietDuringDoNotDisturb
        self.pack = pack
    }
}
