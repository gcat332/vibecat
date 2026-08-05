import Foundation
import SwiftUI
import Testing
@testable import VibeCatUI

/// Plan 4.5's motion-curve item, turned from "compare with an eye" into numbers.
///
/// The prototype animates the island's width and the drawer's height with
/// explicit cubic-beziers over `--t-shape: 440ms`:
///
/// ```css
/// --spring-w: cubic-bezier(.32,1.5,.5,1);   /* width  — that 1.5 is real overshoot */
/// --spring-h: cubic-bezier(.34,1.22,.5,1);  /* height — less of it */
/// ```
///
/// We use SwiftUI springs: `response 0.42 / damping 0.72` for width and
/// `0.42 / 0.78` for height (§9.1). The plan file's own note is that "a spring
/// settles asymptotically where a bezier lands exactly, so this is where the feel
/// diverges most and it will not be settled by matching numbers."
///
/// That is true about *choosing*, and it is not a reason to leave the size of the
/// difference unknown. `Spring` (macOS 14+, which is this package's floor) can be
/// evaluated directly, and a cubic-bezier is four control points, so both curves
/// can be sampled and subtracted. This is env-gated and asserts nothing, like
/// every other preview tool in this suite:
///
/// ```bash
/// VIBECAT_MOTION_CURVES=1 swift test --filter motionCurveComparison
/// ```
@Suite("Motion curves")
struct MotionCurveComparison {
    /// A CSS cubic-bezier's y at a given x, by bisection on x. CSS beziers are
    /// parameterised by t and read by x, so getting y at a *time* means solving
    /// for t first — the same thing a browser does.
    static func bezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, atX x: Double) -> Double {
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

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAT_MOTION_CURVES"] != nil))
    func motionCurveComparison() {
        let shape = 0.440   // --t-shape
        struct Case { let name: String, x1: Double, y1: Double, x2: Double, y2: Double, damping: Double }
        let cases = [
            Case(name: "width  --spring-w vs 0.42/0.72", x1: 0.32, y1: 1.5, x2: 0.5, y2: 1, damping: 0.72),
            Case(name: "height --spring-h vs 0.42/0.78", x1: 0.34, y1: 1.22, x2: 0.5, y2: 1, damping: 0.78),
        ]

        for c in cases {
            let spring = Spring(response: 0.42, dampingRatio: c.damping)
            var worst = (deviation: 0.0, atMs: 0.0, bezier: 0.0, spring: 0.0)
            var bezierPeak = (value: 0.0, atMs: 0.0)
            var springPeak = (value: 0.0, atMs: 0.0)
            var springSettleMs = Double.nan

            for step in 0...200 {
                let ms = Double(step) * 5              // 0…1000ms
                let t = ms / 1000
                // The bezier is done at --t-shape and holds 1 afterwards.
                let b = t >= shape ? 1.0 : Self.bezier(c.x1, c.y1, c.x2, c.y2, atX: t / shape)
                let s = spring.value(target: 1.0, time: t)

                if b > bezierPeak.value { bezierPeak = (b, ms) }
                if s > springPeak.value { springPeak = (s, ms) }
                if abs(b - s) > worst.deviation { worst = (abs(b - s), ms, b, s) }
                if springSettleMs.isNaN, ms > 0, abs(s - 1) < 0.005 { springSettleMs = ms }
            }

            print("""

            \(c.name)
              worst deviation      \(pct(worst.deviation)) at \(Int(worst.atMs))ms  (bezier \(pct(worst.bezier)) vs spring \(pct(worst.spring)))
              overshoot peak       bezier \(pct(bezierPeak.value)) at \(Int(bezierPeak.atMs))ms · spring \(pct(springPeak.value)) at \(Int(springPeak.atMs))ms
              bezier lands exactly \(Int(shape * 1000))ms · spring within 0.5% at \(springSettleMs.isNaN ? "never inside 1s" : "\(Int(springSettleMs))ms")
            """)
        }
    }

    /// Which `dampingFraction` reproduces the prototype's own overshoot.
    ///
    /// §9.1's stated *intent* is "width overshoots more than height, so the
    /// island reads as one body with mass". The comparison above shows the
    /// prototype honours that far more strongly than we do — 8.0% against 1.5%,
    /// a 5.3× ratio, where ours is 3.8% against 2.0%, only 1.9×. So the thing to
    /// match is not the curve shape (a spring cannot be a bezier) but the
    /// overshoot ratio, which is what carries the intent.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAT_MOTION_CURVES"] != nil))
    func dampingThatMatchesThePrototypesOvershoot() {
        func overshoot(_ damping: Double, response: Double = 0.42) -> Double {
            let spring = Spring(response: response, dampingRatio: damping)
            var peak = 0.0
            for step in 0...400 {
                peak = max(peak, spring.value(target: 1.0, time: Double(step) * 0.005))
            }
            return peak - 1
        }
        print("\n  damping → overshoot, at response 0.42")
        for d in stride(from: 0.50, through: 0.90, by: 0.02) {
            print("    \(String(format: "%.2f", d))  \(pct(overshoot(d)))")
        }
        print("""

          prototype targets: width 8.0% · height 1.5%
          ours today:        width 3.8% (0.72) · height 2.0% (0.78)
        """)
    }

    /// §9.1's rule, asserted for the first time: **"Width overshoots more than
    /// height, so the island reads as one body with mass rather than a resizing
    /// box."**
    ///
    /// It was true before Plan 4.5 and only barely — width overshot 3.8% against
    /// height's 2.0%, a ratio of 1.9×, where the prototype's own beziers give
    /// 8.0% against 1.5%, a ratio of 5.3×. A rule that holds by 1.8 percentage
    /// points is not carrying an intent about mass. The floor below is set from
    /// the prototype's ratio, so a future tuning pass that flattens the
    /// difference again fails here rather than passing on a technicality.
    @Test func widthOvershootsFarMoreThanHeightAsTheDesignRequires() {
        // Each half evaluated at its *own* response since Plan 6.3 Task 5 — the
        // drawer's is 30ms longer. Overshoot is a function of damping alone, so the
        // two figures are unchanged; reading the wrong response here would still
        // give the right answer, which is exactly why it is worth stating that this
        // is not the assertion protecting the lag.
        func overshoot(_ damping: Double, response: Double) -> Double {
            let spring = Spring(response: response, dampingRatio: damping)
            var peak = 0.0
            for step in 0...400 {
                peak = max(peak, spring.value(target: 1.0, time: Double(step) * 0.005))
            }
            return peak - 1
        }
        let width = overshoot(IslandMotion.widthDamping, response: IslandMotion.response)
        let height = overshoot(IslandMotion.heightDamping, response: IslandMotion.heightResponse)

        #expect(width > height,
                "§9.1 requires width to overshoot more than height; width \(pct(width)) against height \(pct(height))")
        #expect(width / height > 3,
                "width overshoots only \(String(format: "%.1f", width / height))x height (\(pct(width)) against \(pct(height))) — the prototype's own beziers give 5.3x, and at this ratio the island reads as a resizing box rather than one body with mass")
    }

    private func pct(_ v: Double) -> String { String(format: "%.1f%%", v * 100) }
}
