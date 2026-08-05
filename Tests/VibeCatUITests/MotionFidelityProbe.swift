import AppKit
import Foundation
import SwiftUI
import Testing
import VibeCatCore
@testable import VibeCatUI

// ─────────────────────────────────────────────────────────────────────────────
// THROWAWAY PROBE — motion-fidelity investigation, 2026-08-05.
// Asserts nothing. Env-gated like every other preview tool in this suite.
// Delete once the plan it feeds has landed:
//
//     VIBECAT_MOTION_PROBE=1 swift test --filter MotionFidelityProbe
//     VIBECAT_MOTION_PROBE=1 VIBECAT_MOTION_STRIP=/tmp/morph.png \
//         VIBECAT_MOTION_GIF=/tmp/morph.gif swift test --filter MotionFidelityProbe
// ─────────────────────────────────────────────────────────────────────────────

/// A CSS cubic-bezier's y at a given x, by bisection on x. Same routine as
/// `MotionCurveComparison.bezier`, copied so this file can be deleted whole.
func bez(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, atX x: Double) -> Double {
    func axis(_ p1: Double, _ p2: Double, _ t: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t
    }
    var lo = 0.0, hi = 1.0
    for _ in 0..<60 {
        let mid = (lo + hi) / 2
        if axis(x1, x2, mid) < x { lo = mid } else { hi = mid }
    }
    return axis(y1, y2, (lo + hi) / 2)
}

/// A CSS transition: the curve, held at 1 once the duration is up.
func css(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double,
         duration: Double, atMs ms: Double) -> Double {
    ms >= duration * 1000 ? 1 : bez(x1, y1, x2, y2, atX: (ms / 1000) / duration)
}

func f(_ v: Double, _ d: Int = 1) -> String { String(format: "%.\(d)f", v) }
func pct(_ v: Double) -> String { String(format: "%6.1f%%", v * 100) }
func pad(_ s: String, _ n: Int) -> String {
    s.count >= n ? s : String(repeating: " ", count: n - s.count) + s
}

@Suite("Motion fidelity probe")
struct MotionFidelityProbe {
    static var on: Bool { ProcessInfo.processInfo.environment["VIBECAT_MOTION_PROBE"] != nil }

    // MARK: - 1. Hover

    @Test(.enabled(if: Self.on))
    @MainActor func hoverCurves() {
        print("""

        ══════════════════════════════════════════════════════════════════════
        HOVER — what animates, and on which curve
        ══════════════════════════════════════════════════════════════════════
        prototype (island-motion.html)
          .island        width      440ms  cubic-bezier(.32,1.5,.5,1)   [--t-shape/--spring-w]
          .island        transform  440ms  cubic-bezier(.32,1.5,.5,1)   (recentring shift)
          .flank.r       width      440ms  cubic-bezier(.32,1.5,.5,1)   (--rw)
          .detail        max-width  280ms  cubic-bezier(.22,.9,.28,1)   [--t-hover/--ease]
          .detail        margin     280ms  cubic-bezier(.22,.9,.28,1)
          .detail        opacity    160ms  cubic-bezier(.22,.9,.28,1)
        ours — SINCE PLAN 6.3 TASK 4, three clocks (IslandView.swift)
          silhouette .frame width  spring(response .42 / damping .62)  IslandMotion.widthSpring
          RevealContent .frame     280ms  cubic-bezier(.22,.9,.28,1)   IslandMotion.hoverRevealDuration
          RevealContent .opacity   160ms  cubic-bezier(.22,.9,.28,1)   IslandMotion.hoverFadeDuration
        ours — BEFORE Task 4
          all three on one modifier, 280ms cubic-bezier(.22,.9,.28,1). Was `.easeOut`
          until Task 3, so the `.easeOut` columns below are a record of what Task 3
          fixed, not of live code at any point after it. `hoverThreeClocks()` prints
          the live comparison.
        """)

        // SwiftUI's `.easeOut`, sampled rather than assumed. `UnitCurve.easeOut`
        // is documented as the same curve `Animation.easeOut` uses; printed next
        // to CSS `ease-out` = cubic-bezier(0,0,.58,1) so the report can say which.
        print("""

          t(ms)  proto .island width(440/spring-w)  proto .detail(280/--ease)  ours .easeOut(280)  UnitCurve  css ease-out
        """)
        for ms in stride(from: 0.0, through: 500.0, by: 40.0) {
            let islandW = css(0.32, 1.5, 0.5, 1, duration: 0.440, atMs: ms)
            let detail = css(0.22, 0.9, 0.28, 1, duration: 0.280, atMs: ms)
            let ourP = min(1.0, ms / 280.0)
            let ours = UnitCurve.easeOut.value(at: ourP)
            let cssEO = ms >= 280 ? 1 : bez(0, 0, 0.58, 1, atX: ourP)
            print("  \(String(format: "%5.0f", ms))            \(pct(islandW))                    \(pct(detail))          \(pct(ours))    \(pct(ours))  \(pct(cssEO))")
        }

        // Worst deviation, ours against each of the prototype's two curves.
        func worst(_ proto: (Double) -> Double) -> (dev: Double, ms: Double, p: Double, o: Double) {
            var w = (0.0, 0.0, 0.0, 0.0)
            for step in 0...200 {
                let ms = Double(step) * 5
                let p = proto(ms)
                let o = UnitCurve.easeOut.value(at: min(1.0, ms / 280.0))
                if abs(p - o) > w.0 { w = (abs(p - o), ms, p, o) }
            }
            return w
        }
        let vsIsland = worst { css(0.32, 1.5, 0.5, 1, duration: 0.440, atMs: $0) }
        let vsDetail = worst { css(0.22, 0.9, 0.28, 1, duration: 0.280, atMs: $0) }
        print("""

          ours vs prototype .island width : worst \(pct(vsIsland.dev)) at \(Int(vsIsland.ms))ms (proto \(pct(vsIsland.p)) / ours \(pct(vsIsland.o)))
          ours vs prototype .detail       : worst \(pct(vsDetail.dev)) at \(Int(vsDetail.ms))ms (proto \(pct(vsDetail.p)) / ours \(pct(vsDetail.o)))
        """)

        // How far each actually travels.
        let g = IslandGeometry(screen: IslandGoldenTests.mbp14)
        let rest = CollapsedLayout(right: .sessionCount(3), hovering: false)
        let hov = CollapsedLayout(right: .sessionCount(3), hovering: true)
        print("""

          travel, mbp14 / 3 sessions
            ours              body \(f(g.frames(rightFlank: rest.rightFlankWidth, tier: .rest).body.width))pt → \(f(g.frames(rightFlank: hov.rightFlankWidth, tier: .hover).body.width))pt  (+\(f(CollapsedLayout.hoverReveal))pt, flat)
            prototype         width grows by the detail's own scrollWidth + 9px margin,
                              visually clipped at max-width:150px — so the container's
                              travel is content-dependent, ours is a constant 150.
        """)
    }

