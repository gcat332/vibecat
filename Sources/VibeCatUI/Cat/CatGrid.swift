import VibeCatCore

/// The cat, as cells. Design §7.1's grid verbatim — kept as character art so
/// it stays editable as art rather than as a table of enum cases.
public struct CatGrid: Sendable, Equatable {
    public static let width = 18
    public static let height = 14

    private static let art = [
        "..OO..........OO..",
        ".OEEO........OEEO.",
        ".OEEHO......OHEEO.",
        ".OHHHOOOOOOOOHHHO.",
        ".OLLLLLLLLLLLLLLO.",
        "OHHHHHHHHHHHHHHHHO",
        "OHHHHHHHHHHHHHHHHO",
        "OBBKWWBBBBBBKWWBBO",
        "OBBWPPBBBBBBWPPBBO",
        "OBBPPPBBBBBBPPPBBO",
        "OBBBBBBBNNBBBBBBBO",
        "OSBBBBBOBBOBBBBBSO",
        ".OSSBBBBBBBBBBSSO.",
        "..OOOOOOOOOOOOOO..",
    ]

    public static let base: [[Tone?]] = art.map { line in
        line.map { $0 == "." ? nil : Tone(rawValue: $0) }
    }

    /// The only tones a coat may repaint. Project ruling on §7.3: a coat
    /// repaints *fur*, and only fur — outline and linework (`O`), the pink
    /// inner ear (`E`), the nose (`N`) and the eyes (`W`, `K`, `P`) are not
    /// fur, so they are protected by construction rather than by a
    /// case-by-case exclusion list.
    private static let furTones: Set<Tone> = [.shadow, .body, .highlight, .lightest]

    public let coat: Coat
    public let cells: [[Tone?]]

    public init(coat: Coat) {
        self.coat = coat
        self.cells = Self.apply(coat)
    }

    public subscript(_ col: Int, _ row: Int) -> Tone? {
        guard row >= 0, row < Self.height, col >= 0, col < Self.width else { return nil }
        return cells[row][col]
    }

    private static func apply(_ coat: Coat) -> [[Tone?]] {
        var g = base
        // Repaint only existing fur — never a hole, never the face, never linework.
        func paint(rows: ClosedRange<Int>, cols: ClosedRange<Int>, _ tone: Tone) {
            for row in rows where row >= 0 && row < height {
                for col in cols where col >= 0 && col < width {
                    guard let existing = g[row][col], furTones.contains(existing) else { continue }
                    g[row][col] = tone
                }
            }
        }

        switch coat {
        case .tabby:
            // Four bars down the forehead and one down each cheek.
            //
            // The base art is an *unmarked* cat, so `tabby` used to paint
            // nothing: it differed from `plain` only by the six shadow cells
            // at the paws that `plain` flattens. Six of 210, at the island's
            // ~1pt per cell — rendered side by side they were the same cat,
            // and the coat tests passed because they asserted inequality
            // rather than perceptibility. See `everyPairOfCoatsIsTellableApart`.
            //
            // Bars are symmetric about the grid's centre line (between cols 8
            // and 9): 4↔13 and 7↔10. Rows 5–6 are `highlight` and rows 7–9
            // `body`, so `shadow` reads against both.
            for col in [4, 7, 10, 13] { paint(rows: 5...6, cols: col...col, .shadow) }
            paint(rows: 7...9, cols: 1...1, .shadow)
            paint(rows: 7...9, cols: 16...16, .shadow)
        case .plain:
            for row in 0..<height {
                for col in 0..<width where g[row][col] == .shadow { g[row][col] = .body }
            }
        case .tuxedo:
            paint(rows: 10...12, cols: 6...11, .lightest)
        case .siamese:
            paint(rows: 0...2, cols: 0...width - 1, .lightest)
            paint(rows: 10...11, cols: 5...12, .lightest)
            paint(rows: 5...6, cols: 0...width - 1, .shadow)
        case .patched:
            paint(rows: 5...8, cols: 12...16, .shadow)
        }
        return g
    }
}
