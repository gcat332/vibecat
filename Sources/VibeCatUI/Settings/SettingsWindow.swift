import AppKit
import Observation
import SwiftUI
import VibeCatCore

/// Everything the Settings window's view tree reads, in one observable place —
/// the same shape, and for the same reason, as `IslandModel`: the hosting view's
/// root is assigned once and reads this, rather than a fresh SwiftUI tree being
/// pushed into `rootView` on every change.
///
/// It is a separate object from `SettingsWindowController` rather than the
/// controller itself being `@Observable`, and that is not stylistic. The window
/// retains its `contentView`, the hosting view retains its `rootView`, and the
/// controller retains the window — so a root view holding the *controller* would
/// close the loop into a retain cycle that nothing breaks, including the
/// `isolated deinit` below, which would never run. Holding the model instead
/// leaves the graph acyclic: controller → model ← view ← window ← controller has
/// exactly one arrow pointing back, and it is the one the controller can drop.
@MainActor @Observable final class SettingsWindowModel {
    /// A page *key*, never an index — see `Preferences.selectedPage`. Clamped by
    /// the controller's initialiser on the way in; written afterwards only through
    /// `selectPage(_:)`, so that every change is also persisted.
    var selectedPage: String

    /// What to do with a page the user has just moved to. A closure rather than a
    /// `PreferenceStoring`, because this type has no other business with the store
    /// and a closure is what lets a test see the write without a second store.
    private let persist: (String) -> Void

    init(selectedPage: String, persist: @escaping (String) -> Void = { _ in }) {
        self.selectedPage = selectedPage
        self.persist = persist
    }

    /// The sidebar's and the panes' one handle on the selection — and the reason
    /// `SettingsRootView` no longer uses `@Bindable`.
    ///
    /// `$model.selectedPage` writes straight to the stored property, which is
    /// exactly why the page was persisted by nothing: there was no seam between
    /// "the sidebar changed the selection" and "the selection was stored". Routing
    /// the setter through `selectPage(_:)` puts one there without the sidebar
    /// learning what a `PreferenceStoring` is.
    var pageBinding: Binding<String> {
        Binding(get: { self.selectedPage }, set: { self.selectPage($0) })
    }

    /// Moves to a page and stores it.
    ///
    /// The guard is not an optimisation: `@Observable` notifies on the *write*,
    /// not on the change, so re-selecting the current page would invalidate every
    /// body reading it and write the plist for nothing.
    func selectPage(_ key: String) {
        guard key != selectedPage else { return }
        selectedPage = key
        persist(key)
    }
}

/// The Settings window's content, hosted once.
///
/// Task 6 filled the interior in, and it landed exactly where Task 5 predicted:
/// as an edit inside this `body` rather than as a change to the hosted *type*.
/// That distinction has already cost this repo once —
/// `NotchController.present`'s once-only hosting guard keys on
/// `NSHostingView<IslandView>`, the type, so anything that changes the hosted
/// type silently changes what "already hosted" means, and
/// `theWindowHostsSwiftUIRatherThanAnEmptyContentView` keys on this one.
///
/// All this view does is bridge the observable model to a plain `Binding`, so
/// everything below it — `SettingsShell`, the sidebar, the panes — is a pure
/// function of a `String` and can be rasterised without a window. The binding
/// comes from the model rather than from `@Bindable`, so that a write goes through
/// `SettingsWindowModel.selectPage(_:)` and gets persisted — see that method.
struct SettingsRootView: View {
    /// Read by the sidebar and the panes. Held here for the reason in
    /// `SettingsWindowModel`'s doc comment.
    let model: SettingsWindowModel

    var body: some View {
        // `model.pageBinding`, not `@Bindable`'s `$model.selectedPage` — see that
        // property's own doc comment. The read direction is identical; the write
        // direction is what changed, and it is the direction that was missing.
        SettingsShell(selection: model.pageBinding)
    }
}

