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
        case .zzz:     MotionProfile(framesPerSecond: 8, cycle: 3.0, isContinuous: true)
        case .squares: MotionProfile(framesPerSecond: 12, cycle: 1.0, isContinuous: true)
        case .bang:    MotionProfile(framesPerSecond: 12, cycle: 1.1, isContinuous: true)
        case .star:    MotionProfile(framesPerSecond: 0, cycle: 2.2, isContinuous: false)
        case .cross:   MotionProfile(framesPerSecond: 0, cycle: 0.6, isContinuous: false)
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
            // Two z's drifting up, the small one leading. Its rise is the phase.
            let lift = Int((phase * 3).rounded(.down))          // 0…2
            let smallRow = max(0, 2 - lift)
            let bigRow = min(Self.size - 3, 4 - lift)
            if bigRow >= 0 && bigRow + 2 < Self.size {
                g[bigRow][1] = true; g[bigRow][2] = true; g[bigRow][3] = true
                g[bigRow + 1][2] = true
                g[bigRow + 2][1] = true; g[bigRow + 2][2] = true; g[bigRow + 2][3] = true
            }
            if smallRow >= 0 && smallRow + 1 < Self.size {
                g[smallRow][5] = true; g[smallRow][6] = true
                g[smallRow + 1][5] = true; g[smallRow + 1][6] = true
            }

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
            set([".......",
                 "...#...",
                 "...#...",
                 ".#####.",
                 "...#...",
                 "...#...",
                 "......."])

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
