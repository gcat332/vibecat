#if DEBUG
import AppKit
import VibeCatUI

/// Task 9's own hardware unknown: can a `.nonactivatingPanel` at `.statusBar`
/// become key and receive `keyDown` **without stealing focus from whatever
/// was frontmost**? Nobody has measured this. This file does not answer it —
/// it only prints what a person with a display needs in order to.
///
/// This is deliberately `#if DEBUG` — a diagnostic, not a feature, so it
/// never ships in a release build. `Scripts/build-app.sh`'s default config
/// is `debug`, so the ordinary documented build already includes it.
///
/// ## How to run it
///
/// Build and sign the real app the same way every other hardware
/// measurement on this project has (see `Scripts/build-app.sh`'s own
/// comment on why a bare `swift run` binary will not do — activation
/// policy and TCC both depend on the bundle):
///
/// ```
/// Scripts/build-app.sh
/// ```
///
/// Then — **click on some other app first** (Finder, your terminal,
/// whatever you want to prove keeps its focus; this is what makes "did
/// frontmost change" a meaningful question instead of a trivial one, the
/// exact mistake an earlier attempt at a *different* measurement on this
/// project made by leaving VibeCat itself frontmost) — run:
///
/// ```
/// open -n --stdout /tmp/keydown-probe.log --stderr /tmp/keydown-probe.log \
///      .build/VibeCat.app --args --keydown-probe
/// tail -f /tmp/keydown-probe.log
/// ```
///
/// `-n`/`--new` matters: without it, `open` just re-activates an
/// already-running VibeCat instance instead of launching a fresh process
/// that actually takes the `--keydown-probe` branch below. `--stdout`/
/// `--stderr` matter too — `open` launches a detached process with no
/// controlling terminal, so a bare `print()` goes nowhere visible without
/// them (`man open`'s own `-o`/`--stdout` and `--stderr` flags, confirmed
/// against this machine's `open --help` rather than assumed). **Order
/// matters and was wrong in an earlier draft of this comment**: `open`'s own
/// flags must come *before* the bundle path and before `--args` — `--args`
/// means "everything after this is the launched app's own argv," so a
/// `--stdout`/`--stderr` placed after it silently becomes two more of
/// *this* app's arguments instead of `open`'s, and nothing gets redirected.
/// Confirmed the hard way: an earlier run of this exact binary, launched
/// with the flags in the wrong order, printed nowhere and — a second, worse
/// bug this caught — never exited at all, because both abort branches below
/// used to `return` rather than `exit(2)`, and `main.swift` calls `app.run()`
/// unconditionally right after `KeyDownProbe.run()`. Fixed in both places;
/// the smoke test that caught it is recorded in task-9-report.md.
///
/// ## What it prints, and how to read it
///
/// 1. `frontmost before: <name> (<bundle id>)` — whatever was active the
///    instant this process reached the probe, i.e. before this file does
///    anything at all. **If this reads `loginwindow`, the run is void: the
///    screen is locked, and no window anywhere can become key regardless of
///    anything below.** This exact failure produced a void reading once
///    already on this project (see task-9-report.md) and nearly became a
///    recorded fact; the probe checks for it itself and refuses to go
///    further when it sees it, rather than trusting whoever runs it to
///    remember.
/// 2. `panel.isKeyWindow` and `NSApp.isActive`, read immediately after
///    `makeKeyAndOrderFront(nil)` on a real `NotchPanel` — the exact
///    production type, constructed the exact way `NotchController` builds
///    it (`isFloatingPanel` before `level`, in that order — reversing it is
///    the ordering trap the original notch-shell spike's §2b documents),
///    not a hand-rolled re-creation that could quietly drift from it.
/// 3. `frontmost after: <name> (<bundle id>)` — read at the same instant.
/// 4. An 8-second window with a local `keyDown` monitor live, printing every
///    keystroke it actually receives. Press a digit or Escape during this
///    window — and separately, try typing into whichever app was frontmost
///    in step 1 — to see directly whether the keystroke reached this panel,
///    the other app, or both. This is the most direct evidence available:
///    `isKeyWindow`/`isActive` are proxies for whether input actually
///    arrives, not a substitute for checking that it does.
///
/// ## Interpreting the outcome
///
/// - `before` and `after` name the same app, that app is not this one, and
///   `panel.isKeyWindow == true` — **Path A**: the panel took key status
///   without taking focus. Number keys can be wired the way §10.1 asks,
///   through `KeyRouting.pick` and `NotchController`'s own (not yet written)
///   `keyDown` handling.
/// - `after` names this app's own bundle id (`com.gcat332.vibecat`) even
///   though `before` did not — **Path B**: becoming key activated the app.
///   Task 9's brief calls this "worse than no key: the terminal loses its
///   cursor at the exact moment the person is deciding something
///   destructive." Do not wire number keys; `Escape`-to-dismiss (already
///   implemented — see `NotchController.dismissOnEscape`) is the fallback,
///   and it is safe under this outcome precisely because it never asks
///   `QuestionModel` to produce an answer.
/// - `panel.isKeyWindow == false` — `makeKeyAndOrderFront` did not succeed
///   in making the panel key at all on this machine/OS combination. The
///   question is unresolved, not answered "no" — check `before`/`after`
///   were not `loginwindow` first, since a locked screen is the known cause
///   of exactly this shape of false negative.
/// - Whatever step 4's monitor prints is the most direct evidence of all:
///   if a keystroke logs a line here while focus visibly stayed on the
///   other app, input is reaching this panel regardless of what
///   `isActive`/`frontmostApplication` claim about activation.
///
/// A class, not an enum of static funcs, for two reasons that are really the
/// same underlying one — nothing else in this file keeps anything alive for
/// the 8-second listening window on its own:
///
/// - The local `keyDown` monitor's own token has to survive from
///   installation until the timer removes it 8 seconds later, and a plain
///   local `let` captured into the timer's closure trips Swift 6 strict
///   concurrency (`Any` is not `Sendable`, and the timer closure is not
///   actor-isolated even though it only ever fires on the main run loop). A
///   stored property read through `self` — the same shape
///   `NotchController.keyMonitor` already uses for the identical problem
///   — sidesteps it: capturing a class reference across that boundary is
///   fine, only capturing the bare token directly was not.
/// - The panel itself, and this instance, both need a *strong* owner for
///   those same 8 seconds — `[weak self]` in the timer's own closure (needed
///   so the timer does not keep this alive forever if the process somehow
///   outlived it) means nothing retains either once `start()` returns,
///   unless something else does. `Self.current` is that something: assigned
///   once in `run()`, released only when the timer's own `exit(0)` ends the
///   process anyway. Without it, ARC would be free to deallocate the panel
///   — and with it, the window this whole probe exists to measure —
///   the instant `start()` returns, before a person watching stdout even
///   has time to read the first line, let alone press a key.
@MainActor final class KeyDownProbe {
    private static let loginwindowBundleID = "com.apple.loginwindow"
    private static var current: KeyDownProbe?