    // MARK: - 1b. Hover's three clocks — the live comparison, and the GIF

    /// The three clocks the prototype runs on hover, against ours before and after
    /// Plan 6.3 Task 4, all sampled from the production constants.
    ///
    /// `hoverCurves()` above compares `.easeOut` — the curve Task 3 removed — so its
    /// headline numbers (38.1% / 29.1%) are a record of a state the code has not
    /// been in since Task 3. This is the one to read.
    @Test(.enabled(if: Self.on))
    @MainActor func hoverThreeClocks() {
        let travel = CollapsedLayout.hoverReveal
        let restingW = 273.1

        let protoShape: (Double) -> Double = { css(0.32, 1.5, 0.5, 1, duration: 0.440, atMs: $0) }
        let protoReveal: (Double) -> Double = { css(0.22, 0.9, 0.28, 1, duration: 0.280, atMs: $0) }
        let protoFade: (Double) -> Double = { css(0.22, 0.9, 0.28, 1, duration: 0.160, atMs: $0) }
        // Before Task 4: one `--ease` at `--t-hover`, over all three.
        let before: (Double) -> Double = { css(0.22, 0.9, 0.28, 1, duration: 0.280, atMs: $0) }
        // After: the shape on `IslandMotion.widthSpring`, the two content clocks on
        // `--ease` at their own durations. Read from the production constants.
        let wSpring = Spring(response: IslandMotion.response, dampingRatio: IslandMotion.widthDamping)
        let afterShape: (Double) -> Double = { wSpring.value(target: 1.0, time: $0 / 1000) }
        let afterReveal: (Double) -> Double = {
            IslandMotion.easeCurve.value(at: min(1, ($0 / 1000) / IslandMotion.hoverRevealDuration))
        }
        let afterFade: (Double) -> Double = {
            IslandMotion.easeCurve.value(at: min(1, ($0 / 1000) / IslandMotion.hoverFadeDuration))
        }

        func worst(_ a: (Double) -> Double, _ b: (Double) -> Double) -> (dev: Double, ms: Double, p: Double, o: Double) {
            var w = (0.0, 0.0, 0.0, 0.0)
            for step in 0...300 {
                let ms = Double(step) * 5
                let p = a(ms), o = b(ms)
                if abs(p - o) > w.0 { w = (abs(p - o), ms, p, o) }
            }
            return w
        }
        func peak(_ f: (Double) -> Double) -> (v: Double, ms: Double) {
            var best = (0.0, 0.0)
            for step in 0...400 {
                let ms = Double(step) * 2
                let v = f(ms)
                if v > best.0 { best = (v, ms) }
            }
            return best
        }

        print("""

        ══════════════════════════════════════════════════════════════════════
        HOVER — THREE CLOCKS, prototype vs ours before and after Plan 6.3 Task 4
        ══════════════════════════════════════════════════════════════════════
                       prototype                  before Task 4        after Task 4
          shape width  --spring-w / 440ms         --ease / 280ms       widthSpring (.42/\(f(IslandMotion.widthDamping, 2)))
          reveal width --ease / 280ms             --ease / 280ms       --ease / \(f(IslandMotion.hoverRevealDuration * 1000, 0))ms
          reveal fade  --ease / 160ms             --ease / 280ms       --ease / \(f(IslandMotion.hoverFadeDuration * 1000, 0))ms

          worst deviation from the prototype's own clock, 5ms steps to 1500ms
                        before Task 4                       after Task 4
        """)
        for (label, proto, b, a) in [("shape ", protoShape, before, afterShape),
                                     ("reveal", protoReveal, before, afterReveal),
                                     ("fade  ", protoFade, before, afterFade)] {
            let wb = worst(proto, b), wa = worst(proto, a)
            print("  \(label)   \(pct(wb.dev)) at \(pad("\(Int(wb.ms))", 4))ms (proto \(pct(wb.p)) / ours \(pct(wb.o)))   \(pct(wa.dev)) at \(pad("\(Int(wa.ms))", 4))ms (proto \(pct(wa.p)) / ours \(pct(wa.o)))")
        }

        let pp = peak(protoShape), pb = peak(before), pa = peak(afterShape)
        print("""

          §9.1's OVERSHOOT on the shape clock — the rule hover did not have
            prototype     peak \(pct(pp.v)) at \(Int(pp.ms))ms
            before Task 4 peak \(pct(pb.v)) at \(Int(pb.ms))ms   ← monotone: --ease cannot exceed its target
            after Task 4  peak \(pct(pa.v)) at \(Int(pa.ms))ms   (+\(f((pa.v - 1) * travel, 2))pt past \(f(restingW + travel))pt on a \(f(travel))pt reveal)

          ORDERING — the reveal's own width when the fade lands (\(f(IslandMotion.hoverFadeDuration * 1000, 0))ms)
            prototype     \(pct(protoReveal(IslandMotion.hoverFadeDuration * 1000)))
            before Task 4 \(pct(before(280)))   ← both on one clock, so they land together
            after Task 4  \(pct(afterReveal(IslandMotion.hoverFadeDuration * 1000)))

          t(ms)   proto shape   after shape   proto reveal  after reveal  proto fade  after fade
        """)
        for ms in stride(from: 0.0, through: 480.0, by: 40.0) {
            print("  \(String(format: "%5.0f", ms))     \(pct(protoShape(ms)))       \(pct(afterShape(ms)))       \(pct(protoReveal(ms)))       \(pct(afterReveal(ms)))     \(pct(protoFade(ms)))     \(pct(afterFade(ms)))")
        }
    }

