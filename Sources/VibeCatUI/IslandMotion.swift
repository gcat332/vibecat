import Foundation

/// §9.1's two shape springs, in one place.
///
/// They were two inline literals ~350 lines apart in `IslandView`, which is how
/// the rule they exist to express went unchecked: §9.1 says **"Width overshoots
/// more than height, so the island reads as one body with mass rather than a
/// resizing box"**, and nothing anywhere asserted it.
///
/// ## Retuned 2026-08-03, Plan 4.5, against the prototype
///
/// The prototype animates both over `--t-shape: 440ms` with explicit beziers:
/// `--spring-w: cubic-bezier(.32,1.5,.5,1)` and
/// `--spring-h: cubic-bezier(.34,1.22,.5,1)`. Plan 4.5's own note was that this
/// "will not be settled by matching numbers", because a spring settles
/// asymptotically where a bezier lands exactly. That is true about the *curve
/// shape* and it is not a reason to leave the difference unmeasured.
///
/// Measured by evaluating both (`MotionCurveComparison`, env-gated):
///
/// | | prototype | ours, before | ours, now |
/// |---|---|---|---|
/// | width overshoot | **8.0%** | 3.8% (`0.72`) | **8.3%** (`0.62`) |
/// | height overshoot | **1.5%** | 2.0% (`0.78`) | **1.5%** (`0.80`) |
/// | width÷height ratio | **5.3×** | 1.9× | **5.5×** |
///
/// So the old values did not merely differ from the prototype — **they nearly
/// erased the rule §9.1 states.** Width overshot only 1.9× as much as height
/// where the prototype has 5.3×, which is the difference between "one body with
/// mass" and "a resizing box". The overshoot is what carries that intent, so
/// matching the overshoot is what matching the prototype means here; the bezier's
/// exact shape cannot be reproduced by any spring and is recorded as a
/// deliberate, permanent divergence.
///
/// What is still not matched, and is not a defect: the prototype's width curve is
/// at 65.6% of its travel by 75ms where ours is at 35.8% — the worst deviation
/// between the two curves is 29.8%, and it is all front-loading. A bezier can
/// leap; a spring accelerates. That difference is inherent to the two mechanisms.
enum IslandMotion {
    /// §9.1's `0.42`, unchanged, and close to the prototype's own 440ms.
    static let response: Double = 0.42
    /// Overshoots 8.3%, against the prototype's 8.0%. Was `0.72` (3.8%).
    static let widthDamping: Double = 0.62
    /// Overshoots 1.5%, matching the prototype exactly. Was `0.78` (2.0%).
    static let heightDamping: Double = 0.80
}
