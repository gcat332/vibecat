import Testing
import Foundation
import AppKit
import SwiftUI
import VibeCatCore
@testable import VibeCatUI

/// Every `NSWindow` the tests in this file build, kept alive for the whole
/// process — deliberately, and this is the reason.
///
/// **`swift test` never calls `NSApplication.run()`, and a titled `NSWindow`
/// that *deallocates* in such a process takes the process down with it.**
/// Measured on macOS 26.5.2: any single test in this file is enough, and the run
/// dies mid-suite with `SIGSEGV`/`EXC_BAD_ACCESS` inside
/// `-[_NSWindowTransformAnimation dealloc]`, reached from
/// `CA::Transaction::commit()`'s autorelease-pool pop on the main run loop. It
/// is an animation AppKit started for the window's chrome, released after the
/// window it points at is already gone. AppKit retires that animation inside
/// `NSApplication.run()`, which is why the real app never sees this — and why
/// nothing here can wait it out: a 0.25s `RunLoop.main` drain between `show()`
/// and the close does not help (measured), and an `NSAnimation` in this process
/// never advances at all — `currentProgress` stayed `0.0` through a full second
/// of spinning.
///
/// Three further measurements, so that nobody re-derives them:
///
/// - **It is deallocation, not presentation.** Removing `NSApp.activate()`,
///   `makeKeyAndOrderFront(nil)`, or both from `show()` still crashed 3 runs out
///   of 3; so did a window stripped of its appearance, titlebar flag,
///   background colour, min size, `center()` and hosting view, and so did one
///   with `animationBehavior = .none`. Restoring `isReleasedWhenClosed = false`,
///   the one change that stops the window deallocating at all, was clean 3/3.
///   So `show()` is not at fault and needs no seam; the window merely has to
///   outlive the test that opened it.
/// - **It only reproduces with the display on.** With the display asleep the app
///   cannot become active, no such animation is created, and the whole suite is
///   clean — so a green run measured on a locked or sleeping machine says
///   nothing whatever about this bug. `pmset -g log | grep "Display is turned"`
///   is how to check afterwards which kind of run you got.
/// - **It is the titled chrome.** `rasteriseHosted` in `Raster.swift`
///   deallocates a **borderless** window on every call and has never crashed.
///
/// **Retention is what fixes it, and retention alone is not sufficient — both
/// halves are measured.** Take the retention back out of this file and the suite
/// crashes 3 runs out of 3 again, so this is the load-bearing part. But delete
/// `makeKeyAndOrderFront(nil)` from `show()` while keeping every window retained
/// and the same crash returns, 3/3 — a titled window that is *never presented* is
/// apparently not safe to close even while something still holds it, and
/// `isReleasedWhenClosed = false` is then the only thing that quiets it. **Why
/// that is, this comment does not know**; it was not worth chasing, because
/// presenting is what `show()` does in production, and
/// `showingTheWindowPutsItOnScreenRatherThanMerelyBuildingIt` now fails if that
/// ever stops being true.
///
/// A new test in this file that opens a window must go through
/// `showKeepingTheWindowAlive(_:)` rather than calling `show()` directly.
@MainActor private enum LiveWindows {
    private static var all: [NSWindow] = []
    private static var controllers: [SettingsWindowController] = []

    /// Retains `window` for the rest of the process. Idempotent, because two
    /// `show()` calls on one controller hand back the same window.
    static func keep(_ window: NSWindow?) {
        guard let window, !all.contains(where: { $0 === window }) else { return }
        all.append(window)
    }

    /// Retains the *controller* too, which is the half the first version of this
    /// file missed — and it is what closed the remaining crash.
    ///
    /// Keeping only the window still let `SettingsWindowController.deinit` run the
    /// moment a test's local `let c` went out of scope, and that deinit does
    /// `window?.contentView = nil` and `window?.close()`. So the window object
    /// survived while its `NSHostingView` was freed and its chrome was closed
    /// underneath an animation AppKit only retires inside `NSApplication.run()`.
    /// That is exactly the "not safe to close even while something still holds it"
    /// the comment above could not explain: the unsafe act is the **close**, not
    /// the release of the window.
    ///
    /// Measured: window-only retention crashed 1 run in 6 (signal 11); retaining
    /// the controller as well ran clean. The tests that *deliberately* exercise
    /// closing still call it explicitly, which is the difference between a close
    /// under test and a close that happens because a local went out of scope.
    static func keep(_ controller: SettingsWindowController) {
        guard !controllers.contains(where: { $0 === controller }) else { return }
        controllers.append(controller)
    }
}

