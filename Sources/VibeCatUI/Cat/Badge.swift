import Foundation

/// The small animation beside the cat naming what it is doing. Design §8.
///
/// Every badge draws on the same 7×7 grid inside a fixed 14pt box. That box is
/// constant on purpose: a `zzz` is three times the width of a `!`, and without
/// a fixed slot the left flank resizes on every state change and walks the cat
/// sideways.
///
/// Monochrome by design — the view tints with the state accent, so the badge
/// carries state colour like everything else.
///
/// ## Two shape families, and the split means something
///
/// `check`, `cross` and `bang` share one silhouette, a filled disc, and are told
/// apart by the glyph punched out of it. `zzz` and `squares` stay loose marks.
///
/// That is not decoration. `idle`, `failed` and `waiting` are the three states
/// that have *concluded something* or *want you now* — a verdict. `dormant` and
/// `running` are ambient: the machine is doing what it was already doing. A
/// bounded disc reads as a verdict; an unbounded mark reads as activity. So the
/// family boundary carries information, and deliberately does not extend to the
/// other two.
public enum Badge: String, Sendable, CaseIterable {
    case zzz, squares, bang, check, cross

    public static let size = 7

    /// The disc every verdict badge is punched out of.
    ///
    /// Written as art rather than derived, because the arithmetic version —
    /// every cell but the four corners — rendered as a *squircle*, not a
    /// circle. Removing one cell per corner from a 7×7 grid leaves too much
    /// shoulder; at 14pt it read as a rounded rectangle. Taking three per
    /// corner is what makes the silhouette round at this size.
    ///
    /// Filled, not a ring: a one-cell ring would leave nothing inside to punch.
    /// The rows that narrow (0, 1, 5, 6) still leave rim on every side of every
    /// glyph cell below — checked by
    /// `theThreeVerdictBadgesShareADiscAndDifferOnlyInTheirGlyph`.
    private static let disc: [[Bool]] = [
        [false, false, true,  true,  true,  false, false],
        [false, true,  true,  true,  true,  true,  false],
        [true,  true,  true,  true,  true,  true,  true ],
        [true,  true,  true,  true,  true,  true,  true ],
        [true,  true,  true,  true,  true,  true,  true ],
        [false, true,  true,  true,  true,  true,  false],
        [false, false, true,  true,  true,  false, false],
    ]

    public init(state: IslandState) {
        switch state {
        case .dormant: self = .zzz
        case .running: self = .squares
        case .waiting: self = .bang
        case .idle:    self = .check
        case .failed:  self = .cross
        }
    }

    /// The prototype animates **all five** badges, and every one of them by
    /// `scale` and/or `opacity` rather than by changing which cells are lit —
    /// `zfloat 2.8s`, `twinkle 2.2s`, `quad 1.15s`, `softpulse 1.1s`,
    /// `shudder 2.4s`.
    ///
    /// That distinction is why `zzz`, `check` and `cross` can animate at all.
    /// `motion` below drives a `TimelineView`, which re-evaluates a `Canvas`
    /// N times a second — measured at 3.6–4.1% of a core for `zzz`, against
    /// 0.35% with no timeline, which is why all three were made still. A
    /// transform is a different mechanism: declared once with
    /// `.repeatForever()` and run by the render server, so it needs no
    /// timeline and leaves `needsTimeline` false. See `BadgeCanvas`.
    ///
    /// **Not yet measured.** The claim that a repeating `.scaleEffect` does not
    /// re-invoke the `Canvas` renderer is reasoned from how SwiftUI composites,
    /// not from `getrusage`. Measure before relying on it.
    public struct Pulse: Sendable, Equatable {
        public let period: Double
        public let scale: ClosedRange<Double>
        public let opacity: ClosedRange<Double>
        /// Points travelled upward across the cycle. Only `zzz` drifts.
        public let rise: Double
    }

    /// One independently-animated piece of a badge, and its delay.
    ///
    /// The mockup animates `zzz`'s two z's and `squares`' four blocks on
    /// *staggered* delays — 0/0.9s and 0/0.14/0.28/0.42s. A single `Canvas` has
    /// a single animation and cannot express that, which is why a badge is a
    /// list of parts rather than one mask.
    public struct Part: Sendable, Equatable {
        public let cells: [[Bool]]
        public let delay: Double
    }

