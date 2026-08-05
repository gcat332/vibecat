import Testing
import Foundation
import VibeCatCore
@testable import VibeCatUI

/// Plan 6.1 Task 6: the two preferences §9.3 and §6.2 describe are read off disk
/// at launch, and this file is the only thing standing between that read and the
/// defect this repo keeps shipping — **a preference persisted in both directions
/// and consumed by nothing.** Three fields in Plan 6.4 (`volume`,
/// `quietDuringDoNotDisturb`, `selectedPage`), through six task reviews; a fourth
/// on the store→engine seam in Plan 6.5.
///
/// It is testable at all only because the mapping lives in `NotchController.init`
/// rather than in `main.swift`: an `executableTarget` with a `main.swift` cannot be
/// `@testable import`ed, so anything written there is unguarded by construction.
/// See `main.swift`'s own comment above `let preferences` for the one part of the
/// launch path that remains outside any test — passing the store in at all.
private func fixtureMetrics() -> ScreenMetrics {
    ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                  visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
                  safeAreaTop: 32,
                  auxLeft: CGRect(x: 0, y: 950, width: 663, height: 32),
                  auxRight: CGRect(x: 848, y: 950, width: 664, height: 32))
}

/// No `present()`, deliberately: every assertion below is about what `init`
/// itself read, and `present()` would only add a real `NSPanel` this file has no
/// use for. The mute test in `MuteWiringTests` presents because it drives
/// `model.onToggleMute`, which `present()` is what wires.
@MainActor private func controller(_ store: PreferenceStoring) -> NotchController {
    let appModel = AppModel(socketPath: "/tmp/vibecat-launchwiring-unused.sock")
    let c = NotchController(model: appModel, metrics: { fixtureMetrics() }, preferences: store)
    c.refreshGeometry()
    return c
}

/// §9.3's stored level has to survive construction, because construction is the
/// only place it is ever read: `MotionPreference.current(chosen:)` defaults
/// `chosen` to `.full`, so dropping the argument compiles, runs, and leaves the
/// preference write-only.
///
/// Asserted on `chosen`, **never on `effective`** — `effective` folds in this
/// machine's own Reduce Motion switch, and an assertion that depends on what is
/// set in System Settings is the same class of mistake as the test in this repo
/// that hardcoded 48kHz and turned on what audio hardware was attached: green
/// until it wasn't, with nothing changed in the repo. §9.3's override direction is
/// `MotionPreferenceTests`' business, tested there against both values of
/// `systemWantsReduced` explicitly rather than against whatever this machine has.
@MainActor @Test func aStoredMotionLevelReachesTheIslandAtLaunch() {
    let c = controller(InMemoryPreferenceStore(Preferences(motion: .off)))
    #expect(c.model.motion.chosen == .off,
            "a stored motion level does not reach the island — §9.3's preference is write-only")

    let reduced = controller(InMemoryPreferenceStore(Preferences(motion: .reduced)))
    #expect(reduced.model.motion.chosen == .reduced,
            "the read is not the stored value; something is hardcoding a level")
}

/// The same for §6.2, and one step further than the property: `layout.right` is
/// what `IslandBody` actually draws from, so this covers both the read *and*
/// Task 5's `RightFlank → RightContent` mapping being reachable from a real
/// launch rather than only from a test that assigns `model.rightFlank` by hand.
@MainActor @Test func aStoredRightFlankReachesTheIslandAtLaunch() {
    let c = controller(InMemoryPreferenceStore(Preferences(rightFlank: .agentIcon)))
    #expect(c.model.rightFlank == .agentIcon,
            "a stored right flank does not reach the island — §6.2's preference is write-only")
    #expect(c.model.layout.right == .agentIcon,
            "the stored flank reached the model but not the layout the island draws from")

    let none = controller(InMemoryPreferenceStore(Preferences(rightFlank: .nothing)))
    #expect(none.model.layout.right == .nothing)
}

/// The two above plus the mute glyph, in one controller, from one `load()`.
///
/// Separate from them on purpose: those two would both pass if `init` read the
/// store twice and got two different answers, and this one would too — what it
/// adds is that **all three** launch-time reads land together off a single
/// non-default `Preferences`, which is the shape a real relaunch has. A mutation
/// that reads `preferences.load()` fresh per field cannot be caught by any test
/// (the values agree), so this is not claiming to; it is claiming that no one of
/// the three reads got dropped while the other two were being written.
@MainActor @Test func everyIslandPreferenceIsReadFromTheSameStoreAtLaunch() {
    let c = controller(InMemoryPreferenceStore(
        Preferences(soundEnabled: false, motion: .off, rightFlank: .nothing)))

    #expect(c.model.motion.chosen == .off)
    #expect(c.model.rightFlank == .nothing)
    #expect(c.model.muted, "a launch with sound already muted must show muted immediately")
}

/// Which production reader each `Preferences` field has, enumerated with `Mirror`
/// rather than named field by field — the same tripwire shape as
/// `PreferenceStoreTests.aFieldAddedWithoutPersistenceFailsWithoutAnyoneRememberingToTestIt`,
/// one seam further out. That one catches a field `save`/`load` forgot; this one
/// catches a field **nothing reads**, which is the defect that actually shipped
/// four times.
///
/// **What it does and does not do.** It fails when `Preferences` grows, shrinks or
/// renames a field, forcing whoever did that to write down who reads it. It cannot
/// verify the named reader really reads it — a reader could be gutted tomorrow and
/// this test would stay green. That is what the three behavioural tests above are
/// for, for the two fields this plan owns; the other ten name a testable seam
/// (`SoundSettings(_:)`, `Notifier.postStalls`, `AppModel`'s `CueSelector` gate,
/// `SettingsWindowController(store:)`) that has its own tests, and every one of
/// those names was checked against the source when this table was written rather
/// than assumed.
///
/// Note two of them are not launch-time at all — `alerts` and
/// `postsSystemNotification` are re-read on every event, deliberately, so a switch
/// flipped in Settings takes effect without a relaunch. The distinction is
/// recorded because a future reader looking for "where is this read at launch"
/// would otherwise conclude those two are unwired.
@Test func everyPreferenceFieldHasANamedProductionReader() {
    let readers: [String: String] = [
        "soundEnabled": "NotchController.init → IslandModel.muted; SoundSettings(_:) → SoundPlayer",
        "volume": "SoundSettings(_:) → SoundPlayer",
        "quietDuringDoNotDisturb": "SoundSettings(_:) → SoundPlayer.wantsSilence",
        "selectedPage": "SettingsWindowController(store:) → SettingsWindowModel",
        "alerts": "AppModel.preferences → CueSelector (re-read per event, not at launch)",
        "pack": "SoundSettings(_:) → CueRenderer",
        "choiceForNeedsAnswer": "SoundSettings(_:) → CueRenderer",
        "choiceForFinish": "SoundSettings(_:) → CueRenderer",
        "choiceForFail": "SoundSettings(_:) → CueRenderer",
        "postsSystemNotification": "Notifier.postStalls(from:preferences:) (re-read per stall)",
        "motion": "NotchController.init → IslandModel.motion.chosen",
        "rightFlank": "NotchController.init → IslandModel.rightFlank",
    ]

    let fields = Mirror(reflecting: Preferences()).children.map { $0.label ?? "?" }
    for field in fields {
        #expect(readers[field] != nil,
                "`\(field)` has no named reader — either wire it up or record here what reads it")
    }
    for named in readers.keys {
        #expect(fields.contains(named),
                "`\(named)` is named here but no longer exists on Preferences")
    }
}
