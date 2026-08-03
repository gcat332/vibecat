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

    /// Flipped once on appear so the implicit animation below has something to
    /// travel to. `autoreverses` then carries it back and forth forever.
    @State private var pulsing = false

    public var body: some View {
        let path = litPath
        let color = Color(tint)
        let pulse = badge.pulse
        Canvas { ctx, _ in
            ctx.fill(path, with: .color(color))
        }
        .frame(width: CGFloat(Badge.size) * cellSize,
               height: CGFloat(Badge.size) * cellSize)
        // The prototype animates every badge by transform, not by changing
        // which cells are lit — see `Badge.pulse`. Applied as modifiers on the
        // whole canvas rather than inside the renderer, so the render server
        // runs it and no `TimelineView` is needed: `zzz`, `check` and `cross`
        // animate while `needsTimeline` stays false and the island keeps its
        // 0.35%-of-a-core idle. `squares` opts out because its cells already
        // turn, and scaling on top would double the motion.
        .scaleEffect(pulse.map { pulsing ? $0.scale.upperBound : $0.scale.lowerBound } ?? 1)
        .opacity(pulse.map { pulsing ? $0.opacity.upperBound : $0.opacity.lowerBound } ?? 1)
        .animation(pulse.map {
            .easeInOut(duration: $0.period / 2).repeatForever(autoreverses: true)
        }, value: pulsing)
        .onAppear { if pulse != nil { pulsing = true } }
    }
}
