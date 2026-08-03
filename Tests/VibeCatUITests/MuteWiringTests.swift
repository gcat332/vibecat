import Testing
import Foundation
import SwiftUI
import VibeCatCore
@testable import VibeCatUI

/// Plan 6.4 Task 4: "mute, end to end" — `island-motion.html:1060`'s coupling
/// ("the panel's mute button and the app's sound toggle are the same
/// setting") means there is exactly one value, `Preferences.soundEnabled`,
/// read on both surfaces. This file has two layers of test, deliberately
/// distinct:
///
/// 1. **The four tests the plan itself specifies** (`mutingStopsACueFrom
///    RenderingAtAll` through `aStoredMuteIsHonouredOnTheNextLaunch`) —
///    these exercise `SoundPlayer`/`SoundSettings`/`InMemoryPreferenceStore`
///    directly, with no `NotchController` or view in sight.
/// 2. **The wiring tests below them** — the plan's own mutation 2 predicts
///    that having `PanelBar` hold its own `@State` for `muted` would *not*
///    break test group 1 (confirmed: see the mutation-verify note above
///    `toggleMuteReachesThePreferenceStoreThroughNotchController`), because
///    none of those four tests touches anything a UI tap would actually
///    reach. The tests in group 2 close as much of that gap as this
///    project's own conventions allow — see each one's own comment for
///    exactly what it does and does not prove.
private func fixtureMetrics() -> ScreenMetrics {
    ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                  visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
                  safeAreaTop: 32,
                  auxLeft: CGRect(x: 0, y: 950, width: 663, height: 32),
                  auxRight: CGRect(x: 848, y: 950, width: 664, height: 32))
}

@MainActor private func makeController(store: PreferenceStoring) -> (NotchController, AppModel) {
    let model = AppModel(socketPath: "/tmp/vibecat-mutewiring-unused.sock")
    let c = NotchController(model: model, metrics: { fixtureMetrics() }, preferences: store)
    c.refreshGeometry()
    c.present()
    return (c, model)
}

// MARK: - The plan's own four tests

@Test @MainActor func mutingStopsACueFromRenderingAtAll() {
    // Not "plays quietly" — renders nothing. A muted app that still spends
    // 860ms rendering a buffer it throws away is the defect here.
    let store = InMemoryPreferenceStore(Preferences(soundEnabled: false))
    let player = SoundPlayer(settings: SoundSettings(enabled: store.load().soundEnabled),
                             quietHours: NeverQuiet())
    #expect(player.buffer(for: .ask) == nil)
}

@Test @MainActor func unmutingMakesTheVerySameCueRenderAgain() {
    // Two players differing in exactly one input.
    let player = SoundPlayer(settings: SoundSettings(enabled: true), quietHours: NeverQuiet())
    #expect(player.buffer(for: .ask) != nil)
}

@Test func togglingMuteFromTheIslandPersists() {
    // The coupling island-motion.html:1060 states. If the bar keeps its own
    // copy, the Settings sheet 6.5 builds will disagree with it.
    //
    // **Mutation-verify finding, reported rather than patched around** (the
    // plan's own predicted mutation 2): giving `PanelBar` a private `@State`
    // for `muted` instead of reading `IslandModel.muted`/calling
    // `onToggleMute` does **not** break this test, tried directly against
    // `PanelBar.swift` and reverted. It cannot: this test never constructs a
    // `PanelBar`, a `DrawerView`, or a `NotchController` — it only exercises
    // `InMemoryPreferenceStore`, which a UI-level regression can never touch.
    // The plan predicted exactly this and asked for it to be said plainly
    // rather than left implying coverage that isn't there. See
    // `toggleMuteReachesThePreferenceStoreThroughNotchController` below for
    // the strengthened test this finding calls for, and its own comment for
    // what even that one still cannot prove.
    let store = InMemoryPreferenceStore(Preferences(soundEnabled: true))
    var prefs = store.load()
    prefs.soundEnabled = false
    store.save(prefs)
    #expect(store.load().soundEnabled == false)
}

@Test @MainActor func aStoredMuteIsHonouredOnTheNextLaunch() {
    // The whole point of persistence: mute at 2am, still muted at 9am.
    let store = InMemoryPreferenceStore(Preferences(soundEnabled: false))
    let player = SoundPlayer(settings: SoundSettings(enabled: store.load().soundEnabled),
                            quietHours: NeverQuiet())
    #expect(player.buffer(for: .done) == nil, "a stored mute did not survive construction")
}