    /// The transform every part of this badge travels through, from the mockup.
    ///
    /// **`check`, `cross` and `bang` share one pulse.** They share a silhouette,
    /// so giving them three different rates broke the family the disc exists to
    /// create — an earlier version did exactly that, and it was wrong. Urgency
    /// is carried by the cat's own motion and by colour, not by badge rate.
    public var pulse: Pulse {
        switch self {
        case .zzz:
            // zfloat: fades in from below, drifts up, fades out. Eleven points
            // of travel, +4 to −7 in the mockup's own units.
            Pulse(period: 2.8, scale: 0.8...1.05, opacity: 0.0...1.0, rise: 11)
        case .squares:
            // quad. Every block keeps one size — the keyframes are pure scale
            // and opacity — which is why the cells must stop resizing per frame.
            Pulse(period: 1.15, scale: 0.5...1.18, opacity: 0.28...1.0, rise: 0)
        case .check, .cross, .bang:
            // twinkle's numbers, for all three, because they are one family.
            Pulse(period: 2.2, scale: 0.62...1.0, opacity: 0.55...1.0, rise: 0)
        }
    }

    /// The pieces this badge animates, each on its own delay.
    public func parts(at phase: Double) -> [Part] {
        func mask(_ set: [(Int, Int)]) -> [[Bool]] {
            var g = [[Bool]](repeating: [Bool](repeating: false, count: Self.size),
                             count: Self.size)
            for (r, c) in set { g[r][c] = true }
            return g
        }
        switch self {
        case .zzz:
            // The mockup puts the leading z low and left with no delay, and the
            // second above and right, 0.9s behind — so they drift as a pair
            // rather than in lockstep.
            return [
                Part(cells: mask([(3, 0), (3, 1), (3, 2), (3, 3),
                                  (4, 2), (5, 1),
                                  (6, 0), (6, 1), (6, 2), (6, 3)]), delay: 0),
                Part(cells: mask([(0, 4), (0, 5), (0, 6),
                                  (1, 5),
                                  (2, 4), (2, 5), (2, 6)]), delay: 0.9),
            ]
        case .squares:
            // Four 2×2 blocks: 4px on a 2pt grid, with a one-cell gap, so
            // 2+1+2 centred in seven leaves a cell of margin — the mockup's own
            // 4px/2px/4px inside 14px. Clockwise from the top left, on the
            // mockup's delays: 0, .14 top right, .28 bottom right, .42 bottom
            // left.
            return [((1, 1), 0.0), ((1, 4), 0.14), ((4, 4), 0.28), ((4, 1), 0.42)]
                .map { origin, delay in
                    Part(cells: mask([(origin.0, origin.1), (origin.0, origin.1 + 1),
                                      (origin.0 + 1, origin.1), (origin.0 + 1, origin.1 + 1)]),
                         delay: delay)
                }
        case .check, .cross, .bang:
            return [Part(cells: cells(at: phase), delay: 0)]
        }
    }

    public var motion: MotionProfile {
        switch self {
        case .zzz:
            // Dormant is the state a machine sits in all day. Measured
            // properly (getrusage, not `ps %cpu`, which is too noisy at this
            // scale): the continuous drift cost 3.6–4.1% of a core, against
            // 0.35% with no timeline at all — for an animation that did not
            // read as one. The glyphs are an I-beam and a solid square,
            // there are only 3 distinct frames driven by 24 redraws a
            // second, and §8's "drift up and fade" was never given a fade.
            // The sleeping cat's shut eyes already say "dormant"; the badge
            // does not need to spend a core saying it again.
            .still
        // Every badge's motion is a transform now, so none needs a timeline.
        // Cycles are kept because `IslandBody` still derives a phase from them
        // and `bang`'s one-cell shift rides on it.
        case .squares: MotionProfile(framesPerSecond: 0, cycle: 1.15, isContinuous: false)
        case .bang:    MotionProfile(framesPerSecond: 0, cycle: 1.1, isContinuous: false)
        case .check:   MotionProfile(framesPerSecond: 0, cycle: 2.2, isContinuous: false)
        case .cross:   MotionProfile(framesPerSecond: 0, cycle: 2.4, isContinuous: false)
        }
    }

