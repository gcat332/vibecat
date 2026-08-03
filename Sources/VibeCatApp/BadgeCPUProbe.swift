#if DEBUG
import AppKit
import Darwin
import VibeCatCore
import VibeCatUI

/// Settles the one claim `Badge.pulse` records in the source as unmeasured:
/// every badge now animates as a repeating SwiftUI `.scaleEffect`/`.opacity`
/// rather than by swapping cells, on the reasoning that the render server runs
/// a declared transform without ever asking SwiftUI to draw again — so
/// `needsTimeline` stays false and the idle island keeps costing 0.35% of a
/// core. That reasoning is load-bearing in shipped code and has never been
/// checked against a number.
///
/// This file does not reason about it. It measures two things at once, on the
/// real production island, in the real panel:
///
/// - **`BadgeCanvas.canvasDrawCount`** — actual invocations of the badge's
///   `Canvas` renderer. Flat while a transform animates means the transform is
///   free of SwiftUI; climbing with the frame rate means it is not, and the
///   badges cost what the cell-swapping version they replaced cost.
/// - **`getrusage(RUSAGE_SELF)`** — CPU seconds, as a fraction of one core.
///   Never `ps %cpu`: it is a decaying average and it once produced a false
///   failure on this project that cost most of a plan's investigation budget.
///
/// ## Why two states, not one
///
/// `dormant` alone cannot distinguish "the transform costs nothing" from "the
/// instrument is broken" or "the panel is not drawing at all". So the probe
/// also measures `running`, whose cat trots at 12fps and therefore *does* take
/// `IslandView`'s `TimelineView` branch, rebuilding the badge's body with it.
/// A flat dormant count beside a climbing running count is the same instrument
/// reporting both mechanisms, which is what makes the dormant reading mean
/// something. That contrast is the whole design of this probe.
///
/// **What it cannot tell you:** whether the animation is *visible*. A
/// transform that never runs would also report zero draws. The eye is the
/// instrument for that, and it already exists — `VIBECAT_GIF=…` in
/// `Tests/VibeCatUITests/Cat/ContactSheet.swift`.
///
/// ## How to run it
///
/// Needs the real bundle for the same reasons every other hardware measurement
/// on this project does (`Scripts/build-app.sh`'s own comment), and needs an
/// unlocked screen with the notch unobscured — a locked screen or an occluded
/// window can have macOS stop compositing entirely, which would read as "the
/// transform is free" for the wrong reason. Both are checked below and abort
/// the run rather than reporting a void number.
///
/// ```bash
/// Scripts/build-app.sh
/// open -n --stdout /tmp/badge-cpu.log --stderr /tmp/badge-cpu.log \
///      .build/VibeCat.app --args --badge-cpu-probe
/// tail -f /tmp/badge-cpu.log
/// ```
///
/// `open`'s own flags come before `--args`, and `-n` forces a fresh process —
/// both learned the hard way while running `KeyDownProbe`; see its doc comment.
@MainActor final class BadgeCPUProbe {
    /// Discarded readings while `onAppear` fires, the implicit animations
    /// start, and the first frames settle.
    private static let warmUp: Duration = .seconds(2)
    /// One sample's wall-clock window. Long enough that a 12fps timeline
    /// contributes tens of draws rather than a handful, so the contrast
    /// between the two states is not a rounding artefact.
    private static let sampleWindow: Duration = .seconds(3)
    private static let samplesPerState = 3

    private static var current: BadgeCPUProbe?

    private var model: AppModel?
    private var controller: NotchController?

    static func run() {
        let probe = BadgeCPUProbe()
        // Held for the process's lifetime for the same reason `KeyDownProbe`
        // holds its own: nothing else retains the controller, and with it the
        // panel this probe exists to measure.
        current = probe
        probe.start()
    }

    private func start() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        print("frontmost: \(frontmost?.localizedName ?? "?") (\(frontmost?.bundleIdentifier ?? "?"))")
        if frontmost?.bundleIdentifier == "com.apple.loginwindow" {
            print("""
            ABORT: frontmost is loginwindow — the screen is locked. A locked \
            screen can stop the render server compositing altogether, which \
            would read as "the transform costs nothing" for entirely the wrong \
            reason. Unlock the screen and run again.
            """)
            exit(2)   // not a bare return: main.swift calls app.run() straight after this
        }
        guard ScreenMetrics.current() != nil else {
            print("ABORT: no screen at all — nothing to composite, nothing to measure.")
            exit(2)
        }

