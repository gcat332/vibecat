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

    private let accent: RGBA

    public init(accent: RGBA) { self.accent = accent }

    /// `accent` composited onto `base` at `alpha`.
    private static func over(_ accent: RGBA, _ base: RGBA, _ alpha: Double) -> RGBA {
        RGBA(r: accent.r * alpha + base.r * (1 - alpha),
             g: accent.g * alpha + base.g * (1 - alpha),
             b: accent.b * alpha + base.b * (1 - alpha))
    }

    public subscript(_ tone: Tone) -> RGBA {
        switch tone {
        case .outline:   Self.over(accent, Self.ground, 0.20)
        case .shadow:    Self.over(accent, Self.ground, 0.60)
        case .body:      accent
        case .highlight: Self.over(accent, Self.white, 0.64)
        case .lightest:  Self.over(accent, Self.white, 0.36)
        case .innerEar:  RGBA(hex: "#F2A0B6")!
        case .nose:      RGBA(hex: "#F08098")!
        case .eyeWhite:  RGBA(hex: "#FFFFFF")!
        case .sparkle:   RGBA(hex: "#FFFFFF")!
        case .pupil:     RGBA(hex: "#12131A")!
        }
    }
}
