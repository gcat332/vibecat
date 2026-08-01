import Foundation

/// How often a mood needs redrawing, and whether it needs redrawing at all.
///
/// `isContinuous == false` is not an optimisation — it is the whole mechanism
/// behind "an idle machine must not animate". Measured: a live TimelineView
/// costs ~6% of a core even at 8 fps; removing it costs 0.0%.
public struct MotionProfile: Sendable, Equatable {
    public let framesPerSecond: Double
    public let cycle: TimeInterval
    public let isContinuous: Bool

    public init(framesPerSecond: Double, cycle: TimeInterval, isContinuous: Bool) {
        self.framesPerSecond = framesPerSecond
        self.cycle = cycle
        self.isContinuous = isContinuous
    }

    public static let still = MotionProfile(framesPerSecond: 0, cycle: 0, isContinuous: false)
}

/// What the cat is doing. Design §7.2.
public enum CatMood: String, Sendable, CaseIterable {
    case sleep, trot, call, happy, dead

    public init(state: IslandState) {
        switch state {
        case .dormant: self = .sleep
        case .running: self = .trot
        case .waiting: self = .call
        case .idle:    self = .happy
        case .failed:  self = .dead
        }
    }

    /// Cycle lengths are the design's. Frame rates are the spike's: 12 fps for
    /// the two moods where something is actually happening, nothing at all for
    /// the three steady ones.
    public var motion: MotionProfile {
        switch self {
        case .trot:  MotionProfile(framesPerSecond: 12, cycle: 1.0, isContinuous: true)
        case .call:  MotionProfile(framesPerSecond: 12, cycle: 1.1, isContinuous: true)
        case .sleep: MotionProfile(framesPerSecond: 0, cycle: 3.0, isContinuous: false)
        case .dead:  MotionProfile(framesPerSecond: 0, cycle: 2.4, isContinuous: false)
        case .happy: .still
        }
    }
}

/// A coat and a mood resolved into the cells to draw at one phase.
///
/// Order matters and is §7.3's: the coat paints markings first, then the mood
/// paints the face over the top. The eyes always win.
public struct ResolvedCat: Sendable, Equatable {
    public let coat: Coat
    public let mood: CatMood
    /// 0…1 through the mood's cycle.
    public let phase: Double
    public let cells: [[Tone?]]
    /// Whole cells. Pixel art steps; a fractional offset would blur the grid.
    public let verticalOffset: Int

    public init(coat: Coat, mood: CatMood, phase: Double) {
        self.coat = coat
        self.mood = mood
        self.phase = phase
        var g = CatGrid(coat: coat).cells
        Self.applyFace(mood, phase: phase, to: &g)
        self.cells = g
        self.verticalOffset = Self.offset(mood, phase: phase)
    }

    /// Design §7.2 names two different motions — a "quick bob" for `trot` and
    /// an "attention pulse" for `call`. They used to be one shared step, up for
    /// the first half of the cycle, so the two moods differed by nothing but
    /// the mouth. The difference is rhythm, not amplitude: a step stays one
    /// cell, because two would carry the ear tips off the top of the canvas.
    private static func offset(_ mood: CatMood, phase: Double) -> Int {
        guard mood.motion.isContinuous else { return 0 }
        switch mood {
        case .trot:
            // Two beats per cycle: a walking rhythm rather than one slow rise.
            return phase.truncatingRemainder(dividingBy: 0.5) < 0.25 ? -1 : 0
        case .call:
            // One sharp hop, then stillness — a cat getting your attention,
            // not a cat walking. Up for a sixth of the cycle against trot's half.
            return phase < 0.16 ? -1 : 0
        case .sleep, .happy, .dead:
            // Unreachable behind the guard above; spelled out so adding a
            // continuous mood is a compile error rather than a silent zero.
            return 0
        }
    }

    /// Rows 7…9 are the eyes; row 10 columns 8…9 the nose, row 11 the mouth.
    private static func applyFace(_ mood: CatMood, phase: Double, to g: inout [[Tone?]]) {
        func setEyes(_ left: [Tone?], _ right: [Tone?], row: Int) {
            for (i, tone) in left.enumerated() { g[row][3 + i] = tone }
            for (i, tone) in right.enumerated() { g[row][12 + i] = tone }
        }

        switch mood {
        case .sleep:
            // Shut: a single dark line where the open eye's rows were.
            for row in 7...9 {
                let shut: [Tone?] = row == 8 ? [.pupil, .pupil, .pupil] : [.body, .body, .body]
                setEyes(shut, shut, row: row)
            }
        case .trot:
            // Open, with a rare blink — instantaneous, one frame near the end
            // of the cycle. The blink is the one thing in the interface that
            // does not ease, because a blink does not.
            if phase > 0.92 {
                for row in 7...9 {
                    let shut: [Tone?] = row == 8 ? [.pupil, .pupil, .pupil] : [.body, .body, .body]
                    setEyes(shut, shut, row: row)
                }
            }
        case .call:
            // Open — the same category as trot's resting eye, per design
            // §7.2. What distinguishes this mood is the mouth, not the eyes.
            //
            // Two cells tall, not one. Row 11 already carries the mouth line's
            // two outline cells at columns 7 and 10, so opening only row 11
            // widened an existing dark mark rather than making a new shape:
            // rendered, `call` and `trot` were two cells apart out of 210.
            // Carrying it into row 12 makes it a 2×2 opening — a mouth that is
            // open, which is the whole content of this mood.
            for row in 11...12 {
                g[row][8] = .pupil
                g[row][9] = .pupil
            }
        case .happy:
            // ^ ^ arcs.
            for row in 7...9 {
                let arc: [Tone?] = switch row {
                case 7: [.body, .pupil, .body]
                case 8: [.pupil, .body, .pupil]
                default: [.body, .body, .body]
                }
                setEyes(arc, arc, row: row)
            }
        case .dead:
            // X X.
            for row in 7...9 {
                let x: [Tone?] = switch row {
                case 7, 9: [.pupil, .body, .pupil]
                default:   [.body, .pupil, .body]
                }
                setEyes(x, x, row: row)
            }
        }
    }
}
