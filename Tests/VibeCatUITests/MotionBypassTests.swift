import CoreGraphics
import Foundation
import SwiftUI
import Testing
import VibeCatCore
@testable import VibeCatUI

/// §9.3 reaching the pixels, and the three places it did not.
///
/// Plan 6.1 makes motion a preference a person can actually set, which is what
/// turns three latent bypasses into visible defects:
///
/// 1. `IslandBody.phase` read an arbitrary `Date()` and consulted
///    `MotionPreference` for nothing, so motion `off` posed the cat *randomly*
///    still rather than deliberately still — and `ResolvedCat.applyFace` shuts
///    `trot`'s eyes above phase 0.92, so roughly one launch in twelve gave a
///    running cat its eyes closed for as long as it ran.
/// 2. `MotionPreference.current()` was read once, in `NotchController.init`, so
///    toggling the system's Reduce Motion did nothing until relaunch.
/// 3. `BadgeCanvas` — and, unrecorded but identical, `CatCanvas` — never
///    consulted the preference at all, which the badge-transform spike measured
///    as motion `.off` plus system Reduce Motion changing the island's cost by
///    nothing (11.83% of a core against 12.26%).
///
/// **Everything here that is about a pose is asserted against a render**, not
/// against a property: `Canvas`'s renderer and a `TimelineView`'s content never
/// run during `.body` access, and this suite has three separate cases of a test
/// passing against a broken implementation for exactly that reason.

extension MotionPreference {
    /// §9.3 suppressing nothing — what every fixture in this suite implicitly
    /// had before `CatCanvas`/`BadgeCanvas` were made to take a preference at
    /// all. Named once rather than restated at fourteen call sites.
    static let fullMotion = MotionPreference(chosen: .full, systemWantsReduced: false)
    /// A user who chose `off`, with the system asking for nothing. Deliberately
    /// **not** `systemWantsReduced: true` as well: `effective` is `.off` either
    /// way (§9.3's override is one-directional), and pinning the weaker of the
    /// two inputs proves the preference is honoured on its own rather than
    /// riding on the system's coat-tails.
    static let noMotion = MotionPreference(chosen: .off, systemWantsReduced: false)
    static let reducedMotion = MotionPreference(chosen: .reduced, systemWantsReduced: false)
}