/// The one Settings window, and the guarantee that there is only ever one.
///
/// **`LSUIElement` is the whole problem.** `main.swift` sets
/// `.accessory` activation policy, so this app has no Dock icon and no menu bar
/// of its own: there is no App menu to hang a `Settings…` item on, no
/// `NSApplicationDelegate` reopen callback to catch, and no SwiftUI `Settings`
/// scene to lean on (that one needs a `SwiftUI.App` lifecycle, which the notch
/// panel's AppKit ownership rules out anyway). The drawer's gear is the only
/// door. Everything below follows from that: `show()` has to be idempotent
/// because it is called from a button someone can press twice, and it has to
/// raise a window that may already exist behind another app.
///
/// **On focus.** Plan 5's key-input spike settled Path A for the *panel* — it
/// takes key status without ever changing `frontmostApplication`, because a
/// click on the island must not interrupt what someone is typing into. A
/// Settings window is the opposite case: an ordinary window someone deliberately
/// asked for, which is useless if it cannot take keystrokes. So this one *does*
/// call `NSApp.activate()`, deliberately, and is *expected* to become
/// frontmost.
///
/// **What that actually does to `NSWorkspace.shared.frontmostApplication` is
/// not measured, and this comment will not pretend otherwise.** The attempt is
/// recorded: run from the real binary through the gear's own closure, the window
/// was created and listed visible (`isOpen=true`, `NSApp.windows` carrying
/// `VibeCat Settings:visible=true`), while `frontmost` read `loginwindow` and
/// `keyWindow` read `nil` on every line — because this machine's screen was
/// locked (`CGSSessionScreenIsLocked=Yes`, read from `ioreg`, not assumed), and
/// under a lock no window anywhere can become key or frontmost. That is a void
/// reading, the same trap that already put one wrong fact into this project's
/// record. `SettingsFocusProbe` (`--settings-focus-probe`) exists to answer it
/// in one command on an unlocked screen, and refuses to report at all when it
/// sees `loginwindow`.
///
/// Note that `NSApp.isActive` is **not** evidence either way. Plan 5's spike read
/// it `true` in every run while focus demonstrably stayed elsewhere; the locked
/// run above read it `false` with a window visibly ordered front.
@MainActor public final class SettingsWindowController {
    private let store: PreferenceStoring

    /// Built in `init` and never rebuilt, so a window closed and reopened within
    /// one session comes back on the page it was left on. The stored page is
    /// read exactly once, here — deliberately not also on every `show()`, which
    /// would put two clamped reads of one fact in two places and let a mutation
    /// to either survive `theWindowOpensOnThePageThatWasStored`.
    private let model: SettingsWindowModel

    private var window: NSWindow?

    /// `NSWindow.willCloseNotification`, scoped to *our* window, rather than
    /// `NSWindowDelegate`. Two reasons: this file already needs a token it can
    /// remove in `deinit` (the same shape as `NotchController`'s
    /// screen-parameters observer), and a delegate would make this class an
    /// `NSObject` subclass for one callback. Removed both on close and in
    /// `deinit`, because a block-based observer outlives the object it captures
    /// unless something removes it.
    private var closeObserver: NSObjectProtocol?

    public init(store: PreferenceStoring) {
        self.store = store
        let stored = store.load().selectedPage
        // Two layers of clamping on purpose, and this is the outer one.
        // `UserDefaultsPreferenceStore.load()` already rejects an unknown key,
        // but "which pane is showing" is this file's own invariant: an unknown
        // key here is not a stale plist, it is a window with a sidebar
        // selecting nothing and an empty content area — the one failure a
        // person would see. The fallback is `Preferences`' own default rather
        // than a second `"general"` literal, so the default page stays one
        // fact in one place.
        //
        // **Read-modify-write against the value as it is right now, never against
        // a snapshot this object is holding.** `PreferenceStore.save(_:)` writes
        // the whole struct, so two surfaces that each `load()` once, mutate their
        // own field and `save()` later would have the second write silently drop
        // the first — and there already is a second writer, `NotchController
        // .toggleMute()`, which someone can use from the island's footer while
        // this window is open. Loading inside the closure means the only thing
        // this write can be stale about is a change made between the `load()` and
        // the `save()` on this same actor, which is nothing. Plans 6.5-6.7 add
        // more writers; every one of them needs this shape (or a per-key write)
        // rather than a view model holding a `Preferences` it saves back wholesale.
        //
        // `store`, the parameter, is captured rather than `self` — the closure
        // outlives this initialiser and a captured `self` would retain the
        // controller through its own model.
        self.model = SettingsWindowModel(
            selectedPage: SettingsPageKey.isKnown(stored) ? stored : Preferences().selectedPage,
            persist: { key in
                var prefs = store.load()
                prefs.selectedPage = key
                store.save(prefs)
            })
    }

