import Foundation
import VibeCatCore

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
    ///
    /// **`trot` keeps its timeline after Plan 4.5 moved the bob to a transform**,
    /// and not by oversight: §7.2's "rare blink" is a *cell* change (`applyFace`
    /// shuts the eyes past phase 0.92), so something still has to redraw. `call`
    /// no longer needs one — its mouth is fixed and only the body moved — but the
    /// rate is left at 12 fps rather than tuned here, because that is Plan 8's
    /// job and this file is not where a frame rate should be decided twice.
    public var motion: MotionProfile {
        switch self {
        case .trot:  MotionProfile(framesPerSecond: 12, cycle: 1.0, isContinuous: true)
        case .call:  MotionProfile(framesPerSecond: 12, cycle: 1.1, isContinuous: true)
        case .sleep: MotionProfile(framesPerSecond: 0, cycle: 3.0, isContinuous: false)
        case .dead:  MotionProfile(framesPerSecond: 0, cycle: 2.4, isContinuous: false)
        case .happy: .still
        }
    }

    /// The repeating view-level transform this mood travels through, in points.
    ///
    /// `nil` means the sprite does not move at all. `period` is the **whole**
    /// cycle; `CatCanvas` halves it and reverses, which is exactly what the
    /// prototype's `0%,100% … 50%` keyframe shape means.
    ///
    /// ## Why these are translates when the prototype scales and rotates
    ///
    /// Measured 2026-08-03, `theCatsGridSurvivesATranslateButNotAScale`:
    /// rasterising this sprite through a translate leaves **9 distinct colours**
    /// at any offset, whole or fractional, at 1× and 2×. Through
    /// `.scaleEffect(1.09)` — the prototype's own `callout` value — it becomes
    /// **95 colours at 1×, 130 at 2×**. The 18×14 grid dissolves into blends.
    ///
    /// That settles a question `ResolvedCat.verticalOffset` used to assert
    /// without evidence ("a fractional offset would blur the grid"). **The
    /// opposite is true**: translation is exact and it is *scaling* that blurs. So
    /// the whole-cell rule was protecting against the wrong thing, and the
    /// prototype's `translateY` motions can be matched exactly while its `scale`
    /// and `rotate` ones cannot — not without either accepting a permanently soft
    /// sprite in the two states where the cat matters most, or drawing a second
    /// set of frames at the larger size.
    ///
    /// | mood | prototype | ours | why |
    /// |---|---|---|---|
    /// | `trot` | `translateY(-2px)` 1s | **matched exactly** | translate is exact |
    /// | `call` | `scale(1.09)` 1.1s | `-3pt` translate, 1.1s | scale blurs; larger than trot so §7.2's two motions stay tellable apart |
    /// | `dead` | `rotate(±4deg)` 2.4s | `±1pt` sway, 2.4s | rotate blurs worst of all; a sway still reads as §7.2's "slow wobble" |
    /// | `sleep` | `translateY(2px)` 3s | **matched exactly** | see the marginal-cost note below |
    /// | `happy` | `scale(.6→1.12→1)` 540ms | one-shot, see `CatCanvas` | transient, so its blur is transient too |
    ///
    /// ## Why `sleep` drowses after all, and why that needed a measurement
    ///
    /// Plan 3 made `sleep` still on a **measured** basis, and the measurement was
    /// honest: a continuously drifting sprite cost 3.6–4.1% of a core against
    /// 0.35% with no timeline. But it priced the *cell-swapping* mechanism, which
    /// needed a `TimelineView` tick per frame. A translate needs none.
    ///
    /// Measured 2026-08-03, adding the cat's `trot` transform to a `running`
    /// island that already had the `squares` badge animating: the within-run
    /// `running − dormant` delta moved from **+2.89pp to +3.64pp** — so a whole
    /// second continuous transform cost about **+0.75pp**, against roughly 10pp
    /// for the first one. **The cost is per-island, not per-animation**: it is a
    /// fixed charge for animating at all. Dormant already pays it for the `zzz`
    /// badge, so drowsing the cat there is ~0.8% rather than another 10%, and the
    /// prototype's `drowse` is a translate, so it stays exact.
    ///
    /// An earlier revision of this file left `sleep` still and said so, on the
    /// reasoning that dormant is the resting state and a second transform would
    /// change the 12% the owner accepted. That reasoning was sound and the number
    /// it assumed was wrong.
    public var pulse: Pulse? {
        switch self {
        case .sleep: Pulse(period: 3.0, rise: 2, sway: 0)
        case .trot:  Pulse(period: 1.0, rise: -2, sway: 0)
        case .call:  Pulse(period: 1.1, rise: -3, sway: 0)
        case .dead:  Pulse(period: 2.4, rise: 0, sway: 1)
        case .happy: nil
        }
    }

    /// One repeating transform, in points, as the prototype's keyframes express
    /// it: rest → extreme → rest.
    public struct Pulse: Sendable, Equatable {
        /// The whole cycle. `CatCanvas` animates half of it and reverses.
        public let period: Double
        /// Points travelled vertically at the extreme. Negative is up.
        public let rise: Double
        /// Points travelled horizontally at the extreme.
        public let sway: Double

        public init(period: Double, rise: Double, sway: Double) {
            self.period = period
            self.rise = rise
            self.sway = sway
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

    public init(coat: Coat, mood: CatMood, phase: Double) {
        self.coat = coat
        self.mood = mood
        self.phase = phase
        var g = CatGrid(coat: coat).cells
        Self.applyFace(mood, phase: phase, to: &g)
        self.cells = g
    }

    // `verticalOffset` and its `offset(_:phase:)` lived here until Plan 4.5.
    // They stepped the sprite by whole *cells* from inside the `Canvas`
    // renderer, on the reasoning that "pixel art steps; a fractional offset
    // would blur the grid" — which measurement contradicted (see
    // `CatMood.pulse`). Two consequences of doing it that way, both now gone:
    // the step could never exceed one cell, because rows above 0 do not exist
    // in an 18×14 grid, which is why `trot` ran at half the prototype's
    // amplitude; and because the offset was a function of `phase`, moving at
    // all required a `TimelineView` redraw. A view transform has neither
    // limit — the cat sits in a 14pt frame with ~9pt of headroom above it.

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
