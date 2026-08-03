import Foundation

/// §12's "hard attack (`6ms`), exponential decay — the whole character of the
/// era", as the prototype actually implements it at `island-motion.html:873-875`.
///
/// Web Audio's `exponentialRampToValueAtTime` between `(t₁,v₁)` and `(t₂,v₂)` is
/// `v₁ · (v₂/v₁)^((t−t₁)/(t₂−t₁))`, and that is what these two branches are.
public struct ToneEnvelope: Sendable {
    /// §12's 6ms. Hard enough to read as an attack rather than a swell.
    public static let attack: TimeInterval = 0.006

    /// **Not zero, and not a rounding artefact.** An exponential ramp cannot
    /// reach or cross zero — `v₁ · (0/v₁)^x` is zero everywhere — so Web Audio's
    /// own idiom ramps between small positive values. Ending a note at true zero
    /// instead of gliding to a floor is an audible click at the release. Do not
    /// "simplify" this away.
    public static let floor: Double = 0.0001

    public static func amplitude(at t: TimeInterval, duration: TimeInterval, gain: Double) -> Double {
        guard t > 0 else { return floor }
        guard t < duration else { return floor }
        // Clamped rather than used verbatim: a note shorter than the standard
        // 6ms would otherwise stop mid-ramp at a non-zero amplitude — the same
        // audible click `floor` exists to prevent, arriving by a different
        // route. No cue in the chiptune pack is anywhere near this short (the
        // shortest is 0.09s), so this never engages for a real note.
        let attack = min(Self.attack, duration / 2)
        if t < attack {
            return floor * pow(gain / floor, t / attack)
        }
        // `t >= attack` here (the branch above didn't take) and `t < duration`
        // (the guard above didn't take), so `duration > attack`, which makes
        // `tail > 0` unconditionally: attack <= duration / 2 < duration.
        let tail = duration - attack
        return gain * pow(floor / gain, (t - attack) / tail)
    }
}