    private var monitor: Any?
    private var panel: NotchPanel?

    static func run() {
        let probe = KeyDownProbe()
        current = probe
        probe.start()
    }

    private func start() {
        let before = NSWorkspace.shared.frontmostApplication
        Self.report("frontmost before", before)

        guard !Self.isLoginwindow(before) else {
            print("""
            ABORT: frontmost is loginwindow — the screen is locked, so no \
            window anywhere can become key regardless of anything this probe \
            does. Unlock the screen and run the probe again.
            """)
            // exit(2), not a bare `return` — confirmed by an actual run of
            // this exact binary: `main.swift` calls `app.run()` unconditionally
            // right after `KeyDownProbe.run()`, which blocks forever with
            // nothing scheduled to end it if this function merely returns.
            // A hung, silent process is a worse outcome than the loginwindow
            // case itself; exit(2) (distinct from the exit(0) a completed
            // measurement ends with) is what actually stops it.
            exit(2)
        }

        guard let metrics = ScreenMetrics.current() else {
            print("ABORT: no screen at all — nothing to measure against.")
            exit(2)   // see the loginwindow branch above for why this cannot be a bare `return`
        }

        // The exact type production ships, built the exact way
        // NotchController.present() builds it — not a re-creation, which is
        // exactly how the original notch-shell spike's first measurement
        // went wrong (an `isFloatingPanel`/`level` ordering slip silently
        // left the panel at level 3 instead of .statusBar; see that spike's
        // own §2b).
        let geometry = IslandGeometry(screen: metrics)
        let panel = NotchPanel(frames: geometry.maxCollapsedFrames())
        self.panel = panel   // see this type's own doc comment on why this must not be a bare local

        panel.makeKeyAndOrderFront(nil)

        let after = NSWorkspace.shared.frontmostApplication
        print("panel.isKeyWindow: \(panel.isKeyWindow)")
        print("panel.level == .statusBar: \(panel.level == .statusBar)")
        print("NSApp.isActive: \(NSApp.isActive)")
        Self.report("frontmost after", after)
        print("frontmost changed: \(before?.bundleIdentifier != after?.bundleIdentifier)")

        print("""

        Listening for keyDown for 8 seconds. Press a digit or Escape now, and \
        separately try typing into whichever app was frontmost above — watch \
        for whether it shows up here, there, or both.
        """)

        // A local monitor, the same mechanism (and the same reasoning —
        // no Accessibility permission needed) NotchController's own
        // Escape-dismiss uses; see that type's own doc comment.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            print("keyDown observed: char=\(String(describing: event.charactersIgnoringModifiers)) " +
                  "keyCode=\(event.keyCode) modifiers=\(event.modifierFlags.rawValue)")
            return event
        }

        // Timer(...) + RunLoop.main.add, not Timer.scheduledTimer — the same
        // idiom AppModel's prune timer and HoverMonitor's sampling timer
        // already use. [weak self] + MainActor.assumeIsolated: Timer's own
        // closure is not itself MainActor-isolated, even though it only
        // ever fires on the main run loop — the same reasoning those two
        // types' own timers already document.
        let t = Timer(timeInterval: 8, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                if let monitor = self?.monitor { NSEvent.removeMonitor(monitor) }
                print("\nprobe finished.")
                exit(0)
            }
        }
        RunLoop.main.add(t, forMode: .common)
    }

    private static func report(_ label: String, _ app: NSRunningApplication?) {
        print("\(label): \(app?.localizedName ?? "nil") (\(app?.bundleIdentifier ?? "nil"))")
    }

    /// Checked against both the bundle identifier (stable, documented) and
    /// the localised name (belt-and-suspenders: the void 2026-08-02 reading
    /// this project already hit printed the string "loginwindow" itself, and
    /// this does not assume which property that earlier probe read it from).
    private static func isLoginwindow(_ app: NSRunningApplication?) -> Bool {
        app?.bundleIdentifier == loginwindowBundleID
            || app?.localizedName?.caseInsensitiveCompare("loginwindow") == .orderedSame
    }
}
#endif
