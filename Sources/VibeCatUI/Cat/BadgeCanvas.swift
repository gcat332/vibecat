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

    /// Flipped once on appear so the implicit animations have somewhere to go.
    @State private var pulsing = false

    public var body: some View {
        let pulse = badge.pulse
        let side = CGFloat(Badge.size) * cellSize
        // One sub-canvas per part, each with its own delay — that stagger is
        // what the mockup does and what a single Canvas cannot express. The
        // transforms sit on the views, not inside the renderer, so the render
        // server runs them and no `TimelineView` is involved: every badge
        // animates while `needsTimeline` depends only on the cat.
        ZStack(alignment: .topLeading) {
            ForEach(Array(badge.parts(at: phase).enumerated()), id: \.offset) { _, part in
                Canvas { ctx, _ in ctx.fill(Self.path(part.cells, cellSize), with: .color(Color(tint))) }
                    .frame(width: side, height: side)
                    .scaleEffect(pulsing ? pulse.scale.upperBound : pulse.scale.lowerBound)
                    .opacity(pulsing ? pulse.opacity.upperBound : pulse.opacity.lowerBound)
                    .offset(y: pulsing ? -pulse.rise / 2 : pulse.rise / 2)
                    .animation(.easeInOut(duration: pulse.period / 2)
                        .repeatForever(autoreverses: true)
                        .delay(part.delay), value: pulsing)
            }
        }
        .frame(width: side, height: side)
        .onAppear { pulsing = true }
    }

    static func path(_ cells: [[Bool]], _ cellSize: CGFloat) -> Path {
        guard cellSize > 0 else { return Path() }
        var path = Path()
        for (row, line) in cells.enumerated() {
            for (col, lit) in line.enumerated() where lit {
                path.addRect(CGRect(x: (CGFloat(col) * cellSize).rounded(),
                                    y: (CGFloat(row) * cellSize).rounded(),
                                    width: cellSize, height: cellSize))
            }
        }
        return path
    }
}