        // The real production path, not a re-creation of it. `AppModel` is
        // built but deliberately never `start()`ed: binding the real socket
        // would make this probe fight a running VibeCat for it, and no event
        // needs to arrive for a badge to animate.
        let model = AppModel(socketPath: "/dev/null/vibecat-probe-never-bound.sock")
        let controller = NotchController(model: model)
        self.model = model
        self.controller = controller
        controller.refreshGeometry()

        Task { @MainActor [weak self] in await self?.measure(controller) }
    }

    /// Four rows, each adding exactly one mechanism to the one above it. A
    /// single "dormant costs N%" figure is attributable to nothing — the first
    /// run of this probe produced 9.63% for dormant and could not say whether
    /// the badge transform, the hover monitor's 30Hz polling `Timer`
    /// (`HoverMonitor.start`, installed by `present()`), or the process floor
    /// was responsible. Subtracting adjacent rows can.
    ///
    /// **The second attempt at this decomposition was wrong, and the way it was
    /// wrong is worth keeping.** It tried to isolate the hover monitor by
    /// calling `present()` and then `panel.orderOut(nil)`, on the assumption
    /// that an off-screen window cannot be animating. It reported 10.88% for
    /// that row and 11.05% once the panel was shown — apparently pinning almost
    /// the entire cost on a `Timer` whose body is
    /// `frame.contains(NSEvent.mouseLocation)`, roughly 3.6ms of CPU per sample,
    /// which is absurd on its face. `orderOut` does not stop SwiftUI's
    /// `.repeatForever` animation from ticking, so that row already contained
    /// the transform it was supposed to exclude. The isolation below never puts
    /// two mechanisms in one row: the hover monitor is measured as a standalone
    /// `HoverMonitor` with no panel in existence at all.
    private func measure(_ controller: NotchController) async {
        print("""

        badge transform cost — getrusage(RUSAGE_SELF), \(Self.samplesPerState) \
        samples of \(Self.sampleWindow) each

        Each row adds one mechanism to the row above. Read the differences, not \
        the absolutes.
        """)

        var rows: [(String, [Reading])] = []
        func row(_ label: String) async {
            try? await Task.sleep(for: Self.warmUp)
            var readings: [Reading] = []
            for _ in 0..<Self.samplesPerState { readings.append(await Self.sample()) }
            rows.append((label, readings))
        }

        // 1. Run loop only — no panel, no hover monitor, nothing composited.
        await row("floor: run loop only, no panel, no timer")

        // 2. The 30Hz hover poll on its own, with no panel in existence, so
        //    nothing else can be attributed to it. Stopped again immediately —
        //    `present()` starts its own, and two would double-count.
        let standaloneHover = HoverMonitor()
        standaloneHover.frame = controller.model.frames.body
        standaloneHover.start()
        await row("+ HoverMonitor 30Hz alone (no panel)")
        standaloneHover.stop()

        // 3. The real production island, through the real `present()`: dormant,
        //    cat asleep and still, no `TimelineView`, one repeating
        //    `.scaleEffect`/`.opacity` per `zzz` part. `present()` starts a
        //    hover monitor of its own, so this row is row 2's mechanism plus
        //    the island — and the island's cost is this row minus row 2.
        controller.model.state = .dormant
        controller.model.sessionCount = 0
        controller.present()
        guard let panel = NSApp.windows.first(where: { $0.level == .statusBar }) else {
            print("ABORT: no panel at .statusBar after present() — nothing to measure.")
            exit(2)
        }
        await row("+ dormant island composited (badge transform, no timeline)")

        // 4. The positive control. `running` trots at 12fps, so `IslandView`
        //    takes its `TimelineView` branch and the badge's body is rebuilt
        //    with it — the draw counter must climb here, or the counter is not
        //    measuring what row 3's flat zero claims it is.
        controller.model.state = .running
        controller.model.sessionCount = 2
        await row("+ running (12fps timeline instead of no timeline)")

        // 5. Plan 5's own owed measurement. The badge spike accepted ~12% on
        //    single-sprite numbers and named several sprites as a condition
        //    that would reopen it. Twelve sessions, all four states, drawer
        //    open — not just a second animation (measured separately, and
        //    already known to be cheap), but the session list's own rows,
        //    each with a state dot of its own.
        controller.model.sessions = (0..<12).map { i in
            Session(event: VibeEvent(id: "e\(i)", cli: "claude-code",
                                     kind: [.permission, .failed, .running, .idle][i % 4],
                                     session: "s\(i)", cwd: "/tmp/p\(i)"),
                    now: Date(timeIntervalSince1970: 1_000_000))
        }
        controller.model.state = .running
        controller.model.sessionCount = 12
        controller.model.drawerOpen = true
        await row("+ session list open, 12 sessions across all four states")

        // 6. Back to dormant, with motion turned all the way off and the system
        //    asking for reduced motion as well — the strongest suppression §9.3
        //    can express. `BadgeCanvas` never consults `MotionPreference`, so
        //    the prediction is that this changes nothing; if it does not, the
        //    badges are animating in a configuration the design says must not
        //    animate, and row 3's cost cannot be turned off by any setting.
        //    Also closes the drawer and clears row 5's sessions: this row
        //    tests motion suppression alone, not motion suppression plus an
        //    open list — leaving either set would fold row 5's cost in here.
        controller.model.state = .dormant
        controller.model.sessionCount = 0
        controller.model.drawerOpen = false
        controller.model.sessions = []
        controller.model.motion = MotionPreference(chosen: .off, systemWantsReduced: true)
        await row("+ dormant again, motion .off and system reduce-motion on")

        print("")
        print("| what is running | draws/s | CPU (% of one core) |")
        print("|---|---|---|")
        for (label, readings) in rows {
            let draws = Self.spread(readings.map(\.drawsPerSecond), decimals: 1)
            let cpu = Self.spread(readings.map { $0.coreFraction * 100 }, decimals: 2)
            print("| \(label) | \(draws) | \(cpu) |")
        }

        print("""

        panel occlusion at the end: \(panel.occlusionState.contains(.visible) ? "visible" : "NOT VISIBLE — rows 3 and 4 are void")
        recorded baselines, from an earlier build and so not a same-run control: \
        the idle island measured 0.35% of a core before badges animated at all, \
        and a cell-swapping `zzz` measured 3.6-4.1%.
        """)
        exit(0)
    }

    private struct Reading {
        let drawsPerSecond: Double
        /// CPU seconds burned per wall-clock second: 1.0 is one core saturated.
        let coreFraction: Double
    }

    private static func sample() async -> Reading {
        let drawsBefore = BadgeCanvas.canvasDrawCount
        let cpuBefore = cpuSeconds()
        let clockBefore = ContinuousClock.now

        try? await Task.sleep(for: sampleWindow)

        // Wall clock is measured rather than assumed equal to `sampleWindow`:
        // `Task.sleep` guarantees a floor, not an exact duration, and dividing
        // by the nominal window would quietly inflate every rate.
        let elapsed = (ContinuousClock.now - clockBefore).asSeconds
        return Reading(drawsPerSecond: Double(BadgeCanvas.canvasDrawCount - drawsBefore) / elapsed,
                       coreFraction: (cpuSeconds() - cpuBefore) / elapsed)
    }

    private static func cpuSeconds() -> Double {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return .nan }
        func seconds(_ t: timeval) -> Double {
            Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000
        }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    /// Mean and range, never a single figure — one lucky run is not a
    /// measurement, and the spread is what tells a reader whether the
    /// difference between two rows is real.
    private static func spread(_ values: [Double], decimals: Int) -> String {
        guard let low = values.min(), let high = values.max(), !values.isEmpty else { return "—" }
        let mean = values.reduce(0, +) / Double(values.count)
        func f(_ v: Double) -> String { String(format: "%.\(decimals)f", v) }
        return "\(f(mean))  (\(f(low))–\(f(high)))"
    }
}

private extension Duration {
    /// Seconds as a `Double`. `Duration`'s own components are integer seconds
    /// plus attoseconds, and truncating to `.seconds` alone would turn a 3.02s
    /// window into 3 and skew every rate above by a fraction of a percent.
    var asSeconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
#endif
