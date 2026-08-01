import SwiftUI

/// Draws a badge inside the fixed box. Monochrome, tinted with the state
/// accent — the badge carries state colour like everything else.
public struct BadgeCanvas: View {
    public let badge: Badge
    public let phase: Double
    public let tint: RGBA
    public let cellSize: CGFloat

    public init(badge: Badge, phase: Double, tint: RGBA, cellSize: CGFloat) {
        self.badge = badge
        self.phase = phase
        self.tint = tint
        self.cellSize = cellSize
    }

    /// The lit cells' rects, unioned into one path.
    ///
    /// A plain property rather than logic inside `Canvas`'s renderer closure,
    /// for the same reason as `CatCanvas.fillsByTone`: the closure only runs
    /// when SwiftUI actually draws, so the walk has to happen here for merely
    /// evaluating `body` (what CanvasTests.swift's trap-catching tests do) to
    /// exercise it at all.
    private var litPath: Path {
        guard cellSize > 0 else { return Path() }
        var path = Path()
        for (row, line) in badge.cells(at: phase).enumerated() {
            for (col, lit) in line.enumerated() where lit {
                path.addRect(CGRect(x: (CGFloat(col) * cellSize).rounded(),
                                    y: (CGFloat(row) * cellSize).rounded(),
                                    width: cellSize, height: cellSize))
            }
        }
        return path
    }

    public var body: some View {
        let path = litPath
        let color = Color(tint)
        Canvas { ctx, _ in
            ctx.fill(path, with: .color(color))
        }
        .frame(width: CGFloat(Badge.size) * cellSize,
               height: CGFloat(Badge.size) * cellSize)
    }
}
