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
    /// A page *key*, never an index — see `Preferences.selectedPage`. Always one
    /// of `SettingsPageKey.all`: the only writer today is the controller's
    /// initialiser, which clamps.
    var selectedPage: String

    init(selectedPage: String) {
        self.selectedPage = selectedPage
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
/// function of a `String` and can be rasterised without a window. `@Bindable` on
/// a local, rather than the property itself, because the model is a `let`: the
/// controller owns it and this view must not be the thing that keeps it alive
/// (see `SettingsWindowModel`'s own note on the retain cycle that would close if
/// the *controller* were what a root view held).
struct SettingsRootView: View {
    /// Read by the sidebar and the panes. Held here for the reason in
    /// `SettingsWindowModel`'s doc comment.
    let model: SettingsWindowModel

    var body: some View {
        @Bindable var model = model
        SettingsShell(selection: $model.selectedPage)
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
        self.model = SettingsWindowModel(
            selectedPage: SettingsPageKey.isKnown(stored) ? stored : Preferences().selectedPage)
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

        // ARC and AppKit disagree about who owns a window, and the default is
        // AppKit's answer: an `NSWindow` created in code is
        // `isReleasedWhenClosed == true`. This class holds a strong reference
        // and clears it in the close observer below, which is one release; the
        // AppKit behaviour is a second one, so on paper leaving this at its
        // default makes a close a use-after-free rather than a leak.
        //
        // **Unverified, and deliberately labelled as such.** Deleting this line
        // leaves every test in `SettingsWindowTests` green, close-then-reopen
        // included — measured, not assumed (Task 5's report, mutation 5). So
        // either the extra release is balanced by a retain this process cannot
        // see, or the crash needs a run loop that `swift test` never pumps.
        // The line stays because it is the documented contract for an
        // ARC-held window and because the failure mode it prevents is a crash
        // in someone's Settings window, not because anything here proves it.
        window.isReleasedWhenClosed = false

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
