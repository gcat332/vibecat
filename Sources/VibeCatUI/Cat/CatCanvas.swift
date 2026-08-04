import SwiftUI

/// Draws a resolved cat.
///
/// The spike found path batching makes no measurable difference — 20.3% batched
/// against 20.5% unbatched at the same rate, because the cost is per-frame
/// overhead and not the fills. So this draws the clear way: one rect per cell,
/// cells sharing a tone accumulated into that tone's own path so there is one
/// draw call per tone rather than one per cell. Grouping by tone is for fewer
/// colour switches, not for speed.
public struct CatCanvas: View {
    public let cat: ResolvedCat
    public let palette: CatPalette
    public let cellSize: CGFloat
    /// §9.3, and not defaulted — same reasoning as `BadgeCanvas.motion`.
    ///
    /// The badge-transform spike only named `BadgeCanvas`, but this view has the
    /// identical bypass and it was introduced by the same change (Plan 4.5 moved
    /// the cat's own motion onto a `.repeatForever` view transform here). Fixing
    /// one and not the other would leave the cat drowsing and swaying with
    /// motion off, which is both a §9.3 violation on its own and enough to keep
    /// paying what the spike measured as a *per-island* charge for animating at
    /// all — so a measurement of "off costs less than full" taken with this half
    /// unfixed would have been measuring nothing.
    public let motion: MotionPreference

    public init(cat: ResolvedCat, palette: CatPalette, cellSize: CGFloat,
                motion: MotionPreference) {
        self.cat = cat
        self.palette = palette
        self.cellSize = cellSize
        self.motion = motion
    }

    /// Every non-transparent cell's rect, grouped by tone, each tone's colour
    /// already looked up.
    ///
    /// Deliberately a plain property rather than logic inside `Canvas`'s
    /// renderer closure. That closure is `@escaping` and only runs when
    /// SwiftUI actually draws — verified empirically, a `Canvas` whose
    /// renderer flips a flag leaves it unset after merely accessing `body`.
    /// CanvasTests.swift's tests exist to walk every cell and look up every
    /// tone across every coat/mood/phase and catch a trap; if that walk
    /// lived inside the closure instead, evaluating `body` would exercise
    /// none of it and the tests would pass whether or not the walk was
    /// correct. Computing the plan here means `body` alone still does the
    /// whole walk, and the closure below is left with nothing but the fill
    /// calls.
    private var fillsByTone: [(Color, Path)] {
        guard cellSize > 0 else { return [] }
        var byTone: [Tone: Path] = [:]
        for (row, line) in cat.cells.enumerated() {
            for (col, tone) in line.enumerated() {
                guard let tone else { continue }
                // Integer boundaries — pixel art must land on the grid. The
                // sprite's *motion* is no longer part of this arithmetic: Plan
                // 4.5 moved it to a view transform below, so these rects are
                // the sprite at rest and nothing else.
                let rect = CGRect(x: (CGFloat(col) * cellSize).rounded(),
                                  y: (CGFloat(row) * cellSize).rounded(),
                                  width: cellSize, height: cellSize)
                byTone[tone, default: Path()].addRect(rect)
            }
        }
        return byTone.map { (Color(palette[$0.key]), $0.value) }
    }

    /// Flipped once on appear so the implicit animations have somewhere to go —
    /// the same mechanism `BadgeCanvas` uses, for the same reason, including its
    /// `onChange` companion for a Reduce Motion setting that can now change
    /// while the app runs.
    @State private var moving = false

    public var body: some View {
        let fills = fillsByTone
        // `nil` once §9.3 says nothing moves — see `MotionPreference
        // .allowsMotion`. The pose that remains is the sprite at rest: offset 0
        // and, for `happy`, scale 1 rather than `catpop`'s 0.6 starting frame,
        // which is the mockup's base style with `animation:none` applied and not
        // a shrunken cat frozen at the beginning of a pop it will never finish.
        let pulse = motion.allowsMotion ? cat.mood.pulse : nil
        let popping = motion.allowsMotion && cat.mood == .happy
        Canvas { ctx, _ in
            for (color, path) in fills {
                ctx.fill(path, with: .color(color))
            }
        }
        .frame(width: CGFloat(CatGrid.width) * cellSize,
               height: CGFloat(CatGrid.height) * cellSize)
        // The transform sits on the view, not inside the renderer, so the render
        // server runs it and no `TimelineView` tick is needed to move the cat.
        // `trot` keeps its timeline anyway for §7.2's blink, which is a cell
        // change; `call` no longer needs one to move at all.
        //
        // Half the period, reversing: the prototype's keyframes are
        // `0%,100%{rest} 50%{extreme}`, which is exactly an autoreversing
        // animation of half the cycle. `--ease` is `cubic-bezier(.22,.9,.28,1)`,
        // which `.easeInOut` approximates; matching the bezier exactly is the
        // open motion-curve item and is not settled by guessing here.
        .offset(x: moving ? (pulse?.sway ?? 0) : 0,
                y: moving ? (pulse?.rise ?? 0) : 0)
        .animation(pulse.map {
            .easeInOut(duration: $0.period / 2).repeatForever(autoreverses: true)
        }, value: moving)
        // §7.2's "one spring pop" for `happy`, the prototype's
        // `catpop 540ms var(--spring-w)`: `scale(.6) → 1.12 at 60% → 1`. A
        // spring that overshoots is the same figure with one parameter instead
        // of three keyframes, and unlike the repeating scales this one is
        // transient — so the blur measured in `CatMood.pulse` lasts 540ms and
        // then the grid is exact again, which is why this is the one scale we do
        // match.
        .scaleEffect(popping && !moving ? 0.6 : 1)
        .animation(popping ? .spring(response: 0.42, dampingFraction: 0.56) : nil,
                   value: moving)
        .onAppear { moving = motion.allowsMotion }
        .onChange(of: motion.allowsMotion) { _, allowed in moving = allowed }
    }
}