    /// Which cells of the disc are punched out, for a verdict badge.
    ///
    /// **The glyph is a hole, not a second colour.** `BadgeCanvas` fills only
    /// lit cells, so an unlit one shows the island through and the badge stays
    /// exactly one colour — the state's. Punching it white would make the badge
    /// two-tone against §4.3's "colour means state, and only state", and white
    /// is already spoken for by the cat's eyes and sparkle four points away. At
    /// two points a cell, a white glyph on saturated fill also blooms across
    /// subpixels where a dark hole stays crisp.
    ///
    /// **Colour cannot be what separates these three.** They now share an
    /// outline, and idle green against failed red is the classic colour-vision
    /// failure pair — this project has already shipped a `+` and a `×` that
    /// differed by hue alone. So each glyph carries a *structural* signature
    /// that survives being desaturated, and BadgeTests.swift asserts all three:
    ///
    /// - `check` — centre cell **lit**, and mirror-asymmetric
    /// - `cross` — centre cell holed, symmetric under both mirrors
    /// - `bang`  — every holed cell in a single column
    private func holes(at phase: Double) -> [(Int, Int)] {
        switch self {
        case .check:
            // A short left arm and a long right one. A symmetric V would read
            // as a V, and — worse — would be a mirror image of itself, leaving
            // nothing for a desaturated eye or a test to tell it from `cross`.
            //
            // The same 3×3 footprint as `cross` — rows 2–4, columns 2–4 —
            // after two larger versions. The first reached rows 2–5 and columns
            // 1–5 and read as a slash across the disc; the second was still
            // five columns wide and so visibly outweighed `cross` beside it.
            //
            // The right arm rises *vertically* rather than diagonally, which is
            // what buys the asymmetry inside three columns: a purely diagonal
            // tick this small is a symmetric V, and mirror-asymmetry is the
            // whole discriminator against `cross`.
            return [(3, 2), (4, 3), (3, 4), (2, 4)]
        case .cross:
            // Three by three, and **this is the largest an X fits.** Both of its
            // diagonals through the centre run out to (1,1)/(1,5)/(5,1)/(5,5),
            // and those four cells are the disc's own shoulders — rows 1 and 5
            // are only five wide. Punching them would open the silhouette at
            // the corners and it would read as a bitten circle, not a circle
            // with a mark in it. Growing this needs a bigger grid than §8's
            // fixed 14pt slot allows, or a less round disc.
            //
            // It carries the most cells of the three glyphs, which is what
            // gives it its weight.
            return [(2, 2), (2, 4), (3, 3), (4, 2), (4, 4)]
        case .bang:
            // §8 asks this badge to pulse, and it still does — but by *moving*
            // rather than by growing. The stem-lengthening version had to reach
            // row 1 at its tallest, spanning rows 1–5 and dominating the disc;
            // this keeps a constant two-cell stem, a one-cell gap and a dot,
            // four rows in all, and shifts the whole mark up a cell for half
            // the cycle. Whole cells, because a pixel grid cannot scale without
            // blurring the grid that drawing on one is for.
            let top = phase < 0.5 ? 2 : 1
            return [(top, 3), (top + 1, 3), (top + 3, 3)]
        case .zzz, .squares:
            return []
        }
    }

    public func cells(at phase: Double) -> [[Bool]] {
        var g = [[Bool]](repeating: [Bool](repeating: false, count: Self.size),
                         count: Self.size)
        func set(_ rows: [String]) {
            for (r, line) in rows.enumerated() where r < Self.size {
                for (c, ch) in line.enumerated() where c < Self.size {
                    g[r][c] = ch != "."
                }
            }
        }

        switch self {
        case .zzz:
            // Two z's, the small one leading up and to the right.
            //
            // A z needs four rows to show its diagonal. The previous big z was
            // three — `###`/`.#.`/`###` — whose middle stroke sits in the centre
            // column, which is exactly where an I's stem goes: a 3×3 z and a 3×3
            // I are the same nine cells. The small z was worse, a solid 2×2 block
            // with no glyph at all. Rendered, it read as an I-beam beside a
            // square; see ContactSheet.swift, which is how that was finally seen.
            //
            // The small z is three columns and so cannot escape the centred
            // diagonal — but it does not have to. The big z establishes what
            // these marks are, and the small one is read as another of the
            // same. Sharing no column with the big z keeps the two bars from
            // running together into one staircase.
            //
            // One frame, because `motion` makes this badge `.still` — `phase`
            // is deliberately unread here. The case comment there says why the
            // drift went, and restoring it means offsetting these rows again.
            set(["....###",
                 ".....#.",
                 "....###",
                 "####...",
                 "..#....",
                 ".#.....",
                 "####..."])

        case .squares:
            // The union of `parts(at:)`. The mockup never changes these blocks'
            // size — `quad`'s keyframes are pure scale and opacity — so the
            // earlier version that swelled one block per frame was reading as a
            // different animation altogether.
            for part in parts(at: phase) {
                for r in 0..<Self.size {
                    for c in 0..<Self.size where part.cells[r][c] { g[r][c] = true }
                }
            }

        case .check, .cross, .bang:
            g = Self.disc
            for (r, c) in holes(at: phase) { g[r][c] = false }
        }
        return g
    }
}
