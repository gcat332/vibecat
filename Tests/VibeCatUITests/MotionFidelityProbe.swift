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
        ours (IslandView.swift:725)
          silhouette .frame width + RevealContent .frame width + .opacity
                                  280ms  .easeOut          — one modifier, all three
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
        ours
          silhouette width        \(f(collapsed)) → \(f(openW))pt   — NO CHANGE, nothing to animate
          silhouette x-offset     fixed (left edge pinned by IslandGeometry.frames)
          bottom radius           15pt, constant (IslandShape)
          drawer height           0 → 420pt   spring(response .42, damping .80)
          face crossfade          190ms / 5pt rise / 3pt blur (FaceCrossfade) — matches
        """)

        let spring = Spring(response: IslandMotion.response, dampingRatio: IslandMotion.heightDamping)
        print("""

          DRAWER HEIGHT
          t(ms)   prototype (470ms / spring-h)   ours spring(.42/.80)   Δ      proto pt   ours pt
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
        var settle = Double.nan
        for step in 1...400 {
            let ms = Double(step) * 5
            if abs(spring.value(target: 1.0, time: ms / 1000) - 1) < 0.005 { settle = ms; break }
        }
        print("""
          worst Δ \(pct(worstH.dev)) at \(Int(worstH.ms))ms (proto \(pct(worstH.p)) / ours \(pct(worstH.o)))
          prototype lands exactly at 470ms; ours within 0.5% at \(settle.isNaN ? "never <2s" : "\(Int(settle))ms")

          WIDTH: the prototype travels 287pt over 440ms on an overshooting curve.
          Ours travels 0pt. There is no curve to compare.
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
          Width is where they part: ours is a function of how many DIGITS the tally
          has, so 1 and 3 sessions are byte-identical and only n>=10 moves it 8pt.
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
        //   collapsed 273.1 · hovered 423.1 · prototype's list panel 560.
        // The click always happens while hovering, so 423.1 is where ours starts.
        let hovered = 423.1, resting = 273.1, protoTo = 560.0
        let notchMid: CGFloat = 300          // stage centre
        let leftEdge = notchMid - 185 / 2 - 58   // notch.minX − LW, the pinned edge

        @MainActor func frame(atMs ms: Double) -> some View {
            let pw = css(0.32, 1.5, 0.5, 1, duration: 0.440, atMs: ms)
            let ph = css(0.34, 1.22, 0.5, 1, duration: 0.470, atMs: ms)
            let ourH = Spring(response: IslandMotion.response,
                              dampingRatio: IslandMotion.heightDamping)
                .value(target: 1.0, time: ms / 1000)
            // Prototype: 273 → 560 on --spring-w, recentred on the notch.
            let protoW = resting + (protoTo - resting) * pw
            // Ours: 423 → 273 (the reveal is dropped), left edge pinned. Carried
            // on the drawer-height spring, because nothing keys a curve to it.
            let ourW = hovered + (resting - hovered) * ourH
            return VStack(alignment: .leading, spacing: 6) {
                Text("\(Int(ms))ms").font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color(hazeColour))
                ZStack(alignment: .topLeading) {
                    Color.clear.frame(width: 600, height: 130)
                    IslandShape().fill(Color(RGBA(hex: "#FFA63C")!).opacity(0.9))
                        .frame(width: protoW, height: 32 + 388 * ph / 3)
                        .offset(x: notchMid - protoW / 2)
                }
                ZStack(alignment: .topLeading) {
                    Color.clear.frame(width: 600, height: 130)
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