/// The real `show()` — activation, ordering front and all — plus the one thing a
/// process with no `NSApplication.run()` owes a window it opens. See
/// `LiveWindows`.
@MainActor private func showKeepingTheWindowAlive(_ controller: SettingsWindowController) {
    controller.show()
    LiveWindows.keep(controller)
    LiveWindows.keep(controller.windowForTesting)
}

@Test @MainActor func showingTwiceReusesTheOneWindow() {
    // The gear is the only door. Two windows means two views of one truth, and
    // the second one silently wins whatever it writes last.
    let c = SettingsWindowController(store: InMemoryPreferenceStore())
    showKeepingTheWindowAlive(c)
    let first = c.windowForTesting
    showKeepingTheWindowAlive(c)
    #expect(c.windowForTesting === first, "show() built a second window")
}

@Test @MainActor func showingTheWindowPutsItOnScreenRatherThanMerelyBuildingIt() {
    // `show()` is two things — build the window, and present it — and every
    // other test in this file passes against a `show()` that only built one.
    // This is the assertion that notices the presenting half going missing.
    //
    // `isVisible` because it is the one signal here that is not a void reading:
    // measured, a window that has only been constructed reads `false`, and the
    // same window after `makeKeyAndOrderFront(nil)` reads `true` — with the
    // display awake, with it asleep, and on a locked screen alike.
    //
    // **`NSApp.activate()` has no such signal and is asserted by nothing.**
    // Deleting that line leaves this entire suite green (measured), and it is
    // reported here rather than covered by something weaker: this file's own
    // production comment records `NSApp.isActive` reading `true` while focus
    // demonstrably stayed elsewhere *and* `false` with a window visibly ordered
    // front, and `keyWindow`/`frontmostApplication` are void under a lock.
    // `--settings-focus-probe` is what answers that one, on a real screen.
    let c = SettingsWindowController(store: InMemoryPreferenceStore())
    showKeepingTheWindowAlive(c)
    #expect(c.windowForTesting?.isVisible == true,
            "show() built the window but never ordered it on screen")
}

@Test @MainActor func theWindowCarriesTheTitleTheProtoypeGivesIt() {
    let c = SettingsWindowController(store: InMemoryPreferenceStore())
    showKeepingTheWindowAlive(c)
    #expect(c.windowForTesting?.title == "VibeCat Settings")
}

@Test @MainActor func closingTheWindowLetsItGo() {
    // The lifecycle rule this repo learned the hard way twice.
    let c = SettingsWindowController(store: InMemoryPreferenceStore())
    showKeepingTheWindowAlive(c)
    #expect(c.isOpen)
    c.windowForTesting?.performClose(nil)
    #expect(!c.isOpen, "the controller still thinks a closed window is open")
}

@Test @MainActor func theWindowOpensOnThePageThatWasStored() {
    let store = InMemoryPreferenceStore(Preferences(selectedPage: "display"))
    let c = SettingsWindowController(store: store)
    showKeepingTheWindowAlive(c)
    #expect(c.selectedPageForTesting == "display")
}

@Test @MainActor func anUnknownStoredPageStillOpensSomething() {
    // The store clamps this, but the window must not depend on that to avoid
    // showing an empty content area. Two layers, deliberately.
    //
    // Note on the plan's own prediction (Task 5, mutation 4): it says removing
    // the window's fallback leaves this green because `load()` clamps. That is
    // true of `UserDefaultsPreferenceStore.load()` and **not** of the store this
    // test actually uses — `InMemoryPreferenceStore.load()` hands back exactly
    // what it was given, unclamped (`PreferenceStore.swift:83`). So the only
    // clamp between `Preferences(selectedPage: "kitchen-sink")` and the window
    // here is the window's own, and this does catch mutation 4. Verified by
    // running it; see this task's report.
    let store = InMemoryPreferenceStore(Preferences(selectedPage: "kitchen-sink"))
    let c = SettingsWindowController(store: store)
    showKeepingTheWindowAlive(c)
    #expect(SettingsPageKey.isKnown(c.selectedPageForTesting))
}

