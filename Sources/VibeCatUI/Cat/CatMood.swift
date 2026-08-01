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

    private static func offset(_ mood: CatMood, phase: Double) -> Int {
        guard mood.motion.isContinuous else { return 0 }
        // A single-cell step, up for the first half of the cycle.
        return phase < 0.5 ? -1 : 0
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
            // §7.2. What distinguishes this mood is the mouth, not the eyes:
            // row 11's centre becomes a dark opening.
            g[11][8] = .pupil
            g[11][9] = .pupil
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