    /// Whether a window exists at all — not whether it is on screen.
    ///
    /// `window != nil` is the honest reading of what this class guarantees:
    /// `show()` creates at most one window and the close observer drops it, so
    /// this is exactly "is there a Settings window to bring forward". Reading
    /// `isVisible` instead would make the answer depend on a window server.
    public var isOpen: Bool { window != nil }

    /// Opens the window, or brings the existing one forward. Idempotent.
    public func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        // An accessory app is not frontmost when its own button is clicked —
        // the click went to a panel that deliberately never activates. Without
        // this the window orders front but behind the active app's windows and
        // never becomes key, so it cannot be typed into. `NSApplication.activate()`
        // (macOS 14+), not the deprecated `activate(ignoringOtherApps:)`.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// The live window, for `SettingsWindowTests` only — internal, not `public`,
    /// following `NotchController.panelForTesting` (plain module visibility, not
    /// `#if DEBUG`, which is this repo's established precedent for a test hook).
    /// `show()` builds a real `NSWindow` in the test process, and this is what
    /// lets a test observe that the second `show()` did not build a second one.
    var windowForTesting: NSWindow? { window }

    /// The page the window opened on — same visibility reasoning as
    /// `windowForTesting`. Non-optional because the model outlives the window:
    /// there is always an answer to "which page", even before the first `show()`.
    var selectedPageForTesting: String { model.selectedPage }

    /// The live model, for `SettingsWindowTests` only — same visibility reasoning
    /// as `windowForTesting`. This is what lets a test drive the *write* direction
    /// (`modelForTesting.pageBinding.wrappedValue = ...`) through the very binding
    /// `SettingsRootView` hands the sidebar, rather than through a parallel path
    /// that only resembles it.
    var modelForTesting: SettingsWindowModel { model }