@Test @MainActor func reopeningAfterACloseIsSafeAndBuildsAFreshWindow() {
    // The other half of `closingTheWindowLetsItGo`: that flag going stale and
    // the window itself being reused are different defects, and only this one
    // fails if `show()` hands back a window that was already closed.
    //
    // It was written expecting to also catch `isReleasedWhenClosed = false`
    // being removed, and it does not — a controller that has already dropped
    // its reference builds a fresh window either way, so this test cannot tell
    // a released window from a leaked one. That gap is now covered by
    // `aClosedWindowIsAppKitsToReleaseRatherThanOursToKeepForever` below, which
    // asserts the flag AppKit acts on rather than watching the window go; the
    // line itself is gone, because measuring it showed it leaked one window per
    // close rather than preventing a double release (see `makeWindow()`'s own
    // comment).
    //
    // The second window this builds is retained too, and has to be: both of them
    // deallocating is two chances at the crash `LiveWindows` describes, not one.
    let c = SettingsWindowController(store: InMemoryPreferenceStore())
    showKeepingTheWindowAlive(c)
    let first = c.windowForTesting
    c.windowForTesting?.performClose(nil)
    showKeepingTheWindowAlive(c)
    #expect(c.isOpen)
    #expect(c.windowForTesting !== first, "a closed window was reused after release")
}

@Test @MainActor func aClosedWindowIsAppKitsToReleaseRatherThanOursToKeepForever() {
    // The invariant `CLAUDE.md` states as "anything with a lifecycle tears
    // itself down", applied to the one object in this file that AppKit — not
    // ARC — owns. An `LSUIElement` app runs for the whole login session and its
    // Settings window sits behind a gear someone can press any number of times,
    // so one `NSWindow` retained per open/close is unbounded growth.
    //
    // **This test used to watch the leak directly — the window leaving
    // `NSApp.windows` after a close — and that form cannot be used any more.**
    // `NSApp.windows` drops a window when it *deallocates*, not when it closes
    // (measured: with `isReleasedWhenClosed = false` a closed window stays in
    // the list, which is exactly how the old form detected the leak), and a
    // titled `NSWindow` deallocating in a process that never called
    // `NSApplication.run()` segfaults the run — see `LiveWindows` above for the
    // measurements. The observation and the crash were the same event: the only
    // way this test could watch the window die was to kill the test process
    // doing it, 5 runs out of 5.
    //
    // So what is asserted now is the production decision itself, where it lives,
    // and the narrowing is written down rather than hidden. This catches
    // `window.isReleasedWhenClosed = false` coming back — the exact line Task 5
    // shipped, that `makeWindow()`'s comment forbids and that measurement showed
    // leaks one window per close — and it catches nothing else. A weak reference
    // cannot stand in for it either, for the reason that comment already
    // records: AppKit finishes tearing a closed window down inside
    // `NSApplication.run()`, so "is it deallocated yet" has no stable answer in
    // this process.
    let c = SettingsWindowController(store: InMemoryPreferenceStore())
    showKeepingTheWindowAlive(c)
    #expect(c.windowForTesting?.isReleasedWhenClosed == true,
            "the Settings window is set not to release itself on close — one NSWindow then accumulates for the process's whole life, per open/close, in an app that runs for the whole login session")
}

@Test @MainActor func theWindowHostsSwiftUIRatherThanAnEmptyContentView() {
    // Nothing else in this file reads `contentView` at all, so without this the
    // whole hosting line could be deleted and every other test here would stay
    // green — the window would open, be titled, close and let go, showing
    // nothing. Keyed on the hosted *type*, following `NotchController.present`'s
    // own once-only guard, so replacing `SettingsRootView` with something else
    // in Task 6 is a deliberate edit here rather than a silent pass.
    let c = SettingsWindowController(store: InMemoryPreferenceStore())
    showKeepingTheWindowAlive(c)
    #expect(c.windowForTesting?.contentView is NSHostingView<SettingsRootView>)
}

@Test @MainActor func theTrafficLightsThePrototypeDrawsAreRealOnes() {
    // `settings.html:200` draws three lights; the plan's instruction is to use a
    // real titlebar rather than paint one. A borderless window would pass every
    // other test in this file — `title` is settable on any window and
    // `performClose` is what `closingTheWindowLetsItGo` drives — so this is the
    // only assertion that would notice the style mask being dropped. Read
    // through the buttons rather than the mask because it is the buttons that
    // are the prototype's three lights.
    let c = SettingsWindowController(store: InMemoryPreferenceStore())
    showKeepingTheWindowAlive(c)
    let window = c.windowForTesting
    #expect(window?.standardWindowButton(.closeButton) != nil)
    #expect(window?.standardWindowButton(.miniaturizeButton) != nil)
    #expect(window?.standardWindowButton(.zoomButton) != nil)
}