// MARK: - Strengthening test 3: the wiring a real tap would actually drive

/// A step above `togglingMuteFromTheIslandPersists`: this drives the same
/// entry point a real tap on `PanelBar`'s `#pmute` reaches once `DrawerView`/
/// `IslandView` forward it (`model.onToggleMute?()`), not the bare store.
/// Confirms `NotchController.present()` really wires `model.onToggleMute` to
/// something that persists through the *injected* `PreferenceStoring` (not
/// `UserDefaults.standard` — this test would corrupt a real user's defaults
/// if it read the wrong one) and updates `model.muted` so the footer redraws
/// muted.
@MainActor @Test func toggleMuteReachesThePreferenceStoreThroughNotchController() {
    let store = InMemoryPreferenceStore(Preferences(soundEnabled: true))
    let (c, _) = makeController(store: store)
    #expect(c.model.muted == false, "a fresh controller must start in step with a soundEnabled==true store")

    c.model.onToggleMute?()

    #expect(store.load().soundEnabled == false, "the tap did not reach the injected store")
    #expect(c.model.muted == true, "model.muted did not follow the store it just wrote")

    // And back, proving this is a real toggle rather than a one-way latch.
    c.model.onToggleMute?()
    #expect(store.load().soundEnabled == true)
    #expect(c.model.muted == false)
    c.dismiss()
}

/// `onSoundEnabledChanged` is the one seam `NotchController` gives main.swift
/// to keep a real `SoundPlayer.settings.enabled` in step (see main.swift's
/// own wiring) — this confirms it actually fires, and with the value that
/// was just persisted rather than the one before the toggle.
@MainActor @Test func toggleMuteReportsTheFreshValueOutward() {
    let store = InMemoryPreferenceStore(Preferences(soundEnabled: true))
    let (c, _) = makeController(store: store)
    var reported: [Bool] = []
    c.onSoundEnabledChanged = { reported.append($0) }

    c.model.onToggleMute?()

    #expect(reported == [false], "onSoundEnabledChanged did not fire with the freshly-persisted value")
    c.dismiss()
}

/// `dismiss()` already clears `onIslandClick`/`onAnswer` (see
/// `dismissClearsTheIslandClickCallback` in NotchControllerTests.swift) so a
/// stale closure surviving teardown cannot mutate a torn-down controller's
/// model. `onToggleMute` is new in this plan and needs the same guarantee.
@MainActor @Test func dismissClearsTheMuteCallback() {
    let store = InMemoryPreferenceStore()
    let (c, _) = makeController(store: store)
    c.dismiss()
    #expect(c.model.onToggleMute == nil)
}

// MARK: - Strengthening further: does DrawerView actually forward `muted`?