    private func makeWindow() -> NSWindow {
        // `settings.html:50` — `.body{min-height:620px}` — and `:40`,
        // `.win{width:min(900px,100%)}`. The prototype's 44pt `.titlebar` is
        // *not* part of this rect: it is a real titlebar, which AppKit puts
        // above the content area.
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.contentSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        // `settings.html:201`. A real title in a real titlebar with the real
        // three lights, rather than a borderless window with a drawn one —
        // `.titled` is what makes `performClose`, window dragging, Mission
        // Control and the zoom button behave the way every other window does.
        window.title = "VibeCat Settings"

        // **`isReleasedWhenClosed` is deliberately left at AppKit's own default
        // of `true`, and this comment exists so nobody sets it to `false`
        // again.** Task 5 did, reasoning that this class holds a strong
        // reference and clears it in the close observer below, so AppKit's
        // release would be a *second* one and a close would be a
        // use-after-free.
        //
        // **That reasoning is inverted, and the measurement says so.**
        // `NSWindow.willCloseNotification` is posted *before* the close
        // completes, so `windowDidClose()`'s `window = nil` runs first and
        // AppKit's release is the one that balances its own window-list
        // retain — not a second release of a reference this class still holds.
        // With `false`, nothing balances it at all: ten `show()`/
        // `performClose(nil)` cycles through one controller, inside an
        // `autoreleasepool` and followed by a two-second run-loop drain, took
        // `NSApp.windows` from 0 to 10 with all ten still titled "VibeCat
        // Settings" and all ten weak references still live — one `NSWindow`
        // leaked per open/close, permanently, in an `LSUIElement` app that runs
        // for the whole login session. At the default the same probe reads
        // 0 -> 10 -> 0 with every weak reference nil and no crash.
        //
        // `aClosedWindowIsAppKitsToReleaseRatherThanOursToKeepForever` in
        // `SettingsWindowTests` holds this — by asserting this flag rather than
        // by watching the window die, and **that is not timidity, it is the only
        // form available.** A titled `NSWindow` that actually deallocates in a
        // process which never called `NSApplication.run()` segfaults that
        // process: AppKit starts an animation for the window's chrome and only
        // retires it inside `run()`, so in `swift test` it outlives the window
        // and its `dealloc` releases freed memory — `SIGSEGV` inside
        // `-[_NSWindowTransformAnimation dealloc]`, off
        // `CA::Transaction::commit()`, 5 runs out of 5 with the display awake.
        // Every measurement behind that sentence is recorded on `LiveWindows` in
        // `SettingsWindowTests`, including the two things it is *not*
        // (presentation, and any of this window's own configuration).
        //
        // **Nothing here needs changing for it, and nothing here should be.**
        // The real app calls `NSApplication.run()`, so the animation completes
        // long before any close and this window is released exactly as intended.
        // The hazard belongs to the test process alone, which is where it is
        // handled.

        // The prototype is a dark sheet, and this app has no light variant to
        // switch to — pinning the appearance rather than following the system
        // keeps the real titlebar's own chrome (which is drawn by AppKit, not
        // by us) in the same family as `--chrome` below instead of turning
        // white around a `#1C1C1E` body under Light Mode.
        window.appearance = NSAppearance(named: .darkAqua)
        // `settings.html:11`, `--chrome:#232326`, aimed at a real titlebar.
        // `titlebarAppearsTransparent` makes the titlebar draw no material of
        // its own so the window's background shows through the strip, which is
        // the documented way to give a titlebar an exact colour without
        // drawing one.
        //
        // **How close it lands is unverified on screen, and the offscreen
        // capture that would answer it is not trustworthy here.** Measured:
        // `cacheDisplay` on the window's frame view read the strip as `#2E2E32`
        // with this flag and `#282828` without, against a target of `#232326` —
        // but the same capture read the *content* area as `#252528` where the
        // hosting view paints `#1C1C1E`, so it is not seeing what the window
        // server composites and neither strip figure means anything absolute.
        // A real check needs an unlocked screen; Task 6's prototype-fidelity
        // pass is where it belongs, and this is recorded so that pass has the
        // question rather than having to rediscover it.
        //
        // Two divergences from `settings.html` follow from using a real
        // titlebar at all, and both are decisions rather than misses:
        // `.titlebar`'s `height:44px` is AppKit's own instead — **measured at
        // 32pt** here (a 620pt content area inside a 652pt frame view) — and
        // `.win`'s `border-radius:12px` plus `1px solid var(--line)` are the
        // browser standing in for window chrome this window gets for free.
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(srgbRed: CGFloat(SettingsPalette.chrome.r),
                                         green: CGFloat(SettingsPalette.chrome.g),
                                         blue: CGFloat(SettingsPalette.chrome.b),
                                         alpha: 1)
        // Resizable, because `.win`'s own `min(900px,100%)` says the layout is
        // meant to give — but never below the prototype's own measurements,
        // which is where the four panes' content stops fitting.
        window.contentMinSize = Self.contentSize
        window.center()
        window.contentView = NSHostingView(rootView: SettingsRootView(model: model))

        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.windowDidClose() }
            }
        return window
    }

    /// Drops the window the moment it closes, which is what makes `isOpen`
    /// honest and what releases the hosting view — and with it the SwiftUI
    /// observation registered against `model`. The next `show()` builds a fresh
    /// window; nothing tries to reopen a closed one, because AppKit's own
    /// close/reopen behaviour for a released window is not something to rely on.
    private func windowDidClose() {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        window?.contentView = nil
        window = nil
    }

    /// The same defect class already hardened on `AppModel`, `HoverMonitor` and
    /// `NotchController`: a block-based `NotificationCenter` observer keeps
    /// firing, holding its own closure, for the rest of the process unless it is
    /// explicitly removed — regardless of what happens to this instance. A
    /// controller dropped while its window is still open would otherwise leak
    /// that registration, the window, the hosting view and the model.
    ///
    /// `isolated deinit`, like the other three, so this can touch main-actor
    /// state at all. `close()` posts `willCloseNotification` synchronously and
    /// the observer's `[weak self]` is already `nil` inside `deinit`, so the
    /// notification lands on nothing rather than re-entering this object.
    isolated deinit {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        window?.contentView = nil
        window?.close()
        window = nil
    }

    /// `settings.html:40` and `:50`. The content area, titlebar excluded.
    static let contentSize = CGSize(width: 900, height: 620)
}
