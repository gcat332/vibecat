import Foundation

/// What colour the aura is, and how strong, against the backdrop it has to be
/// seen on.
///
/// A coloured shadow works by pulling the pixels behind it toward its own
/// colour: `B + α(C − B)`. On a dark menu bar the accent is most of the
/// distance away, so the bloom reads as light spilling outward — which is what
/// design §9.2 describes and what the constant was tuned for.
///
/// On a *light* menu bar there is nowhere to go. Measured on a real screen in
/// Light mode, with the bar at 234 grey, the bloom lifted the halo by **8
/// levels summed across R, G and B** against 26 on a dark backdrop. Present in
/// the numbers, a faint stain to the eye.
///
/// More opacity is not the fix. Enough amber to register on white is garish on
/// black, and the two cannot share one number. What changes is the *colour*:
/// on a light backdrop the glow goes **down** instead of up — a deepened
/// accent, which is the only direction with any contrast left in it. The hue
/// is untouched either way, so §4.3 still holds: the aura is the state's
/// colour, and only the state's colour.
public struct AuraTint: Sendable, Equatable {
    public let colour: RGBA
    public let peakOpacity: Double

    /// How far toward black a light-backdrop glow is pushed. Not a tuning dial
    /// so much as the answer to "how dark before it separates from a 234 bar":
    /// below about 0.5 the accent stops reading as its own hue and turns into
    /// a generic grey shadow, and above it there is not enough contrast left.
    static let deepening: Double = 0.5

    public init(accent: RGBA, onLightBackdrop: Bool) {
        if onLightBackdrop {
            colour = RGBA(r: accent.r * Self.deepening,
                          g: accent.g * Self.deepening,
                          b: accent.b * Self.deepening)
            peakOpacity = Self.lightPeakOpacity
        } else {
            colour = accent
            peakOpacity = Self.darkPeakOpacity
        }
    }

    /// Both measured with `auraOpacitySweep`, against the backdrop each one is
    /// for, to the same target: a halo lift of roughly 26 levels summed across
    /// RGB at the peak of the bloom. Equal *perceived* strength, which two
    /// equal numbers would not have given — 0.34 on the light bar lifts 30,
    /// and 0.30 on the dark one lifts 23.
    ///
    /// Both curves are near enough linear at about 76 levels per unit of
    /// opacity, which is a coincidence of the two backdrops being roughly
    /// equidistant from their respective glow colours, not a law.
    public static let darkPeakOpacity: Double = 0.34
    public static let lightPeakOpacity: Double = 0.30
}