/// `DrawerView` used to hardcode `PanelBar(muted: false, …)` (Task 3). This
/// renders the real `DrawerView` — not a shared static any test calls around
/// `body`, for the exact reason `footerHeight`'s own doc comment gives for
/// rejecting that shape — with `muted: true` and `muted: false`, and looks
/// for `dimColour`, which only ever paints when `MuteIcon` itself receives
/// `muted: true` (`PanelBarTests.theMuteButtonShowsASlashOnlyWhenMuted`
/// already pins that `MuteIcon` half in isolation). A pixel this test finds
/// therefore proves `DrawerView`'s own `muted` parameter really reaches the
/// `PanelBar` it constructs, rather than a hardcoded value surviving Task 4.
///
/// **What this does not prove**: whether `DrawerView`'s `onToggleMute`
/// closure — a value no rendered pixel carries — is the one `PanelBar`'s
/// `Button` actually invokes. That is the same permanent gap
/// `PanelBarTests.tappingEachButtonCallsItsOwnClosureAndNotTheOther` already
/// records for `PanelBar` itself, one level further out: this project takes
/// no ViewInspector-style dependency, and a rendered `Button`'s `action`
/// closure cannot be read back out of a `View` value headlessly. Recorded
/// here rather than silently assumed covered.
@Test @MainActor func mutedForwardsFromDrawerViewIntoThePanelBarItRenders() throws {
    let width: CGFloat = 388
    let muted = try rasterise(
        DrawerView(question: nil, sessions: [], accent: IslandState.waiting.accent,
                   width: width, muted: true))
    let unmuted = try rasterise(
        DrawerView(question: nil, sessions: [], accent: IslandState.waiting.accent,
                   width: width, muted: false))

    let footerTop = muted.height - Int(DrawerView.footerHeight)
    try #require(footerTop >= 0, "the drawer rendered shorter than the footer reservation")
    try #require(unmuted.height == muted.height, "the two renders must be directly comparable")

    // Exact match, not a tolerance-6 "near" comparison the way
    // `PanelBarTests.fullyOpaquePixelCount` reads. Measured directly (and
    // worth recording since it contradicts that helper's own premise
    // transplanted here): `DrawerView` paints `PanelBar` over an *opaque*
    // `islandGroundColour` fill, so every antialiased stroke edge — the
    // gear's included, which never changes with `muted` — still composites
    // to `a == 255` with a blended RGB, rather than a partial alpha the way
    // an edge over transparency would. `PanelBarTests`' own restriction to
    // `a == 255` relies on a transparent backdrop to make "fully opaque"
    // mean "solid interior"; against an opaque backdrop it does not, and a
    // tolerance-6 scan over this render's footer read 22 such edge pixels —
    // from the *gear*, unmuted, unrelated to this test's own claim — within
    // 6 levels of `dimColour` on every channel. Exact equality survives that:
    // measured here, every genuinely `dimColour`-tinted interior pixel reads
    // the value exactly (`#5A6273`, 24 of them), and the antialiased
    // near-misses this test must not count land at `#5D6370`/`#5E6472`/
    // `#606775`/`#586070`/`#565E6E` — never the exact target.
    func opaqueDimPixelsInFooter(_ raster: Raster) -> Int {
        let target = Raster.Pixel(dimColour)
        var count = 0
        for y in footerTop..<raster.height {
            for x in 0..<raster.width {
                let p = raster[x, y]
                guard p.a == 255, p.r == target.r, p.g == target.g, p.b == target.b else { continue }
                count += 1
            }
        }
        return count
    }

    #expect(opaqueDimPixelsInFooter(muted) > 0,
            "DrawerView(muted: true) must draw the footer's mute icon in dimColour")
    #expect(opaqueDimPixelsInFooter(unmuted) == 0,
            "DrawerView(muted: false) must not draw any dimColour ink in the footer")
}

// MARK: - the other two preferences production never read

@Test func everyPersistedSoundSettingReachesTheRuntimeAndNotJustEnabled() {
    // Two of the four preferences were write-only: `main.swift` built
    // `SoundSettings(enabled: preferences.load().soundEnabled)`, so `volume` and
    // `quietDuringDoNotDisturb` were saved by `PreferenceStore.save(_:)` and read
    // by nothing. `quietDuringDoNotDisturb` is the one that mattered —
    // `SoundPlayer.wantsSilence` gates every cue on it, so the plist could say
    // `false` and Focus suppression carried on anyway.
    //
    // Every value here differs from `SoundSettings`' own default, which is what
    // makes the test able to fail: with `volume` at the shared 0.60 default, a
    // dropped `volume:` argument is invisible.
    let prefs = Preferences(soundEnabled: false, volume: 0.15,
                            quietDuringDoNotDisturb: false, selectedPage: "display")
    let settings = SoundSettings(prefs)
    #expect(settings.enabled == false)
    #expect(settings.volume == 0.15, "a persisted volume does not reach the player")
    #expect(settings.quietDuringDoNotDisturb == false,
            "a persisted Do Not Disturb choice does not reach the player, so suppression ignores it")
    // The one field with no key yet. Asserted so that adding a `pack` preference in
    // 6.5 is a deliberate edit here rather than a silent default.
    #expect(settings.pack == .chiptune)
}

@Test func aStoredVolumeIsStillClampedOnItsWayIntoTheRuntime() {
    // Two clamps, deliberately, exactly as `SettingsWindowController` keeps two
    // page clamps: `UserDefaultsPreferenceStore.load()` clamps, but
    // `InMemoryPreferenceStore` does not and `Preferences.init` does not either, so
    // a `Preferences` can carry a volume production could not have produced. This
    // initialiser must not be the place that lets one through to an AVAudioEngine
    // gain.
    #expect(SoundSettings(Preferences(volume: 42)).volume == 1.0)
    #expect(SoundSettings(Preferences(volume: .nan)).volume == SoundSettings.defaultVolume)
}
