import Foundation

/// The three oscillator shapes §12 calls for, band-limited by construction.
///
/// Built by summing the shape's own Fourier series and stopping below Nyquist,
/// rather than by the obvious `phase < 0.5 ? 1 : -1`. A naive square at G6
/// (1568Hz, which `done` holds for 0.46s) puts harmonics at 4704, 7840, 10976 …
/// well past 22050Hz, and every one above it folds back down as an inharmonic
/// tone. The prototype does not have that hash because Web Audio's `'square'`
/// is band-limited too.
///
/// The series are the standard ones and are **not** peak-normalised. A truncated
/// square overshoots to about 1.09 (Gibbs), so the loudest note this project
/// plays — gain `.09` — peaks near `.098`, three orders of magnitude below
/// clipping. Normalising would cost a peak search per note and change nothing
/// anybody can hear.
public enum Waveform: String, Sendable, CaseIterable {
    case square, sawtooth, triangle

    /// `phase` is in cycles: `0…1` is one period. Values outside that are legal
    /// and periodic, which is what lets a caller integrate phase across a whole
    /// note without wrapping it.
    public func sample(phase: Double, harmonics: Int) -> Double {
        let ω = 2 * Double.pi * phase
        var sum = 0.0
        switch self {
        case .square:
            for n in stride(from: 1, through: harmonics, by: 2) {
                sum += sin(ω * Double(n)) / Double(n)
            }
            return sum * 4 / .pi
        case .sawtooth:
            for n in 1...max(1, harmonics) {
                let sign = n.isMultiple(of: 2) ? -1.0 : 1.0
                sum += sign * sin(ω * Double(n)) / Double(n)
            }
            return sum * 2 / .pi
        case .triangle:
            for k in stride(from: 1, through: harmonics, by: 2) {
                let sign = ((k - 1) / 2).isMultiple(of: 2) ? 1.0 : -1.0
                sum += sign * sin(ω * Double(k)) / Double(k * k)
            }
            return sum * 8 / (.pi * .pi)
        }
    }

    /// How many harmonics fit below Nyquist. Never zero: a note that renders
    /// silence is a defect, not graceful degradation.
    public static func harmonicCount(frequency: Double, sampleRate: Double) -> Int {
        guard frequency > 0 else { return 1 }
        return max(1, Int((sampleRate / 2) / frequency))
    }
}
