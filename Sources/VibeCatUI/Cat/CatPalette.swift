/// One cell's colour role. The raw character is the grid's own alphabet, so
/// the sprite table in CatGrid stays readable as art.
public enum Tone: Character, Sendable, CaseIterable {
    case outline = "O"
    case shadow = "S"
    case body = "B"
    case highlight = "H"
    case lightest = "L"
    case innerEar = "E"
    case nose = "N"
    case eyeWhite = "W"
    case sparkle = "K"
    case pupil = "P"
}

/// The cat's colours for one state.
///
/// Five tones derive from the accent so the fur is always the state's colour —
/// that is what keeps "colour means state" true through every coat. The facial
/// tones are fixed, because a pink nose reads as a nose at any hue and an
/// accent-tinted one does not.
public struct CatPalette: Sendable, Equatable {
    private static let ground = RGBA(hex: "#05070B")!
    private static let white = RGBA(hex: "#FFFFFF")!

    /// The four fixed facial tones, parsed once for the process rather than on
    /// every subscript access.
    ///
    /// These were the more expensive half, and the fix-now item that asked for
    /// this only named the other one ("cache the five accent-derived tones,
    /// 210 cells a frame"). `RGBA(hex:)` parses a *string*, so every read of
    /// `.nose` or `.pupil` was scanning `"#F08098"` and force-unwrapping the
    /// result — strictly more work than the three multiply-adds `over` does,
    /// and on the same hot path.
    private static let innerEar = RGBA(hex: "#F2A0B6")!
    private static let nose = RGBA(hex: "#F08098")!
    private static let pupil = RGBA(hex: "#12131A")!

    private let accent: RGBA

    /// The accent-derived ramp, computed once at init.
    ///
    /// `body` is not stored: it *is* the accent, so caching it would be a second
    /// copy of a value already here and a second thing to keep consistent.
    private let outlineTone: RGBA
    private let shadowTone: RGBA
    private let highlightTone: RGBA
    private let lightestTone: RGBA

    public init(accent: RGBA) {
        self.accent = accent
        outlineTone = Self.over(accent, Self.ground, 0.20)
        shadowTone = Self.over(accent, Self.ground, 0.60)
        highlightTone = Self.over(accent, Self.white, 0.64)
        lightestTone = Self.over(accent, Self.white, 0.36)
    }

    /// `accent` composited onto `base` at `alpha`.
    private static func over(_ accent: RGBA, _ base: RGBA, _ alpha: Double) -> RGBA {
        RGBA(r: accent.r * alpha + base.r * (1 - alpha),
             g: accent.g * alpha + base.g * (1 - alpha),
             b: accent.b * alpha + base.b * (1 - alpha))
    }

    public subscript(_ tone: Tone) -> RGBA {
        switch tone {
        case .outline:   outlineTone
        case .shadow:    shadowTone
        case .body:      accent
        case .highlight: highlightTone
        case .lightest:  lightestTone
        case .innerEar:  Self.innerEar
        case .nose:      Self.nose
        case .eyeWhite:  Self.white
        case .sparkle:   Self.white
        case .pupil:     Self.pupil
        }
    }
}
