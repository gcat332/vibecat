import Testing
import Foundation
@testable import VibeCatCore

// MARK: - defaults

@Test func anEmptyStoreReturnsThePrototypesOwnDefaults() {
    // Every one of these is a value read off settings.html, not a preference of
    // ours: the volume slider's value="60", the DND switch's aria-checked="true",
    // and the General pane's data-active="true".
    withFreshDefaults { defaults, prefix in
        let prefs = UserDefaultsPreferenceStore(defaults: defaults, keyPrefix: prefix).load()
        #expect(prefs.soundEnabled == true)
        #expect(prefs.volume == 0.60)
        #expect(prefs.quietDuringDoNotDisturb == true)
        #expect(prefs.selectedPage == "general")
    }
}

// MARK: - round trip

@Test func everyFieldSurvivesASaveAndReload() {
    // One store, two operations. If a field is missing from either the write or
    // the read, exactly that field comes back as its default — so this fails
    // field by field rather than all at once.
    withFreshDefaults { defaults, prefix in
        let store = UserDefaultsPreferenceStore(defaults: defaults, keyPrefix: prefix)
        let written = Preferences(soundEnabled: false, volume: 0.15,
                                  quietDuringDoNotDisturb: false, selectedPage: "display")
        store.save(written)
        #expect(store.load() == written)
    }
}

@Test func savingOneFieldDoesNotResetTheOthers() {
    withFreshDefaults { defaults, prefix in
        let store = UserDefaultsPreferenceStore(defaults: defaults, keyPrefix: prefix)
        store.save(Preferences(volume: 0.9))
        var next = store.load()
        next.soundEnabled = false
        store.save(next)
        #expect(store.load().volume == 0.9, "the second save dropped the first's volume")
    }
}

// MARK: - the boundary

@Test func anAbsurdVolumeInThePlistIsClampedRatherThanTrusted() {
    // A UserDefaults plist is a file anything running as this user can edit, and
    // 6.5 will write this key. An unclamped value reaches an AVAudioEngine gain.
    withFreshDefaults { defaults, prefix in
        defaults.set(42.0, forKey: prefix + "volume")
        #expect(UserDefaultsPreferenceStore(defaults: defaults, keyPrefix: prefix).load().volume == 1.0)
        defaults.set(-3.0, forKey: prefix + "volume")
        #expect(UserDefaultsPreferenceStore(defaults: defaults, keyPrefix: prefix).load().volume == 0.0)
    }
}

@Test func aNonFiniteVolumeIsReplacedByTheDefaultRatherThanClampedToAnEdge() {
    // NaN fails every comparison, so `min(max(x, 0), 1)` passes it straight
    // through — clamping alone does not catch this one. It has to be tested
    // separately or it will not be caught at all.
    withFreshDefaults { defaults, prefix in
        defaults.set(Double.nan, forKey: prefix + "volume")
        let v = UserDefaultsPreferenceStore(defaults: defaults, keyPrefix: prefix).load().volume
        #expect(v == 0.60, "expected the default, got \(v)")
        defaults.set(Double.infinity, forKey: prefix + "volume")
        #expect(UserDefaultsPreferenceStore(defaults: defaults, keyPrefix: prefix).load().volume == 1.0)
    }
}

// MARK: - the four new alert/sound fields (Plan 6.5, Task 1)

@Test func aNewAlertFieldRoundTripsAndDefaultsWhenAbsent() {
    // `withFreshDefaults` below is the real fixture, installed by Plan 6.4's fix
    // round — a fixed suite plus a per-test `keyPrefix`, cleaned up on the way
    // out. Its predecessor built a suite per test and leaked 175 plists into
    // `~/Library/Preferences`, because emptying a defaults domain is not
    // cleaning up after yourself — `cfprefsd` writes it back.
    withFreshDefaults { defaults, prefix in
        let store = UserDefaultsPreferenceStore(defaults: defaults, keyPrefix: prefix)
        #expect(store.load().alerts == AlertPolicy(), "an untouched store must give the prototype's states")
        var p = store.load()
        p.alerts.onStall = true
        p.postsSystemNotification = true
        store.save(p)
        #expect(store.load().alerts.onStall == true)
        #expect(store.load().postsSystemNotification == true)
        // And the fields this plan did not touch survived.
        #expect(store.load().volume == 0.60)
    }
}

@Test func anUnknownPackOrChoiceInThePlistFallsBackRatherThanCrashing() {
    // 6.2's decision 3: Soft/System/Blip do not exist. A plist naming one — or a
    // future build's key read by an older one — must not produce a nil enum.
    withFreshDefaults { defaults, prefix in
        defaults.set("soft", forKey: prefix + "pack")
        defaults.set("blip", forKey: prefix + "choiceForFail")
        let loaded = UserDefaultsPreferenceStore(defaults: defaults, keyPrefix: prefix).load()
        #expect(loaded.pack == .chiptune)
        #expect(loaded.choiceForFail == .standard)
    }
}

