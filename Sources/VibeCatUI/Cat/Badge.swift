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
        case .squares: MotionProfile(framesPerSecond: 12, cycle: 1.0, isContinuous: true)
        case .bang:    MotionProfile(framesPerSecond: 12, cycle: 1.1, isContinuous: true)
        case .check:   MotionProfile(framesPerSecond: 0, cycle: 2.2, isContinuous: false)
        case .cross:   .still
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
            // Three rows, down from four. The first version reached rows 2–5
            // and read as a slash across the disc rather than a mark inside it.
            //
            // The flat two-cell elbow at the bottom is what keeps it legible at
            // this height. A purely diagonal four-cell version was tried and
            // rendered as a V: at three rows there is not enough difference
            // between a one-step left arm and a two-step right one for the
            // asymmetry to read, and the asymmetry is the whole discriminator
            // against `cross`. The elbow gives the eye a vertex to sit on.
            return [(3, 1), (4, 2), (4, 3), (3, 4), (2, 5)]
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
            // Four squares swelling in turn, clockwise. A pixel grid cannot
            // rotate cleanly — but it can take turns, and that reads as
            // rotation without anything actually rotating.
            let step = Int((phase * 4).rounded(.down)) % 4      // 0…3
            let origins = [(0, 0), (0, 4), (4, 4), (4, 0)]      // TL, TR, BR, BL
            for (i, o) in origins.enumerated() {
                let big = (i == step)
                let span = big ? 3 : 2
                let rowOffset = big ? 0 : (o.0 == 0 ? 0 : 1)
                let colOffset = big ? 0 : (o.1 == 0 ? 0 : 1)
                for r in 0..<span {
                    for c in 0..<span {
                        g[o.0 + rowOffset + r][o.1 + colOffset + c] = true
                    }
                }
            }

        case .check, .cross, .bang:
            g = Self.disc
            for (r, c) in holes(at: phase) { g[r][c] = false }
        }
        return g
    }
}
