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
        if t < attack {
            return floor * pow(gain / floor, t / attack)
        }
        // A note whose whole duration fits inside the attack never gets a tail;
        // the guard above has already returned the floor for it.
        let tail = duration - attack
        guard tail > 0 else { return floor }
        return gain * pow(floor / gain, (t - attack) / tail)
    }
}