@Suite("Motion preference bypasses")
struct MotionBypassTests {
    static let mbp14 = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
        safeAreaTop: 32,
        auxLeft: CGRect(x: 0, y: 950, width: 663, height: 32),
        auxRight: CGRect(x: 848, y: 950, width: 664, height: 32))

    /// An instant that lands `IslandBody.phase` on exactly `phase` for a cycle
    /// of `cycle` seconds — derived from the rule (`truncatingRemainder` against
    /// `timeIntervalSinceReferenceDate`) rather than by picking dates until the
    /// render looked right.
    ///
    /// **Deliberately within the first cycle after the reference date, with no
    /// large offset added.** `truncatingRemainder` of `x` by `cycle` for
    /// `0 ≤ x < cycle` is `x` itself, so the phase this produces is exact. The
    /// obvious-looking `(1_000_000 + phase) * cycle` is not: measured, it puts
    /// `phase: 0` at **0.99999999992** for `cycle: 1.1`, because neither 1.1 nor
    /// its millionth multiple is representable — and 0.9999… is on the far side
    /// of `Badge.holes(at:)`'s own `phase < 0.5` boundary from 0, so the two
    /// instants that were meant to straddle it both landed above it and the
    /// full-motion control read as "identical" for the wrong reason. That is the
    /// version of this helper this file was first written with, and it silently
    /// disarmed the one case that covers `bang`.
    static func instant(phase: Double, cycle: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: phase * cycle)
    }

    /// The topmost and leftmost painted rows/columns, measured off the render.
    /// A repeating transform's rest pose differs from its extreme by a
    /// translation, so where the ink starts is the quantity that shows it.
    static func firstPainted(_ r: Raster) -> (row: Int, column: Int)? {
        var row = -1, column = -1
        for y in 0..<r.height where (0..<r.width).contains(where: { !r[$0, y].isTransparent }) {
            row = y
            break
        }
        for x in 0..<r.width where (0..<r.height).contains(where: { !r[x, $0].isTransparent }) {
            column = x
            break
        }
        guard row >= 0, column >= 0 else { return nil }
        return (row, column)
    }

    @MainActor
    static func model(_ state: IslandState, motion: MotionPreference) -> IslandModel {
        let m = IslandModel(geometry: IslandGeometry(screen: mbp14), motion: motion)
        m.state = state
        m.sessionCount = 0
        return m
    }

    @MainActor
    static func render(_ state: IslandState, motion: MotionPreference,
                       at now: Date) throws -> Raster {
        try rasterise(IslandBody(model: model(state, motion: motion), now: now))
    }

    /// Near-white pixels **inside the cat's own 18 columns**, which is the box
    /// this test predicted rather than the whole render.
    ///
    /// White is emitted by exactly two tones, `eyeWhite` and `sparkle`
    /// (`CatPalette`), and `CatGrid`'s art places both only in the eyes: rows 7
    /// and 8, columns 3–5 and 12–14, eight cells in all. `applyFace`'s blink
    /// replaces those rows with `body` and `pupil`, so a blink takes this count
    /// to zero. Nothing else in a collapsed, unhovered island is within
    /// `tolerance` of pure white — the fur ramp's brightest tone,
    /// `lightestTone`, is 36% accent over white and lands near 196 — but the
    /// columns are pinned anyway, because `--bone` text does arrive in the right
    /// flank the moment something hovers and a whole-render scan would then be
    /// counting a different thing without saying so.
    @MainActor
    static func eyeWhitePixels(_ r: Raster, _ m: IslandModel) -> Int {
        let originX = IslandFrames(body: m.frames.body, panel: m.panelFrames.panel)
            .bodyInPanel.origin.x
        let first = Int(originX) + Int(IslandBody.LeftFlankLayout.leadingPadding)
        let last = min(r.width, first + Int(IslandBody.LeftFlankLayout.catWidth))
        var count = 0
        for x in first..<last {
            for y in 0..<r.height {
                let p = r[x, y]
                if p.a > 0, p.r >= 249, p.g >= 249, p.b >= 249 { count += 1 }
            }
        }
        return count
    }

    /// The eight white cells `CatGrid`'s art gives an open-eyed cat, derived
    /// from the art rather than from a measurement of the render: row 7 has
    /// `K W W` on each side and row 8 a single `W`.
    static let openEyeWhiteCells = 8

    // MARK: - Defect 1: the pose with motion off

    /// The bug, exactly. `phase` divided an arbitrary `Date()` by the mood's
    /// cycle, so with motion `off` — where `needsTimeline` is false and the view
    /// is handed one `Date()` for the whole run — the pose was whatever instant
    /// the view happened to be built at.
    ///
    /// Two instants, one render each, and the *same* pixels must come out. The
    /// control in the second half is what stops this being a test that a fix
    /// freezing every level would also pass: at motion `full` those same two
    /// instants must differ, or the pair of instants proves nothing.
    ///
    /// `differingPixelCount(from:)`, because `Raster` is not `Equatable` — a
    /// measured quantity, not an image comparison.
    @MainActor @Test func withMotionOffTheIslandIsPosedTheSameWayEveryTime() throws {
        // One row per thing that actually reads a phase, with the cycle whose
        // fractions those two instants are chosen against.
        let cases: [(IslandState, TimeInterval, String)] = [
            (.running, CatMood.trot.motion.cycle, "trot's blink past phase 0.92"),
            (.waiting, Badge.bang.motion.cycle, "bang's one-cell shift past phase 0.5"),
        ]
        for (state, cycle, what) in cases {
            let early = Self.instant(phase: 0.0, cycle: cycle)
            let late = Self.instant(phase: 0.95, cycle: cycle)

            let a = try Self.render(state, motion: .noMotion, at: early)
            let b = try Self.render(state, motion: .noMotion, at: late)
            #expect(a.differingPixelCount(from: b) == 0,
                    "\(state) with motion off drew \(a.differingPixelCount(from: b)) different pixels at two different instants — the pose is still arbitrary, so \(what) still lands by luck of when the view was built")

            let c = try Self.render(state, motion: .fullMotion, at: early)
            let d = try Self.render(state, motion: .fullMotion, at: late)
            #expect(c.differingPixelCount(from: d) > 0,
                    "at motion full those two instants rendered identically, so this pair cannot show a freeze either way — \(what) is no longer at the phase this test assumes")
        }
    }

    /// The specific harm the freeze caused, named on its own because the test
    /// above would still pass if `off` froze the cat mid-blink deterministically.
    /// ~8% of arbitrary instants land past 0.92, and the chosen pose must not be
    /// one of them: a *running* agent with its eyes shut for the whole run reads
    /// as a dead one.
    ///
    /// Rendered at the instant that does blink at full motion, so the assertion
    /// is about the preference and not about the date.
    @MainActor @Test func withMotionOffTheRunningCatsEyesAreOpen() throws {
        let cycle = CatMood.trot.motion.cycle
        let blinkInstant = Self.instant(phase: 0.95, cycle: cycle)

        let off = Self.model(.running, motion: .noMotion)
        let offRaster = try rasterise(IslandBody(model: off, now: blinkInstant))
        #expect(Self.eyeWhitePixels(offRaster, off) == Self.openEyeWhiteCells,
                "motion off drew \(Self.eyeWhitePixels(offRaster, off)) white eye pixels where the art has \(Self.openEyeWhiteCells) — the chosen pose is mid-blink")

        let full = Self.model(.running, motion: .fullMotion)
        let fullRaster = try rasterise(IslandBody(model: full, now: blinkInstant))
        #expect(Self.eyeWhitePixels(fullRaster, full) == 0,
                "this instant no longer blinks at motion full, so the test above is asserting nothing about the blink")
    }

    /// The regression guard the plan names: a fix that froze the cat at *every*
    /// level would pass both tests above.
    @MainActor @Test func withMotionFullTheCatStillBlinks() throws {
        let cycle = CatMood.trot.motion.cycle
        let m = Self.model(.running, motion: .fullMotion)
        let open = try rasterise(IslandBody(model: m, now: Self.instant(phase: 0.0, cycle: cycle)))
        let shut = try rasterise(IslandBody(model: m, now: Self.instant(phase: 0.95, cycle: cycle)))
        #expect(Self.eyeWhitePixels(open, m) == Self.openEyeWhiteCells)
        #expect(Self.eyeWhitePixels(shut, m) == 0,
                "with motion full the cat no longer blinks at all")
    }

    /// `reduced` honours what `resolve(_:)` says rather than inventing a third
    /// behaviour: it halves `framesPerSecond` and leaves `cycle` and continuity
    /// alone, so a reduced cycle is at the same point at the same instant as a
    /// full one — only sampled half as often, which
    /// `IslandView.minimumInterval(for:)` already applies. A phase frozen or
    /// slewed here as well would reduce it twice.
    @MainActor @Test func withMotionReducedThePhaseStillAdvances() throws {
        let cycle = CatMood.trot.motion.cycle
        let m = Self.model(.running, motion: .reducedMotion)
        let open = try rasterise(IslandBody(model: m, now: Self.instant(phase: 0.0, cycle: cycle)))
        let shut = try rasterise(IslandBody(model: m, now: Self.instant(phase: 0.95, cycle: cycle)))
        #expect(Self.eyeWhitePixels(open, m) == Self.openEyeWhiteCells)
        #expect(Self.eyeWhitePixels(shut, m) == 0,
                "motion reduced froze the phase — `resolve(_:)` keeps the cycle at every level but off, so reduced must blink exactly as full does")
    }

    /// The gate is `allowsMotion` and not the resolved profile's `cycle`, and
    /// `Badge.bang` is why: `resolve(_:)` returns an already-still profile
    /// unchanged at *every* level — its own guard exists so a request for less
    /// motion cannot set a sleeping cat moving — so `bang`'s `isContinuous:
    /// false, cycle: 1.1` survives `.off` intact and a cycle-based gate would
    /// leave the badge frozen at whichever of its two positions an arbitrary
    /// `Date()` named.
    ///
    /// Asserted on the rule directly as well as through the render above,
    /// because the render can only show that *something* stopped moving.
    /// `@MainActor` because the last two assertions call `IslandBody.phase`, which
    /// is main-actor isolated — four `#ActorIsolatedCall` warnings through macro
    /// expansion otherwise, the repo's only remaining build warning when Plan 6.1
    /// Task 6 closed the plan (visible on a clean build only; an incremental one
    /// caches it away). Nothing else about the test changes: it makes no
    /// assertion about which actor it runs on.
    @MainActor @Test func aStillProfileWithALiveCycleIsStillFrozenByMotionOff() {
        let bang = Badge.bang.motion
        #expect(bang.isContinuous == false)
        #expect(bang.cycle > 0, "bang no longer has a cycle to be frozen at the wrong point of")
        #expect(MotionPreference.noMotion.resolve(bang).cycle == bang.cycle,
                "resolve(_:) now zeroes an already-still profile's cycle, so `allowsMotion` may no longer be the only gate that covers bang")

        let mid = MotionBypassTests.instant(phase: 0.7, cycle: bang.cycle)
        #expect(IslandBody.phase(at: mid, cycle: bang.cycle, motion: .fullMotion) > 0.5)
        #expect(IslandBody.phase(at: mid, cycle: bang.cycle, motion: .noMotion) == 0)
    }

    // MARK: - Defect 3: the transforms

    /// The badge-transform spike's own open item, closed. `BadgeCanvas` declared
    /// a `.repeatForever` `.scaleEffect`/`.opacity` unconditionally, so motion
    /// `.off` changed the cost by nothing.
    ///
    /// With the animation removed the badge has to sit at the mockup's **base**
    /// style — `island-motion.html:439`'s whole reduced-motion rule is
    /// `animation:none`, and a CSS element with no animation renders at its base
    /// style rather than at `0%`. Leaving the `pulsing ? upper : lower`
    /// expression standing would instead park every badge at its *lower*
    /// keyframe, which for `zzz` is `zfloat`'s `opacity:0`.
    ///
    /// ## What a render can and cannot show here, measured
    ///
    /// **`onAppear` *does* fire under `ImageRenderer`, and its state change
    /// reaches the same render.** Verified directly with a `Rectangle` whose fill
    /// `onAppear` flips: the closure runs and the render comes back in the *new*
    /// colour. So a full-motion render shows each badge at `pulsing == true` —
    /// its **animated** pose, `scale.upperBound` — not at the resting one. Two
    /// consequences, and the second is a real limit on this test:
    ///
    /// - Motion off must come out monochrome and on whole pixels. A sub-integral
    ///   `scaleEffect` dissolves a pixel grid into blends — the instrument
    ///   `theCatsGridSurvivesATranslateButNotAScale` established — so a single
    ///   distinct colour is the strong statement that no transform is applied.
    /// - `check`, `cross` and `bang` share `twinkle`'s numbers, whose
    ///   `scale.upperBound` is exactly **1.0** with `rise: 0` — so their animated
    ///   pose and their resting pose are the same picture, and **no render can
    ///   tell the gate's two branches apart for those three.** That half is
    ///   covered by `getrusage` in `BadgeCPUProbe`'s motion-off row and by
    ///   nothing here; saying so is better than an assertion that looks like
    ///   evidence and is not.
    @MainActor @Test func withMotionOffEveryBadgeIsDrawnUnscaled() throws {
        for badge in Badge.allCases {
            let tint = IslandState.dormant.accent
            let off = try rasterise(BadgeCanvas(badge: badge, phase: 0, tint: tint,
                                                cellSize: 2, motion: .noMotion), scale: 2)
            let full = try rasterise(BadgeCanvas(badge: badge, phase: 0, tint: tint,
                                                 cellSize: 2, motion: .fullMotion), scale: 2)
            #expect(off.distinctColours.count == 1,
                    "\(badge) with motion off drew \(off.distinctColours.count) colours — a badge is monochrome, and an unscaled 7×7 grid of 2pt cells lands on whole pixels, so more than one colour means a transform is still being applied")
            let animatedPoseIsVisiblyDifferent =
                badge.pulse.scale.upperBound != 1 || badge.pulse.rise != 0
            if animatedPoseIsVisiblyDifferent {
                #expect(full.differingPixelCount(from: off) > 0,
                        "\(badge) rendered identically at motion full and motion off even though its animated pose is scale \(badge.pulse.scale.upperBound) and rise \(badge.pulse.rise) — the preference is reaching nothing")
            }
        }
    }

    /// `CatCanvas` had the identical bypass, unrecorded by the spike because the
    /// spike only looked at badges — and it matters as much, because Plan 4.5
    /// moved the cat's own motion onto a `.repeatForever` transform here and the
    /// spike measured that charge as *per island* rather than per animation.
    ///
    /// The quantity is the translation. `onAppear` fires under `ImageRenderer`
    /// (see the badge test above), so a full-motion render catches the sprite at
    /// `moving == true` — displaced by the whole of `Pulse.rise`/`.sway` — while
    /// motion off must leave it at rest. Both expected shifts are derived from
    /// `CatMood.pulse` and the rasterisation scale, not widened until they passed.
    ///
    /// `happy` is skipped and cannot be otherwise: its transform is a one-shot
    /// pop whose *animated* value is `scale 1`, identical to its resting value,
    /// so the two branches paint the same picture. `catpop`'s 0.6 exists only as
    /// the frame before the spring starts.
    @MainActor @Test func withMotionOffTheCatSitsAtRestRatherThanAtItsPulsesExtreme() throws {
        let scale: CGFloat = 2
        let palette = CatPalette(accent: IslandState.running.accent)
        for mood in CatMood.allCases {
            guard let pulse = mood.pulse else {
                #expect(mood == .happy, "\(mood) lost its pulse, so this test now covers less than it says")
                continue
            }
            let cat = ResolvedCat(coat: .tabby, mood: mood, phase: 0.2)
            // 8pt of slack each way: the largest displacement is `call`'s 3pt,
            // and `.offset` does not grow the layout, so an unpadded render
            // would clip the very shift being measured.
            let off = try rasterise(CatCanvas(cat: cat, palette: palette, cellSize: 1,
                                              motion: .noMotion).padding(8), scale: scale)
            let full = try rasterise(CatCanvas(cat: cat, palette: palette, cellSize: 1,
                                               motion: .fullMotion).padding(8), scale: scale)
            let atRest = try #require(Self.firstPainted(off), "\(mood) painted nothing at all")
            let moved = try #require(Self.firstPainted(full), "\(mood) painted nothing at all")
            #expect(moved.row - atRest.row == Int(pulse.rise * scale),
                    "\(mood): motion off put the sprite's top at \(atRest.row) and motion full at \(moved.row), a shift of \(moved.row - atRest.row)px where the pulse's own rise is \(pulse.rise)pt — with motion off the transform must not be applied at all")
            #expect(moved.column - atRest.column == Int(pulse.sway * scale),
                    "\(mood): sideways shift was \(moved.column - atRest.column)px against a sway of \(pulse.sway)pt")
        }
    }

    // MARK: - Defect 2: Reduce Motion is a live setting

    @MainActor private func makeController() -> NotchController {
        let appModel = AppModel(socketPath: "/tmp/vibecat-motion-test-unused.sock")
        let c = NotchController(model: appModel, metrics: { Self.mbp14 })
        c.refreshGeometry()
        c.present()
        return c
    }

    /// One level down from "does the handler work". Every behavioural test below
    /// drives `refreshMotion()`/`apply(motion:)` directly, because a test process
    /// cannot toggle a system accessibility switch — so without this, deleting
    /// the whole installation block in `present()` would fail no test at all,
    /// which is precisely what Plan 6.4's review found had happened to the
    /// Escape monitor. Same shape as
    /// `presentInstallsTheEscapeMonitorAndDismissRemovesIt`.
    @MainActor @Test func presentInstallsTheReduceMotionObserverAndDismissRemovesIt() {
        let c = makeController()
        #expect(c.motionObserverForTesting != nil,
                "present() did not observe accessibilityDisplayOptionsDidChangeNotification, so toggling Reduce Motion still does nothing until relaunch")
        c.dismiss()
        #expect(c.motionObserverForTesting == nil,
                "dismiss() left the observer registered — a block-based observer on NSWorkspace's centre outlives the object it captures")
    }

    /// §9.3's override runs one way only, and a *refresh* must not quietly break
    /// that. `refreshed()` keeps `chosen`; `current()` would default it to
    /// `.full` and promote a user who chose `off` back into motion the first time
    /// the system posted any accessibility change at all.
    ///
    /// Asserted on `chosen` and `effective`, never on `systemWantsReduced`: that
    /// half is a real read of this machine's Accessibility settings, and an
    /// assertion whose outcome turns on what the machine is configured like is
    /// an assertion that will eventually fail for no reason — this suite has
    /// already shipped one (a hardcoded 48kHz sample rate that depended on the
    /// attached audio hardware). `effective` is `.off` whichever way that read
    /// comes back, which is exactly the property under test.
    @MainActor @Test func refreshingMotionRereadsTheSystemWithoutDiscardingTheChoice() {
        let c = makeController()
        defer { c.dismiss() }
        for chosen in [MotionLevel.off, .reduced] {
            c.model.motion = MotionPreference(chosen: chosen, systemWantsReduced: false)
            c.refreshMotion()
            #expect(c.model.motion.chosen == chosen,
                    "refreshMotion() replaced a chosen level of \(chosen) with \(c.model.motion.chosen) — it is re-resolving through current(), whose chosen defaults to .full")
            #expect(c.model.motion.effective == chosen,
                    "a refresh moved the effective level off \(chosen)")
        }
    }

    /// The write itself, in both directions — the half a test process can drive
    /// that a real Reduce Motion toggle cannot.
    @MainActor @Test func applyingAFreshPreferenceReachesTheModel() {
        let c = makeController()
        defer { c.dismiss() }
        c.apply(motion: .fullMotion)
        #expect(c.model.motion.allowsMotion)
        c.apply(motion: .noMotion)
        #expect(c.model.motion.allowsMotion == false,
                "apply(motion:) did not reach model.motion, so the observer has nothing to change")
        c.apply(motion: .fullMotion)
        #expect(c.model.motion.allowsMotion,
                "apply(motion:) is one-way — motion turned back on never reaches the model")
    }

    /// A live change has to reach the *pixels*, not just the model. `IslandView`
    /// reads `model.motion` through `needsTimeline`, `activeProfile` and both
    /// phases, so the observation the write triggers is the whole mechanism —
    /// this pins that the model's own property is the one the render depends on,
    /// with no relaunch involved.
    @MainActor @Test func aLiveMotionChangeChangesWhatTheIslandDraws() throws {
        let c = makeController()
        defer { c.dismiss() }
        c.model.state = .running
        let blink = Self.instant(phase: 0.95, cycle: CatMood.trot.motion.cycle)

        c.apply(motion: .fullMotion)
        let animated = try rasterise(IslandBody(model: c.model, now: blink))
        #expect(Self.eyeWhitePixels(animated, c.model) == 0)
        #expect(c.model.needsTimeline)

        c.apply(motion: .noMotion)
        let still = try rasterise(IslandBody(model: c.model, now: blink))
        #expect(Self.eyeWhitePixels(still, c.model) == Self.openEyeWhiteCells,
                "turning motion off at runtime did not change the pose — the view is still reading a preference fixed at launch")
        #expect(c.model.needsTimeline == false)
    }
}
