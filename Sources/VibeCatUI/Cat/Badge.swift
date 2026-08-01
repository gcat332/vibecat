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
public enum Badge: String, Sendable, CaseIterable {
    case zzz, squares, bang, star, cross

    public static let size = 7

    public init(state: IslandState) {
        switch state {
        case .dormant: self = .zzz
        case .running: self = .squares
        case .waiting: self = .bang
        case .idle:    self = .star
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
        case .star:    MotionProfile(framesPerSecond: 0, cycle: 2.2, isContinuous: false)
        case .cross:   .still
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

        case .bang:
            // A pulse: the stem grows by a cell at the peak of the cycle.
            let tall = phase < 0.5
            let top = tall ? 0 : 1
            for r in top...4 { g[r][3] = true }
            g[6][3] = true

        case .star:
            // A four-pointed star with a body — a filled diamond, one row
            // wider on each side moving toward the middle, tapering back to
            // single-cell tips. Previously a plain `+`, indistinguishable
            // from `cross` (the same `+`, rotated 45°) except by hue — idle
            // green versus failed red, the classic colour-vision failure
            // pair, which defeated "colour means state" (design §4.3: that
            // only holds if shape carries it too). See
            // `starAndCrossAreNotJustRotationsOfEachOther` in BadgeTests.swift.
            set(["...#...",
                 "..###..",
                 ".#####.",
                 "#######",
                 ".#####.",
                 "..###..",
                 "...#..."])

        case .cross:
            set(["#.....#",
                 ".#...#.",
                 "..#.#..",
                 "...#...",
                 "..#.#..",
                 ".#...#.",
                 "#.....#"])
        }
        return g
    }
}