    /// **The hover, as motion, prototype against ours — and measured off the GIF's
    /// own pixels rather than described.**
    ///
    ///     VIBECAT_MOTION_PROBE=1 VIBECAT_GIF=/tmp/hover.gif \
    ///         swift test --no-parallel --filter hoverGIF
    ///
    /// Three bands per frame, all three starting from the same 273.1pt resting
    /// width and revealing the same 150pt:
    ///
    /// | band | colour | shape clock | reveal clock | fade clock |
    /// |---|---|---|---|---|
    /// | prototype | `#FFA63C` | `--spring-w` / 440ms | `--ease` / 280ms | `--ease` / 160ms |
    /// | ours, after Task 4 | `#5B9DF9` | `widthSpring` | `--ease` / 280ms | `--ease` / 160ms |
    /// | ours, before Task 4 | `#8A93A6` | `--ease` / 280ms | `--ease` / 280ms | `--ease` / 280ms |
    ///
    /// The reveal is drawn as a `--bone` bar right-aligned inside its own
    /// silhouette, at its own width and its own opacity, because that is the
    /// property the middle and bottom bands differ on and a silhouette alone would
    /// not show it.
    ///
    /// Every number the report quotes about this file is then read back out of the
    /// rasters: painted columns per band per frame, and the bar's own alpha
    /// recovered from its rendered colour over `--void`. Nothing here is an
    /// impression.
    @Test(.enabled(if: Self.on && ProcessInfo.processInfo.environment["VIBECAT_GIF"] != nil))
    @MainActor func hoverGIF() throws {
        let path = ProcessInfo.processInfo.environment["VIBECAT_GIF"]!
        let travel = CollapsedLayout.hoverReveal      // 150
        let resting = 273.1                           // mbp14 / 3 sessions, measured
        let stage: CGFloat = 700
        let bandHeight: CGFloat = 44

        struct Band {
            let name: String
            let tint: RGBA
            let shape: (Double) -> Double
            let reveal: (Double) -> Double
            let fade: (Double) -> Double
        }
        let wSpring = Spring(response: IslandMotion.response, dampingRatio: IslandMotion.widthDamping)
        let easeAt: (Double, Double) -> Double = { ms, dur in
            IslandMotion.easeCurve.value(at: min(1, (ms / 1000) / dur))
        }
        let bands = [
            Band(name: "prototype", tint: RGBA(hex: "#FFA63C")!,
                 shape: { css(0.32, 1.5, 0.5, 1, duration: 0.440, atMs: $0) },
                 reveal: { css(0.22, 0.9, 0.28, 1, duration: 0.280, atMs: $0) },
                 fade: { css(0.22, 0.9, 0.28, 1, duration: 0.160, atMs: $0) }),
            Band(name: "ours, after ", tint: RGBA(hex: "#5B9DF9")!,
                 shape: { wSpring.value(target: 1.0, time: $0 / 1000) },
                 reveal: { easeAt($0, IslandMotion.hoverRevealDuration) },
                 fade: { easeAt($0, IslandMotion.hoverFadeDuration) }),
            Band(name: "ours, before", tint: RGBA(hex: "#8A93A6")!,
                 shape: { easeAt($0, 0.28) },
                 reveal: { easeAt($0, 0.28) },
                 fade: { easeAt($0, 0.28) }),
        ]

        @MainActor func band(_ b: Band, atMs ms: Double) -> some View {
            let w = resting + travel * b.shape(ms)
            let rw = travel * b.reveal(ms)
            return ZStack(alignment: .topLeading) {
                // A clear stage the shapes can never outgrow: `.frame(width:)`
                // affects layout where `.offset` does not, so a stage the overshoot
                // could exceed would give the GIF frames of differing sizes.
                Color.clear.frame(width: stage, height: bandHeight)
                IslandShape().fill(Color(b.tint).opacity(0.92))
                    .frame(width: w, height: 30)
                // The revealed text, right-aligned inside the flank — its own
                // width, its own opacity, over the island's own ground so the
                // recovered alpha below means something.
                Rectangle().fill(Color(boneColour))
                    .frame(width: rw, height: 9)
                    .opacity(b.fade(ms))
                    .offset(x: w - rw - 12, y: 10)
            }
        }

        @MainActor func frame(atMs ms: Double) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(Int(ms))ms").font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color(hazeColour))
                    .frame(width: stage, height: 14, alignment: .leading)
                ForEach(bands.indices, id: \.self) { i in band(bands[i], atMs: ms) }
            }
            .padding(6)
            .background(Color(islandGroundColour))
        }

        let times = stride(from: 0.0, through: 580.0, by: 20.0).map { $0 }
        var frames: [Raster] = []
        for ms in times { frames.append(try rasterise(frame(atMs: ms), scale: 1)) }
        #expect(Set(frames.map { "\($0.width)x\($0.height)" }).count == 1,
                "the frames are not all one size, so the GIF's motion is a layout artefact: \(Set(frames.map { "\($0.width)x\($0.height)" }))")
        #expect(writeAnimatedGIF(frames, secondsPerFrame: 0.03, to: path),
                "could not write \(path)")

        // ── Measured off those very rasters, band by band. ──
        let top = 6 + 14                              // padding + the label row
        let boneGreen = Int((boneColour.g * 255).rounded())
        /// Per band: the silhouette's painted width, the bar's painted width, and
        /// the bar's own alpha recovered from its rendered colour.
        ///
        /// **The green channel, not brightness or neutrality.** The first draft
        /// identified the bar by near-neutrality and it read `barColumns ==
        /// columns` at every frame: `IslandShape`'s antialiased top and bottom
        /// fringe is the tint at a few percent over `--void`, which *is* near-grey
        /// and *is* brighter than `--void`, and it runs the whole width of the
        /// shape. A measurement that cannot tell a 0pt bar from a 273pt one is
        /// worth nothing, so the bar is recovered instead from the one channel
        /// where `--bone` (239) is far from all three band tints (orange 153, blue
        /// 157, grey 147) and the composite is linear in alpha:
        ///
        ///     rendered.g = alpha * bone.g + (1 - alpha) * tint.g
        ///
        /// Sampled on the bar's own middle row, where the thing underneath is
        /// known to be the band's own tint and nothing else.
        func measure(_ r: Raster, bandIndex i: Int) -> (columns: Int, barColumns: Int, alpha: Double) {
            let y0 = top + i * Int(bandHeight)
            let tint = bands[i].tint
            let t = (Int((tint.r * 255).rounded()), Int((tint.g * 255).rounded()),
                     Int((tint.b * 255).rounded()))
            // The tint is filled at 0.92 over --void, so the expected composite is
            // ~8% darker than the pure colour; tolerance 26 covers that and the
            // antialiased interior, and excludes `--bone`.
            let barRow = min(y0 + 14, r.height - 1)
            var first = -1, last = -1, barFirst = -1, barLast = -1
            var peakAlpha = 0.0
            for x in 0..<r.width {
                var sawTint = false
                for y in y0..<min(y0 + 30, r.height) {
                    let p = r[x, y]
                    guard p.a > 0 else { continue }
                    if abs(Int(p.r) - t.0) <= 26 && abs(Int(p.g) - t.1) <= 26
                        && abs(Int(p.b) - t.2) <= 26 { sawTint = true; break }
                }
                if sawTint { if first < 0 { first = x }; last = x }

                // The bar, on its own row. `--void` shows through only outside the
                // silhouette, where there is no bar either, so a pixel whose green
                // sits between the tint's and `--bone`'s is the composite.
                let p = r[x, barRow]
                guard p.a > 0 else { continue }
                let alpha = Double(Int(p.g) - t.1) / Double(boneGreen - t.1)
                if alpha >= 0.5 {
                    if barFirst < 0 { barFirst = x }
                    barLast = x
                    peakAlpha = max(peakAlpha, min(1, alpha))
                }
            }
            return (first < 0 ? 0 : last - first + 1,
                    barFirst < 0 ? 0 : barLast - barFirst + 1,
                    peakAlpha)
        }

        print("""

        ══════════════════════════════════════════════════════════════════════
        HOVER GIF — \(path)
        \(frames.count) frames, \(frames[0].width)x\(frames[0].height), 30ms each
        orange = prototype · blue = ours after Task 4 · grey = ours before Task 4
        ══════════════════════════════════════════════════════════════════════
        MEASURED OFF THE FRAMES. painted silhouette columns / --bone bar columns /
        recovered bar alpha, per band. Resting \(f(resting))pt, reveal \(f(travel))pt,
        so a settled silhouette is \(f(resting + travel))pt and anything wider is §9.1's overshoot.

          t(ms)      prototype                 ours AFTER               ours BEFORE
        """)
        var peaks = [0, 0, 0]
        for (n, ms) in times.enumerated() where n % 2 == 0 {
            var cells: [String] = []
            for i in 0..<3 {
                let m = measure(frames[n], bandIndex: i)
                peaks[i] = max(peaks[i], m.columns)
                cells.append("\(pad("\(m.columns)", 4))pt \(pad("\(m.barColumns)", 4))pt a=\(f(m.alpha, 2))")
            }
            print("  \(String(format: "%5.0f", ms))   \(cells.joined(separator: "   "))")
        }
        let settled = Int((resting + travel).rounded())
        print("""

          widest silhouette painted, over all \(frames.count) frames
            prototype    \(peaks[0])pt   (\(peaks[0] - settled)pt past its settled \(settled)pt)
            ours AFTER   \(peaks[1])pt   (\(peaks[1] - settled)pt past)
            ours BEFORE  \(peaks[2])pt   (\(peaks[2] - settled)pt past — §9.1's overshoot, absent)
        """)
        for i in 0..<3 {
            #expect(peaks[i] > 0, "band \(i) (\(bands[i].name)) painted nothing at all — the GIF above shows an empty stage and its numbers are meaningless")
        }
        #expect(peaks[2] <= settled,
                "the pre-Task-4 band painted \(peaks[2])pt, past its settled \(settled)pt — --ease cannot overshoot, so this measurement is picking up something other than the silhouette and the comparison is invalid")
        #expect(peaks[1] > settled,
                "ours-after painted at most \(peaks[1])pt against a settled \(settled)pt — the hover's shape clock is not overshooting in the rendered frames")
    }

    // MARK: - 2. Expand / collapse

    @Test(.enabled(if: Self.on))
    @MainActor func expandCurves() {
        let g = IslandGeometry(screen: IslandGoldenTests.mbp14)
        let m = IslandModel(geometry: g, motion: MotionPreference(chosen: .full, systemWantsReduced: false))
        m.state = .waiting
        m.sessionCount = 3
        m.sessions = []
        let collapsed = m.frames.body.width
        m.drawerOpen = true
        let openW = m.drawerWidth

        print("""

        ══════════════════════════════════════════════════════════════════════
        EXPAND (click → drawer) — what animates, and on which curve
        ══════════════════════════════════════════════════════════════════════
        prototype
          .island   width         273→560px   440ms  cubic-bezier(.32,1.5,.5,1)
          .island   transform     translateX((r-LW)/2) → 0   440ms  same curve (recentres)
          .island   border-radius 15px → 20px   440ms  cubic-bezier(.22,.9,.28,1)
          .drawer   height        0 → 420px    470ms  cubic-bezier(.34,1.22,.5,1)   [calc(--t-shape + 30ms)]
          .face     opacity/translateY(4px)/blur(3px)  190ms  --ease  [--t-face]
        ours (width re-measured after Task 1; curve identified by Task 2)
          silhouette width        \(f(collapsed)) → \(f(openW))pt   — §9.1 WIDTH spring
                                  (response .42 / damping \(f(IslandMotion.widthDamping, 2))), keyed to
                                  IslandBody.restingWidth, which moves on the click
                                  only because Task 1 made it tier-aware
          silhouette x-offset     fixed (left edge pinned by IslandGeometry.frames) —
                                  the prototype recentres instead, §5.3 says we do not
          bottom radius           15pt → 20pt   440ms  --ease  (Task 5:
                                  IslandTier.bottomRadius / IslandMotion.shapeDuration;
                                  the interpolation is masked — see IslandView's own
                                  note on `.animation(radiusMorph,`)
          drawer height           0 → 420pt   spring(response \(f(IslandMotion.heightResponse, 2)), damping .80)
                                  — \(f(IslandMotion.heightLag * 1000, 0))ms longer than the width's, Task 5
          face crossfade          190ms / 5pt rise / 3pt blur (FaceCrossfade) — matches
        """)

        // `heightResponse` since Task 5: 470ms against the width's 440, which is
        // the lag this table is now comparing rather than assuming away.
        let spring = Spring(response: IslandMotion.heightResponse,
                            dampingRatio: IslandMotion.heightDamping)
        print("""

          DRAWER HEIGHT
          t(ms)   prototype (470ms / spring-h)   ours spring(\(f(IslandMotion.heightResponse, 2))/.80)   Δ      proto pt   ours pt
        """)
        var worstH = (dev: 0.0, ms: 0.0, p: 0.0, o: 0.0)
        for step in 0...240 {
            let ms = Double(step) * 5
            let p = css(0.34, 1.22, 0.5, 1, duration: 0.470, atMs: ms)
            let o = spring.value(target: 1.0, time: ms / 1000)
            if abs(p - o) > worstH.dev { worstH = (abs(p - o), ms, p, o) }
        }
        for ms in stride(from: 0.0, through: 600.0, by: 50.0) {
            let p = css(0.34, 1.22, 0.5, 1, duration: 0.470, atMs: ms)
            let o = spring.value(target: 1.0, time: ms / 1000)
            print("  \(String(format: "%5.0f", ms))          \(pct(p))                  \(pct(o))       \(pct(p - o))   \(f(p * 420))    \(f(o * 420))")
        }
        // Task 5's lag, measured as the thing it is about: when each axis first
        // gets within 0.5% of its target, width against height. Two springs
        // sharing one response arrive together; that is what the +30ms removes.
        func settling(_ damping: Double, response: Double) -> Double {
            let s = Spring(response: response, dampingRatio: damping)
            for step in 1...800 {
                let ms = Double(step) * 2
                if abs(s.value(target: 1.0, time: ms / 1000) - 1) < 0.005 { return ms }
            }
            return .nan
        }
        let settle = settling(IslandMotion.heightDamping, response: IslandMotion.heightResponse)
        let widthSettle = settling(IslandMotion.widthDamping, response: IslandMotion.response)
        let sharedSettle = settling(IslandMotion.heightDamping, response: IslandMotion.response)
        print("""
          worst Δ \(pct(worstH.dev)) at \(Int(worstH.ms))ms (proto \(pct(worstH.p)) / ours \(pct(worstH.o)))
          prototype lands exactly at 470ms; ours within 0.5% at \(settle.isNaN ? "never <2s" : "\(Int(settle))ms")

          THE 30ms LAG (Task 5) — first sample within 0.5% of target
            width   spring(\(f(IslandMotion.response, 2))/\(f(IslandMotion.widthDamping, 2)))  \(Int(widthSettle))ms
            height  spring(\(f(IslandMotion.heightResponse, 2))/\(f(IslandMotion.heightDamping, 2)))  \(Int(settle))ms   → the body lands \(Int(settle - widthSettle))ms after the width
            height on the SHARED response (before Task 5)  \(Int(sharedSettle))ms
            prototype: 440ms / 470ms, a \(Int(IslandMotion.heightLag * 1000))ms lag written as calc(--t-shape + 30ms)

          WIDTH: the prototype travels 287pt over 440ms on an overshooting curve.
          Ours travelled 0pt when this probe was written. Since Plan 6.3 Task 1 it
          travels \(f(openW - collapsed))pt — 423.1 → \(f(openW)) from the hovered start a click
          actually happens in. **Task 2's answer: the §9.1 width spring carries it.**
        """)

        let wSpring = Spring(response: IslandMotion.response,
                             dampingRatio: IslandMotion.widthDamping)
        let from = 423.1
        var lowest = openW, highest = from, peakMs = 0.0
        for step in 0...500 {
            let ms = Double(step) * 2
            let w = from + (openW - from) * wSpring.value(target: 1.0, time: ms / 1000)
            lowest = min(lowest, w)
            if w > highest { highest = w; peakMs = ms }
        }
        print("""

          DOES THE WIDTH EVER MOVE BACKWARDS?  423.1 → \(f(openW)) on spring(.42/\(f(IslandMotion.widthDamping, 2)))
            lowest sample  \(f(lowest, 2))pt   (start \(f(from, 2))pt — a dip would be below it)
            peak           \(f(highest, 2))pt at \(Int(peakMs))ms  (+\(f(highest - openW, 2))pt past target,
                           = \(f((highest - openW) / (openW - from) * 100, 1))% of travel — §9.1's overshoot, forwards)
            so: no dip. The only backwards motion in the whole morph is the
            settle from the overshoot peak back down to \(f(openW)), which is the
            rule §9.1 asks for rather than a defect. On CLOSE the same curve
            undershoots symmetrically — down to \(f(from - (highest - openW), 2))pt, \(f(highest - openW, 2))pt past 423.1 —
            and back up. Also §9.1, in the other direction.
        """)
    }

    // MARK: - 3. Rendered width at 1 / 3 / 12 sessions

    @Test(.enabled(if: Self.on))
    @MainActor func openWidths() throws {
        print("""

        ══════════════════════════════════════════════════════════════════════
        THE OPEN PANEL'S WIDTH — measured, mbp14 (notch 185pt)
        ══════════════════════════════════════════════════════════════════════
        sessions  count text  collapsed  hovered  drawerWidth  painted cols  panel  prototype
        """)
        let g = IslandGeometry(screen: IslandGoldenTests.mbp14)
        for n in [1, 3, 12] {
            let m = IslandModel(geometry: g,
                                motion: MotionPreference(chosen: .full, systemWantsReduced: false))
            m.state = .waiting
            m.sessionCount = n
            m.sessions = MotionFidelityProbe.sessions(n)
            let collapsed = m.frames.body.width
            m.hovering = true
            let hovered = m.frames.body.width
            m.hovering = false
            m.drawerOpen = true
            let dw = m.drawerWidth
            let panel = m.panelFrames.panel.width
            let text = m.layout.sessionCountText ?? "-"

            // Painted extent, off the render, with the drawer open.
            let raster = try rasterise(IslandView(model: m), scale: 1)
            let cols = IslandGoldenTests.paintedColumns(raster)
            let colText = cols.map { "\($0.count)" } ?? "none"

            print("  \(String(format: "%8d", n))  \(pad(text, 6))  \(f(collapsed))    \(f(hovered))   \(f(dw))       \(colText)          \(f(panel))  560")
        }
        print("""

          DrawerFace.sessionList.height = \(f(DrawerFace.sessionList.height))pt for every count
          (§6.3). Prototype: .island[data-state="list"] .drawer{height:420px} — same.
          Width used to be where they part: it was a function of how many DIGITS the
          tally had, so 1 and 3 sessions were byte-identical (273.1) and only n>=10
          moved it 8pt. Plan 6.3 Task 1 made it DrawerFace.width — flat, and the
          `drawerWidth`/`painted cols` columns above should now read 560 at every
          count. The `collapsed`/`hovered` columns are the closed island and still
          move with the tally, correctly.
        """)
    }

    static func sessions(_ n: Int) -> [Session] {
        (0..<n).map { i in
            var e = VibeEvent(id: "probe-\(i)", cli: "claude-code",
                              kind: i == 0 ? .permission : .running,
                              session: "s\(i)", cwd: "/Users/dev/project-\(i)")
            e.model = "Opus 4.8"
            e.title = "Asking to run"
            e.body = "rm -rf build/"
            return Session(event: e, now: Date())
        }
    }

    // MARK: - 3b. Which way the width moves on a click

    /// The click that opens the drawer always happens *while hovering* (the panel
    /// only takes clicks when `model.hovering`), so this is the ordinary case, not
    /// an edge. Painted extent of the collapsed bar alone — rows above the notch
    /// line — for the four combinations.
    @Test(.enabled(if: Self.on))
    @MainActor func widthDirectionOnClick() throws {
        func barColumns(_ hovering: Bool, _ open: Bool) throws -> (bar: Int, all: Int) {
            let g = IslandGeometry(screen: IslandGoldenTests.mbp14)
            let m = IslandModel(geometry: g,
                                motion: MotionPreference(chosen: .full, systemWantsReduced: false))
            m.state = .waiting
            m.sessionCount = 3
            m.sessions = Self.sessions(3)
            m.hovering = hovering
            m.drawerOpen = open
            let r = try rasterise(IslandView(model: m), scale: 1)
            let notchH = Int(g.notch.height.rounded())
            var first = -1, last = -1
            for x in 0..<r.width {
                let painted = (0..<min(notchH, r.height)).contains { !r[x, $0].isTransparent }
                if painted { if first < 0 { first = x }; last = x }
            }
            let all = IslandGoldenTests.paintedColumns(r)?.count ?? 0
            return (first < 0 ? 0 : last - first + 1, all)
        }
        print("""

        ══════════════════════════════════════════════════════════════════════
        WHICH WAY THE WIDTH MOVES ON A CLICK  (painted columns, mbp14 / 3 sessions)
        ══════════════════════════════════════════════════════════════════════
        hover  drawer   collapsed bar   whole render
        """)
        for (h, o) in [(false, false), (true, false), (false, true), (true, true)] {
            let c = try barColumns(h, o)
            print("  \(h ? "on " : "off")    \(o ? "open  " : "closed")   \(pad("\(c.bar)", 8))        \(pad("\(c.all)", 6))")
        }
        print("""

          prototype, same gesture: 273 → 560 (grows, and recentres).
        """)
    }

    // MARK: - 3c. Does 420pt fit the content?

    /// §6.3 fixes the list face at 420pt with rows scrolling. This measures how
    /// much content there actually is at 1 / 3 / 12 sessions, at our production
    /// width and at the prototype's 560, so "too tall with few / fold cuts a row
    /// with many" becomes numbers.
    @Test(.enabled(if: Self.on))
    @MainActor func listContentHeights() throws {
        print("""

        ══════════════════════════════════════════════════════════════════════
        DOES 420pt FIT?  unconstrained content height of the rows
        ══════════════════════════════════════════════════════════════════════
        sessions   at 273pt (ours)   at 388pt   at 560pt (mockup)   face 420 / usable 376
        """)
        for n in [1, 3, 12] {
            var out: [String] = []
            for w in [273.1, 388.0, 560.0] {
                let rows = VStack(alignment: .leading, spacing: 1) {
                    ForEach(Self.sessions(n)) { s in SessionRow(session: s, now: Date()) }
                }
                .padding(.top, 2)
                .padding(.horizontal, QuestionFace.leadingPadding)
                .frame(width: w)
                let r = try rasterise(rows, scale: 1)
                out.append(pad("\(r.height)", 6))
            }
            print("  \(pad("\(n)", 8))   \(out[0])            \(out[1])     \(out[2])")
        }
        print("""

          usable = 420 − §6.4's footer reservation (≈44pt) = 376pt.
          Prototype: .island[data-state="list"] .drawer{height:420px} at width 560px.
        """)
    }

    // MARK: - 3b. The two corners, magnified (Plan 6.3 Task 5)

    /// Writes the collapsed and open bottom-right corners side by side at 8×, so the
    /// 15 → 20 difference is something an eye can check rather than a number.
    ///
    ///     VIBECAT_MOTION_PROBE=1 VIBECAT_RADIUS_SHEET=/tmp/radii.png \
    ///         swift test --filter cornerSheet
    ///
    /// Nothing is asserted here — `theOpenIslandsBottomCornerIsThePrototypes20ptAnd
    /// TheCollapsedOneIsStill15` in `IslandShapeTests` is the assertion, and it reads
    /// the same two renders.
    @Test(.enabled(if: Self.on))
    @MainActor func cornerSheet() throws {
        guard let path = ProcessInfo.processInfo.environment["VIBECAT_RADIUS_SHEET"] else {
            print("\n  (set VIBECAT_RADIUS_SHEET=/tmp/radii.png for the visual)")
            return
        }
        let magnify: CGFloat = 8
        // 28, not 34: the collapsed body is only `notch.height` (32pt) tall, so a
        // crop taller than that runs off the top of the raster.
        let crop = 28     // points of corner to keep
        var tiles: [Raster] = []
        for open in [false, true] {
            let m = IslandModel(geometry: IslandGeometry(screen: IslandGoldenTests.mbp14),
                                motion: MotionPreference(chosen: .full, systemWantsReduced: false))
            m.state = .waiting
            m.sessionCount = 0
            if open {
                m.question = QuestionModel(event: VibeEvent(
                    id: "q", cli: "claude-code", kind: .permission, session: "s",
                    cwd: "/tmp/proj", title: "Bash command", body: "pnpm install",
                    choices: [Choice(id: "allow", label: "Allow once")], wantsReply: true))
                m.drawerOpen = true
            }
            let full = try rasterise(IslandView(model: m), scale: magnify)
            let inPanel = IslandFrames(body: m.frames.body,
                                       panel: m.panelFrames.panel).bodyInPanel
            let side = Int(CGFloat(crop) * magnify)
            let x0 = Int((inPanel.maxX * magnify).rounded()) - side
            let y0 = Int((inPanel.maxY * magnify).rounded()) - side
            var bytes = [UInt8](repeating: 0, count: side * side * 4)
            for y in 0..<side {
                for x in 0..<side {
                    let p = full[x0 + x, y0 + y]
                    let i = (y * side + x) * 4
                    bytes[i] = p.r; bytes[i + 1] = p.g; bytes[i + 2] = p.b; bytes[i + 3] = p.a
                }
            }
            tiles.append(Raster(width: side, height: side, bytes: bytes))
        }
        // Two tiles side by side, a 16px gutter between.
        let gutter = 16
        let w = tiles[0].width * 2 + gutter, h = tiles[0].height
        var sheet = [UInt8](repeating: 0, count: w * h * 4)
        for (i, tile) in tiles.enumerated() {
            let dx = i * (tile.width + gutter)
            for y in 0..<tile.height {
                for x in 0..<tile.width {
                    let p = tile[x, y]
                    let o = (y * w + dx + x) * 4
                    sheet[o] = p.r; sheet[o + 1] = p.g; sheet[o + 2] = p.b; sheet[o + 3] = p.a
                }
            }
        }
        let ok = Raster(width: w, height: h, bytes: sheet).writePNG(to: path)
        print("""

          CORNERS AT \(Int(magnify))× — left: collapsed (\(f(IslandGeometry.bottomRadius))pt) ·
          right: open (\(f(IslandGeometry.openBottomRadius))pt)
          \(ok ? "wrote" : "FAILED to write") \(path)  \(w)×\(h)
        """)
    }

    // MARK: - 4. The two curves as motion

    @Test(.enabled(if: Self.on))
    @MainActor func morphStrip() throws {
        let stripPath = ProcessInfo.processInfo.environment["VIBECAT_MOTION_STRIP"]
        let gifPath = ProcessInfo.processInfo.environment["VIBECAT_MOTION_GIF"]
        guard stripPath != nil || gifPath != nil else {
            print("\n  (set VIBECAT_MOTION_STRIP / VIBECAT_MOTION_GIF for the visual)")
            return
        }

        // Measured numbers, not invented ones. mbp14 / 3 sessions:
        //   collapsed 273.1 · hovered 423.1 · open 560 (DrawerFace.width).
        // The click always happens while hovering, so 423.1 is where ours starts.
        let hovered = 423.1, resting = 273.1, protoTo = 560.0
        let ourTo = DrawerFace.sessionList.width
        let notchMid: CGFloat = 300          // stage centre
        let leftEdge = notchMid - 185 / 2 - 58   // notch.minX − LW, the pinned edge

        @MainActor func frame(atMs ms: Double) -> some View {
            let pw = css(0.32, 1.5, 0.5, 1, duration: 0.440, atMs: ms)
            let ph = css(0.34, 1.22, 0.5, 1, duration: 0.470, atMs: ms)
            // `heightResponse`, not `response`, since Plan 6.3 Task 5 gave the
            // drawer's height the prototype's own +30ms.
            let ourH = Spring(response: IslandMotion.heightResponse,
                              dampingRatio: IslandMotion.heightDamping)
                .value(target: 1.0, time: ms / 1000)
            let ourWp = Spring(response: IslandMotion.response,
                               dampingRatio: IslandMotion.widthDamping)
                .value(target: 1.0, time: ms / 1000)
            // Prototype: 273 → 560 on --spring-w, recentred on the notch.
            let protoW = resting + (protoTo - resting) * pw
            // Ours: 423.1 → 560 (the reveal is dropped and the face's own width
            // takes over), left edge pinned — §5.3, we do not recentre. On the
            // §9.1 WIDTH spring, keyed to `IslandBody.restingWidth`, which Plan
            // 6.3 Task 1 made tier-aware and Task 2 confirmed is the key that
            // moves on the click. This line used to read `hovered + (resting -
            // hovered) * ourH` — 423 → 273 on the height spring — which was the
            // defect and the best guess available before Task 2 measured it.
            let ourW = hovered + (ourTo - hovered) * ourWp
            return VStack(alignment: .leading, spacing: 6) {
                Text("\(Int(ms))ms").font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color(hazeColour))
                ZStack(alignment: .topLeading) {
                    // Wide/tall enough to dominate the ZStack at every sample,
                    // including both curves' overshoot. `.offset` does not affect
                    // layout but `.frame(width:)` does, so a stage the shapes can
                    // outgrow would give the GIF frames of differing sizes.
                    Color.clear.frame(width: 820, height: 190)
                    IslandShape().fill(Color(RGBA(hex: "#FFA63C")!).opacity(0.9))
                        .frame(width: protoW, height: 32 + 388 * ph / 3)
                        .offset(x: notchMid - protoW / 2)
                }
                ZStack(alignment: .topLeading) {
                    // Wide/tall enough to dominate the ZStack at every sample,
                    // including both curves' overshoot. `.offset` does not affect
                    // layout but `.frame(width:)` does, so a stage the shapes can
                    // outgrow would give the GIF frames of differing sizes.
                    Color.clear.frame(width: 820, height: 190)
                    IslandShape().fill(Color(RGBA(hex: "#5B9DF9")!).opacity(0.9))
                        .frame(width: ourW, height: 32 + 388 * ourH / 3)
                        .offset(x: leftEdge)
                }
            }
            .padding(6)
            .background(Color(islandGroundColour))
        }

        let times = stride(from: 0.0, through: 560.0, by: 40.0).map { $0 }
        if let gifPath {
            var frames: [Raster] = []
            for ms in times { frames.append(try rasterise(frame(atMs: ms), scale: 1)) }
            _ = writeAnimatedGIF(frames, secondsPerFrame: 0.04, to: gifPath)
            print("  morph gif -> \(gifPath)  (\(frames.count) frames; orange = prototype, blue = ours)")
        }
        if let stripPath {
            let strip = HStack(alignment: .top, spacing: 2) {
                ForEach(times, id: \.self) { ms in frame(atMs: ms) }
            }
            .background(Color.black)
            let r = try rasterise(strip, scale: 1)
            _ = r.writePNG(to: stripPath)
            print("  morph filmstrip -> \(stripPath)  \(r.width)x\(r.height)")
        }
    }
}
