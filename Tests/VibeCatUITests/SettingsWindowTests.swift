import Testing
import Foundation
import AppKit
import SwiftUI
import VibeCatCore
@testable import VibeCatUI

@Test @MainActor func showingTwiceReusesTheOneWindow() {
    // The gear is the only door. Two windows means two views of one truth, and
    // the second one silently wins whatever it writes last.
    let c = SettingsWindowController(store: InMemoryPreferenceStore())
    c.show()
    let first = c.windowForTesting
    c.show()
    #expect(c.windowForTesting === first, "show() built a second window")
}

@Test @MainActor func theWindowCarriesTheTitleTheProtoypeGivesIt() {
    let c = SettingsWindowController(store: InMemoryPreferenceStore())
    c.show()
    #expect(c.windowForTesting?.title == "VibeCat Settings")
}

@Test @MainActor func closingTheWindowLetsItGo() {
    // The lifecycle rule this repo learned the hard way twice.
    let c = SettingsWindowController(store: InMemoryPreferenceStore())
    c.show()
    #expect(c.isOpen)
    c.windowForTesting?.performClose(nil)
    #expect(!c.isOpen, "the controller still thinks a closed window is open")
}

@Test @MainActor func theWindowOpensOnThePageThatWasStored() {
    let store = InMemoryPreferenceStore(Preferences(selectedPage: "display"))
    let c = SettingsWindowController(store: store)
    c.show()
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
    c.show()
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
    // `closingTheWindowTakesItOutOfTheApplicationsWindowList` below, which asks
    // whether AppKit still holds it rather than whether we do; the line itself is
    // gone, because
    // measuring it showed it leaked one window per close rather than preventing
    // a double release (see `makeWindow()`'s own comment).
    let c = SettingsWindowController(store: InMemoryPreferenceStore())
    c.show()
    let first = c.windowForTesting
    c.windowForTesting?.performClose(nil)
    c.show()
    #expect(c.isOpen)
    #expect(c.windowForTesting !== first, "a closed window was reused after release")
}

@Test @MainActor func closingTheWindowTakesItOutOfTheApplicationsWindowList() {
    // The invariant `CLAUDE.md` states as "anything with a lifecycle tears
    // itself down", applied to the one object in this file that AppKit — not
    // ARC — owns. An `LSUIElement` app runs for the whole login session and its
    // Settings window sits behind a gear someone can press any number of times,
    // so one `NSWindow` retained per open/close is unbounded growth.
    //
    // **Identity, not a count, and not a weak reference.** A count would be
    // wrong because `NSApp.windows` is process-global and this suite runs in
    // parallel — every other test in this file builds a window titled "VibeCat
    // Settings". Asking whether *our own* window is still listed is unaffected
    // by any of them.
    //
    // A weak reference was tried first and does not work here, which is worth
    // recording because it looks like the obvious test. Measured: with
    // `isReleasedWhenClosed` at its default, ten open/close cycles leave
    // `NSApp.windows` at 0 — but all ten `NSWindow` objects are still alive with
    // a retain count of 8 each, after 50 run-loop spins. AppKit finishes tearing
    // a closed window down inside `NSApplication.run()`, which `swift test`
    // never calls, so "is it deallocated yet" has no stable answer in this
    // process. "Is it still in the window list" does, and it is the thing that
    // grows without bound: with `window.isReleasedWhenClosed = false` restored,
    // the same ten cycles take `NSApp.windows` from 0 to 10 with all ten still
    // titled "VibeCat Settings", and this test fails on the first one.
    let app = NSApplication.shared
    let c = SettingsWindowController(store: InMemoryPreferenceStore())
    c.show()
    let opened = c.windowForTesting
    #expect(opened != nil && app.windows.contains { $0 === opened },
            "an open window that is not in NSApp.windows means this test cannot detect a leak either")
    c.windowForTesting?.performClose(nil)
    #expect(!app.windows.contains { $0 === opened },
            "the closed window is still in NSApp.windows — one NSWindow accumulates there per open/close, for the process's whole life")
}

@Test @MainActor func theWindowHostsSwiftUIRatherThanAnEmptyContentView() {
    // Nothing else in this file reads `contentView` at all, so without this the
    // whole hosting line could be deleted and every other test here would stay
    // green — the window would open, be titled, close and let go, showing
    // nothing. Keyed on the hosted *type*, following `NotchController.present`'s
    // own once-only guard, so replacing `SettingsRootView` with something else
    // in Task 6 is a deliberate edit here rather than a silent pass.
    let c = SettingsWindowController(store: InMemoryPreferenceStore())
    c.show()
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
    c.show()
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
    c.show()
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
    c.show()
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