@Test func anUnknownSelectedPageFallsBackToGeneralRatherThanOpeningNothing() {
    // A page key that no longer exists — a renamed pane, a hand-edited plist —
    // must not open a window with no pane selected.
    withFreshDefaults { defaults, prefix in
        defaults.set("kitchen-sink", forKey: prefix + "selectedPage")
        #expect(UserDefaultsPreferenceStore(defaults: defaults, keyPrefix: prefix).load().selectedPage == "general")
    }
}

// MARK: - the fixture itself

@Test func theFixtureLeavesNothingBehindInTheUsersDefaults() {
    // The defect this file shipped with: a fixture that isolated correctly and
    // cleaned up not at all, so `swift test` wrote to `~/Library/Preferences` on
    // every run and never took anything back. Nothing in this file would have
    // noticed — every assertion above is about the store, and a store reads the
    // keys it just wrote whether or not they survive the test.
    //
    // So this asserts the fixture's own contract instead: after the block returns,
    // the whole prefix is gone from the real domain. Deleting the `defer` fails
    // exactly this and nothing else.
    var usedPrefix = ""
    withFreshDefaults { defaults, prefix in
        usedPrefix = prefix
        UserDefaultsPreferenceStore(defaults: defaults, keyPrefix: prefix)
            .save(Preferences(soundEnabled: false, volume: 0.15,
                              quietDuringDoNotDisturb: false, selectedPage: "display"))
        #expect(defaults.object(forKey: prefix + "volume") != nil,
                "the fixture wrote nothing, so its cleanup cannot be tested")
    }
    let leftovers = UserDefaults(suiteName: sharedTestSuite)!
        .dictionaryRepresentation().keys.filter { $0.hasPrefix(usedPrefix) }
    #expect(leftovers.isEmpty, "the fixture left \(leftovers.count) keys in the user's real defaults")
}

// MARK: - fixture

/// A key space in a real `UserDefaults` that nobody else in the suite shares —
/// **one file, not one per test**, and emptied when the test returns.
///
/// Per-test *isolation* is the obvious half: the whole suite runs in parallel and
/// `.standard` is process-wide, so two tests writing the same key would flake in a
/// way that looks like a bug in the store.
///
/// **Per-test cleanup is the half an earlier version of this fixture missed, and
/// getting it right meant giving up the per-test suite name.** That version made a
/// `UserDefaults(suiteName: "vibecat.tests.<UUID>")` and called
/// `removePersistentDomain` only *before* use, so everything the test then wrote
/// stayed on disk. Measured: **165 `vibecat.tests.<UUID>.plist` files, 660K, six
/// more per full `swift test` run**, unbounded, from the command `CLAUDE.md`
/// documents as the ordinary thing to run.
///
/// Calling `removePersistentDomain` in a `defer` as well is *not* enough, and this
/// was measured too: the domain is emptied, `cfprefsd` then writes the now-empty
/// domain back out, and even deleting the file by hand inside the `defer` only
/// changes the leak from 172-byte files to 42-byte ones — five more per run. There
/// is no in-process point at which a suite's own file can be made to stay deleted,
/// because the daemon owns it and outlives the test.
///
/// So the suite name is **fixed** and isolation comes from
/// `UserDefaultsPreferenceStore`'s own `keyPrefix` instead, which exists for
/// exactly this. The store's whole key set lives under one unique prefix per test,
/// the `defer` removes those keys and nothing else (`removePersistentDomain` would
/// wipe a concurrently-running test's keys), and the file count is one forever.
private func withFreshDefaults(_ body: (UserDefaults, String) throws -> Void) rethrows {
    let defaults = UserDefaults(suiteName: sharedTestSuite)!
    let prefix = "t\(UUID().uuidString.replacingOccurrences(of: "-", with: "")).vibecat."
    defer {
        // Every key this store can write, removed by name rather than by scanning
        // `dictionaryRepresentation()`. The scan version left one key behind per
        // run (measured: a stale `…volume = 42` in the shared file), because the
        // representation is a snapshot and several of these tests run in parallel
        // against the same domain. Naming the four keys cannot miss one that the
        // snapshot had not caught up with — and `SettingsPageKey`-style drift is
        // covered, because a fifth key would have to be added to `save(_:)` and
        // `everyFieldSurvivesASaveAndReload` reads all four back.
        for name in ["soundEnabled", "volume", "quietDuringDoNotDisturb", "selectedPage",
                     "alerts.onNeedsAnswer", "alerts.onFinish", "alerts.onFail", "alerts.onStall",
                     "pack", "choiceForNeedsAnswer", "choiceForFinish", "choiceForFail",
                     "postsSystemNotification"] {
            defaults.removeObject(forKey: prefix + name)
        }
        defaults.synchronize()
    }
    try body(defaults, prefix)
}

/// The one suite file every test in this file shares. Named rather than inlined so
/// `theFixtureLeavesNothingBehind` below can look at the same domain.
private let sharedTestSuite = "vibecat.tests"