@Test @MainActor func theWindowIsTheSizeTheProtoypeGivesItsBody() {
    // `settings.html:40` — `.win{width:min(900px,100%)}` — and `:50`,
    // `.body{min-height:620px}`. The body is the content area: the prototype's
    // 44pt `.titlebar` is a real titlebar here, which lives outside
    // `contentRect`. Asserted on the content view's own size rather than
    // `frame`, so a future titlebar-height change cannot quietly shrink the
    // panes to keep a total constant.
    let c = SettingsWindowController(store: InMemoryPreferenceStore())
    showKeepingTheWindowAlive(c)
    let size = c.windowForTesting?.contentView?.frame.size
    #expect(size?.width == 900)
    #expect(size?.height == 620)
}

// MARK: - the page the window reopens on

@Test @MainActor func choosingAPageStoresItSoTheWindowReopensThere() {
    // `Preferences.selectedPage`'s whole stated reason to exist — "the window has
    // to reopen where you left it" — did not work: Task 1 created the key, Task 5
    // read it, and no task wrote it. `grep -rn "\.save(" Sources/` returned one hit
    // and it was `NotchController.toggleMute()`.
    //
    // Driven through `model.pageBinding`, which is the *same* binding
    // `SettingsRootView` hands `SettingsShell` and therefore the sidebar — not a
    // parallel `select…ForTesting()` that only resembles it. What this still cannot
    // prove is that `body` passes that binding rather than a `.constant`; that is
    // the closure-identity gap `PanelBarTests
    // .tappingEachButtonCallsItsOwnClosureAndNotTheOther` records, and it is
    // reported rather than papered over — the mutation
    // `SettingsShell(selection: .constant(model.selectedPage))` stays green here.
    let store = InMemoryPreferenceStore()
    let c = SettingsWindowController(store: store)
    showKeepingTheWindowAlive(c)
    c.modelForTesting.pageBinding.wrappedValue = "display"
    #expect(c.selectedPageForTesting == "display", "the binding did not reach the model")
    #expect(store.load().selectedPage == "display", "the chosen page was never persisted")

    // The consequence, spelled out: a second window built on the same store opens
    // where the first one was left. This is the assertion that would still fail if
    // `selectPage` wrote some *other* key correctly.
    #expect(SettingsWindowController(store: store).selectedPageForTesting == "display")
}

@Test @MainActor func storingThePageDoesNotClobberASettingChangedElsewhere() {
    // `PreferenceStore.save(_:)` writes the whole struct, and there is a second
    // writer: `NotchController.toggleMute()`, reachable from the island's footer
    // while this window is open. If the page write went through a `Preferences`
    // this controller had snapshotted at init, it would silently undo the mute.
    //
    // So: mute happens *after* the controller is built, then a page is chosen.
    // Both must survive. Mutating `persist` to build a fresh `Preferences(
    // selectedPage: key)`, or to close over a snapshot taken in `init`, fails
    // exactly this.
    let store = InMemoryPreferenceStore()
    let c = SettingsWindowController(store: store)
    var muted = store.load()
    muted.soundEnabled = false
    muted.volume = 0.15
    store.save(muted)

    c.modelForTesting.pageBinding.wrappedValue = "integrations"
    let after = store.load()
    #expect(after.selectedPage == "integrations")
    #expect(after.soundEnabled == false, "storing the page reset soundEnabled")
    #expect(after.volume == 0.15, "storing the page reset volume")
}

@Test @MainActor func reselectingTheCurrentPageWritesNothing() {
    // `@Observable` notifies on the write, not on the change — CLAUDE.md's own
    // rule, and `AppModel.prune` is the precedent. A sidebar row is clickable when
    // it is already current, so without the guard every such click invalidates
    // every body reading the selection and writes the plist.
    //
    // Counted through a store that records, because "did it write" is invisible
    // from a value-equal `Preferences`.
    final class CountingStore: PreferenceStoring {
        let inner = InMemoryPreferenceStore()
        nonisolated(unsafe) var saves = 0
        func load() -> Preferences { inner.load() }
        func save(_ preferences: Preferences) { saves += 1; inner.save(preferences) }
    }
    let store = CountingStore()
    let c = SettingsWindowController(store: store)
    c.modelForTesting.pageBinding.wrappedValue = "general"   // already the default
    #expect(store.saves == 0, "re-selecting the current page wrote the plist")
    c.modelForTesting.pageBinding.wrappedValue = "display"
    #expect(store.saves == 1)
}
