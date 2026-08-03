import Foundation

/// The note table from `island-motion.html:890-892`, verbatim.
///
/// Equal temperament above A5 = 880Hz. Eight of the prototype's entries have no
/// cue that uses them (`d5 f5 a5 b5 d6 f4 e4 g3`) — they are there because the
/// prototype's own comment says a pack "retunes per state for free", and
/// deleting them would remove the scaffolding for the alternative packs
/// `settings.html` offers.
public enum Pitch {
    public static let c5 = 523.25, d5 = 587.33, e5 = 659.25, f5 = 698.46
    public static let g5 = 783.99, a5 = 880.0,  b5 = 987.77
    public static let c6 = 1046.5, d6 = 1174.7, e6 = 1318.5, g6 = 1568.0
    public static let g4 = 392.0,  f4 = 349.23, e4 = 329.63
    public static let c4 = 261.63, eFlat4 = 311.13, bFlat3 = 233.08, g3 = 196.0
}

/// One note of a cue. Mirrors the prototype's
/// `note(freq, at, dur, {type, gain, bend, duty})` argument for argument, so a
/// reader can diff a cue against `island-motion.html:894-912` by eye.
public struct Note: Sendable, Equatable {
    public let frequency: Double
    /// Offset from the start of the cue, not from the note before it.
    public let at: TimeInterval
    public let duration: TimeInterval
    public let waveform: Waveform
    public let gain: Double
    /// The prototype's `bend`: the frequency ramps exponentially to
    /// `frequency * bend` across the note. **`0` means no bend**, which is how
    /// the prototype spells it — see `phase(at:detuned:)`.
    public let bend: Double
    /// The prototype's `duty`, in cents. `0` means no twin.
    public let detuneCents: Double

    public init(_ frequency: Double, at: TimeInterval, _ duration: TimeInterval,
                waveform: Waveform = .square, gain: Double = 0.07,
                bend: Double = 0, detuneCents: Double = 0) {
        self.frequency = frequency
        self.at = at
        self.duration = duration
        self.waveform = waveform
        self.gain = gain
        self.bend = bend
        self.detuneCents = detuneCents
    }

    public var end: TimeInterval { at + duration }

    /// Phase in cycles, `t` measured from the note's own onset.
    ///
    /// An unbent note is just `f·t`. A bent one has an instantaneous frequency
    /// of `f₀·b^(t/D)` — Web Audio's `exponentialRampToValueAtTime` — and a
    /// sample generator needs the integral of that, not the value:
    ///
    ///     φ(t) = ∫₀ᵗ f₀·b^(τ/D) dτ = f₀·D·(b^(t/D) − 1) / ln b
    ///
    /// Using the frequency directly instead of its integral does not fail
    /// loudly; it plays the note at the wrong pitch, which is why this is
    /// asserted by differentiating rather than by listening.
    ///
    /// **`bend == 0` and `bend == 1` both mean "no ramp".** The prototype
    /// spells "no bend" as `0`, and `ln 0` is `-∞`: applying the closed form to
    /// it would make every plain note in the pack `NaN`, which renders as
    /// silence — and silence passes any test that only counts samples.
    public func phase(at t: TimeInterval, detuned: Bool) -> Double {
        let f0 = detuned ? frequency * pow(2, detuneCents / 1200) : frequency
        guard bend > 0, bend != 1, duration > 0 else { return f0 * t }
        return f0 * duration * (pow(bend, t / duration) - 1) / log(bend)
    }
}
