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

    /// Flipped once on appear so the implicit animations have somewhere to go.
    @State private var pulsing = false

    #if DEBUG
    /// Counts invocations of the `Canvas` renderer below — actual draws, not
    /// body builds. Read by `BadgeCPUProbe` to settle the question `Badge
    /// .pulse` records as unmeasured: whether the repeating `.scaleEffect`/
    /// `.opacity` this file declares is run by the render server without
    /// asking SwiftUI to draw again, or re-invokes this renderer every frame.
    /// If the latter, the badges cost what the cell-swapping version they
    /// replaced cost and the idle island's 0.35% of a core is gone.
    ///
    /// It has to live inside the closure to mean that. `theBadgeDrawCounter
    /// CountsDrawsRatherThanBodyEvaluations` in CanvasTests.swift pins both
    /// halves — body evaluation must not move it, a real render must.
    ///
    /// `#if DEBUG`-gated for the same reason `IslandView.buildCount` is: pure
    /// instrumentation, and `swift test` and `Scripts/build-app.sh`'s default
    /// both build debug, so nothing that needs it loses it.
    @MainActor public static var canvasDrawCount = 0
    #endif

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
                Canvas { ctx, _ in
                    #if DEBUG
                    Self.canvasDrawCount += 1
                    #endif
                    ctx.fill(Self.path(part.cells, cellSize), with: .color(Color(tint)))
                }
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
