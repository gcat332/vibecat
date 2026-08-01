import SwiftUI

/// Draws a resolved cat.
///
/// The spike found path batching makes no measurable difference — 20.3% batched
/// against 20.5% unbatched at the same rate, because the cost is per-frame
/// overhead and not the fills. So this draws the clear way: one rect per cell,
/// cells sharing a tone accumulated into that tone's own path so there is one
/// draw call per tone rather than one per cell. Grouping by tone is for fewer
/// colour switches, not for speed.
public struct CatCanvas: View {
    public let cat: ResolvedCat
    public let palette: CatPalette
    public let cellSize: CGFloat

    public init(cat: ResolvedCat, palette: CatPalette, cellSize: CGFloat) {
        self.cat = cat
        self.palette = palette
        self.cellSize = cellSize
    }

    /// Every non-transparent cell's rect, grouped by tone, each tone's colour
    /// already looked up.
    ///
    /// Deliberately a plain property rather than logic inside `Canvas`'s
    /// renderer closure. That closure is `@escaping` and only runs when
    /// SwiftUI actually draws — verified empirically, a `Canvas` whose
    /// renderer flips a flag leaves it unset after merely accessing `body`.
    /// CanvasTests.swift's tests exist to walk every cell and look up every
    /// tone across every coat/mood/phase and catch a trap; if that walk
    /// lived inside the closure instead, evaluating `body` would exercise
    /// none of it and the tests would pass whether or not the walk was
    /// correct. Computing the plan here means `body` alone still does the
    /// whole walk, and the closure below is left with nothing but the fill
    /// calls.
    private var fillsByTone: [(Color, Path)] {
        guard cellSize > 0 else { return [] }
        let dy = CGFloat(cat.verticalOffset) * cellSize
        var byTone: [Tone: Path] = [:]
        for (row, line) in cat.cells.enumerated() {
            for (col, tone) in line.enumerated() {
                guard let tone else { continue }
                // Integer boundaries — pixel art must land on the grid.
                let rect = CGRect(x: (CGFloat(col) * cellSize).rounded(),
                                  y: (CGFloat(row) * cellSize + dy).rounded(),
                                  width: cellSize, height: cellSize)
                byTone[tone, default: Path()].addRect(rect)
            }
        }
        return byTone.map { (Color(palette[$0.key]), $0.value) }
    }

    public var body: some View {
        let fills = fillsByTone
        Canvas { ctx, _ in
            for (color, path) in fills {
                ctx.fill(path, with: .color(color))
            }
        }
        .frame(width: CGFloat(CatGrid.width) * cellSize,
               height: CGFloat(CatGrid.height) * cellSize)
    }
}
