import SwiftUI

/// Draws a badge inside the fixed box. Monochrome, tinted with the state
/// accent — the badge carries state colour like everything else.
public struct BadgeCanvas: View {
    public let badge: Badge
    public let phase: Double
    public let tint: RGBA
    public let cellSize: CGFloat
    /// §9.3, and **not** defaulted.
    ///
    /// The badge-transform spike recorded that this view "never consults
    /// `MotionPreference` at all, so every badge animates in the configuration
    /// the design says must not animate, and nothing a person can choose turns
    /// this 12% off" — measured: motion `.off` *with* system Reduce Motion on
    /// cost 11.83% of a core against 12.26% with motion full, a difference
    /// inside either spread. A defaulted parameter would let the next call site
    /// reintroduce that silently; a required one makes consulting the
    /// preference structural rather than remembered.
    public let motion: MotionPreference

    public init(badge: Badge, phase: Double, tint: RGBA, cellSize: CGFloat,
                motion: MotionPreference) {
        self.badge = badge
        self.phase = phase
        self.tint = tint
        self.cellSize = cellSize
        self.motion = motion
    }

    /// Flipped once on appear so the implicit animations have somewhere to go —
    /// and only if §9.3 allows any. `onChange` keeps it in step afterwards,
    /// because Reduce Motion is now a live setting (`NotchController
    /// .refreshMotion()`) and `onAppear` fires only once: without it, motion
    /// turned back on mid-run would leave `pulsing` false forever, so the
    /// animation below would have no value change to react to and the badge
    /// would sit dead at its own resting pose.
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
        let moves = motion.allowsMotion
        // The pose every part is drawn at.
        //
        // With motion off there is no animation, so the badge has to sit at the
        // mockup's own **base** style — scale 1, full opacity, no offset — and
        // never at a keyframe's extreme. `island-motion.html:439` is the
        // authority: its entire reduced-motion rule is `animation:none`, and a
        // CSS element with no animation renders at its base style, not at `0%`.
        // Leaving the `pulsing ? upper : lower` expression to stand with the
        // animation removed would render every badge at its *lower* keyframe
        // instead, which for `zzz` is `zfloat`'s `opacity:0` — a permanently
        // invisible badge in the one configuration §9.3 says must be calm
        // rather than blank, and `squares`/`check` at 0.28 and 0.55 opacity and
        // half size in the others.
        let scale = moves ? (pulsing ? pulse.scale.upperBound : pulse.scale.lowerBound) : 1
        let opacity = moves ? (pulsing ? pulse.opacity.upperBound : pulse.opacity.lowerBound) : 1
        let riseY = moves ? (pulsing ? -pulse.rise / 2 : pulse.rise / 2) : 0
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
                    .scaleEffect(scale)
                    .opacity(opacity)
                    .offset(y: riseY)
                    // `nil`, not a shorter duration, when motion is off: the
                    // spike's whole finding was that a `.repeatForever`
                    // transform keeps something ticking every display frame
                    // whether or not SwiftUI redraws, so the animation has to
                    // stop existing rather than merely slow down.
                    .animation(moves ? .easeInOut(duration: pulse.period / 2)
                        .repeatForever(autoreverses: true)
                        .delay(part.delay) : nil, value: pulsing)
            }
        }
        .frame(width: side, height: side)
        .onAppear { pulsing = moves }
        .onChange(of: moves) { _, allowed in pulsing = allowed }
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
