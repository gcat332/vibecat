#if DEBUG
import AppKit
import VibeCatCore
import VibeCatUI

/// Answers, on real hardware with an unlocked screen, the one question Plan
/// 6.4 Task 5 could not answer from a test: **what happens to
/// `NSWorkspace.shared.frontmostApplication` when the Settings window opens.**
///
/// It exists for the same reason `KeyDownProbe` does. `swift test` can prove the
/// window is built once, titled, closed and let go — all nine assertions in
/// `SettingsWindowTests` run headlessly — but activation is not a property of a
/// window object, it is a negotiation with the window server, and this machine's
/// screen was locked when Task 5 was implemented (`CGSSessionScreenIsLocked=Yes`,
/// checked via `ioreg -n Root -d1`, not assumed). Under a locked screen
/// `frontmostApplication` is `loginwindow` before *and* after, `keyWindow` is nil,
/// and no reading means anything — the same void-run trap that already produced a
/// wrong recorded fact once on this project (see `KeyDownProbe` and
/// task-9-report.md). So this refuses to report rather than let that happen again.
///
/// ## Running it
///
/// ```bash
/// swift run vibecat --settings-focus-probe                  # prints to this terminal
/// Scripts/build-app.sh && open .build/VibeCat.app --stdout $(tty) --args --settings-focus-probe
/// ```
///
/// The bare binary is enough here, and that is worth stating because CLAUDE.md
/// warns against it: what a bare run cannot do is hold a TCC grant, and nothing
/// about window activation is TCC-gated. Note `open`'s flag order — `--stdout`
/// must precede `--args`, see `KeyDownProbe`'s own comment on the mistake.
///
/// ## What it prints, and how to read it
///
/// Three timestamps — before the window opens, immediately after, and two
/// seconds later — each carrying `frontmost`, this process's own pid, the key
/// window's title, and `NSApp.windows`. The window is opened **through
/// `IslandModel.onOpenSettings`**, the closure the gear button itself calls, so
/// this measures the shipped path rather than a re-creation of it.
///
/// - `frontmost` becomes this process's pid on the middle line and stays there:
///   the Settings window activated the app. **This is the intended outcome**, and
///   the deliberate difference from the notch panel, which must never do it (Plan
///   5, Path A) — a person clicked a gear and asked for a window to type into.
/// - `frontmost` never becomes this pid but `keyWindow` is `VibeCat Settings`:
///   the window took key status without activating, i.e. the panel's Path A
///   behaviour leaked into a window that wants the opposite. `NSApp.activate()`
///   in `SettingsWindowController.show()` is the line to look at.
/// - `keyWindow=nil` with the window listed and visible: it opened but cannot be
///   typed into. That is the failure this probe exists to catch, and it is worth
///   nothing unless the abort below stayed quiet.
///
/// `NSApp.isActive` is printed and **is not evidence** either way. Plan 5's spike
/// read it `true` in every run while focus demonstrably stayed elsewhere; Task 5's
/// own locked-screen run read it `false`. It is here only so a future reader can
/// see it disagreeing with the two readings that do mean something.
@MainActor final class SettingsFocusProbe {
    private static let loginwindowBundleID = "com.apple.loginwindow"
    private static var current: SettingsFocusProbe?

    /// Strong, for the same reason `KeyDownProbe.current` is: nothing else
    /// retains this instance across the sleeps below once `run(...)` returns.
    private let openSettings: @MainActor () -> Void
    private let isOpen: @MainActor () -> Bool

    /// Takes the two closures rather than a `SettingsWindowController` so that
    /// `main.swift` passes **the wiring it actually shipped** — `openSettings`
    /// is `IslandModel.onOpenSettings`, the gear's own closure. A probe handed
    /// the controller directly could pass while the gear was wired to nothing.
    static func run(openSettings: @escaping @MainActor () -> Void,
                    isOpen: @escaping @MainActor () -> Bool) {
        let probe = SettingsFocusProbe(openSettings: openSettings, isOpen: isOpen)
        current = probe
        probe.start()
    }

    private init(openSettings: @escaping @MainActor () -> Void,
                 isOpen: @escaping @MainActor () -> Bool) {
        self.openSettings = openSettings
        self.isOpen = isOpen
    }

    private func start() {
        Task { @MainActor in
            // Two seconds before touching anything: `app.run()` has not started
            // pumping when this is scheduled, and a window ordered front before
            // the run loop is running is not the situation being measured.
            try? await Task.sleep(for: .seconds(2))

            let before = NSWorkspace.shared.frontmostApplication
            guard !Self.isLoginwindow(before) else {
                print("""
                ABORT: frontmost is loginwindow — the screen is locked, so no \
                window can become key or frontmost regardless of anything this \
                probe does. Every reading below would be void. Unlock the screen \
                and run it again.
                """)
                // exit(2), never a bare `return`: `main.swift` calls `app.run()`
                // right after this, which blocks forever with nothing scheduled
                // to end it. Same reasoning as `KeyDownProbe`'s own abort.
                exit(2)
            }

            report("before open", before)
            openSettings()
            try? await Task.sleep(for: .milliseconds(500))
            report("after open", NSWorkspace.shared.frontmostApplication)
            try? await Task.sleep(for: .seconds(2))
            report("2s later", NSWorkspace.shared.frontmostApplication)
            print("\nprobe finished.")
            exit(0)
        }
    }

    private func report(_ label: String, _ front: NSRunningApplication?) {
        let windows = NSApp.windows.map {
            "\($0.title.isEmpty ? "«untitled»" : $0.title):visible=\($0.isVisible)"
        }
        print("""
        [\(label)] frontmost=\(front?.localizedName ?? "nil") \
        (\(front?.bundleIdentifier ?? "nil")) pid=\(front?.processIdentifier ?? -1) \
        ownPid=\(ProcessInfo.processInfo.processIdentifier) \
        isFrontmostUs=\(front?.processIdentifier == ProcessInfo.processInfo.processIdentifier) \
        keyWindow=\(NSApp.keyWindow?.title ?? "nil") isOpen=\(isOpen()) \
        NSApp.isActive=\(NSApp.isActive) [not evidence — see this type's doc comment] \
        windows=\(windows)
        """)
    }

    /// Both the bundle identifier and the localised name, exactly as
    /// `KeyDownProbe.isLoginwindow` does and for the reason recorded there.
    private static func isLoginwindow(_ app: NSRunningApplication?) -> Bool {
        app?.bundleIdentifier == loginwindowBundleID
            || app?.localizedName?.caseInsensitiveCompare("loginwindow") == .orderedSame
    }
}
#endif
