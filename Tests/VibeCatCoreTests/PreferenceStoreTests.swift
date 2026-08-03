import Testing
import Foundation
@testable import VibeCatCore

// MARK: - defaults

@Test func anEmptyStoreReturnsThePrototypesOwnDefaults() {
    // Every one of these is a value read off settings.html, not a preference of
    // ours: the volume slider's value="60", the DND switch's aria-checked="true",
    // and the General pane's data-active="true".
    let prefs = UserDefaultsPreferenceStore(defaults: freshDefaults()).load()
    #expect(prefs.soundEnabled == true)
    #expect(prefs.volume == 0.60)
    #expect(prefs.quietDuringDoNotDisturb == true)
    #expect(prefs.selectedPage == "general")
}

// MARK: - round trip

@Test func everyFieldSurvivesASaveAndReload() {
    // One store, two operations. If a field is missing from either the write or
    // the read, exactly that field comes back as its default — so this fails
    // field by field rather than all at once.
    let defaults = freshDefaults()
    let store = UserDefaultsPreferenceStore(defaults: defaults)
    let written = Preferences(soundEnabled: false, volume: 0.15,
                              quietDuringDoNotDisturb: false, selectedPage: "display")
    store.save(written)
    #expect(store.load() == written)
}

@Test func savingOneFieldDoesNotResetTheOthers() {
    let defaults = freshDefaults()
    let store = UserDefaultsPreferenceStore(defaults: defaults)
    store.save(Preferences(volume: 0.9))
    var next = store.load()
    next.soundEnabled = false
    store.save(next)
    #expect(store.load().volume == 0.9, "the second save dropped the first's volume")
}

// MARK: - the boundary

@Test func anAbsurdVolumeInThePlistIsClampedRatherThanTrusted() {
    // A UserDefaults plist is a file anything running as this user can edit, and
    // 6.5 will write this key. An unclamped value reaches an AVAudioEngine gain.
    let defaults = freshDefaults()
    defaults.set(42.0, forKey: "vibecat.volume")
    #expect(UserDefaultsPreferenceStore(defaults: defaults).load().volume == 1.0)
    defaults.set(-3.0, forKey: "vibecat.volume")
    #expect(UserDefaultsPreferenceStore(defaults: defaults).load().volume == 0.0)
}

@Test func aNonFiniteVolumeIsReplacedByTheDefaultRatherThanClampedToAnEdge() {
    // NaN fails every comparison, so `min(max(x, 0), 1)` passes it straight
    // through — clamping alone does not catch this one. It has to be tested
    // separately or it will not be caught at all.
    let defaults = freshDefaults()
    defaults.set(Double.nan, forKey: "vibecat.volume")
    let v = UserDefaultsPreferenceStore(defaults: defaults).load().volume
    #expect(v == 0.60, "expected the default, got \(v)")
    defaults.set(Double.infinity, forKey: "vibecat.volume")
    #expect(UserDefaultsPreferenceStore(defaults: defaults).load().volume == 1.0)
}

@Test func anUnknownSelectedPageFallsBackToGeneralRatherThanOpeningNothing() {
    // A page key that no longer exists — a renamed pane, a hand-edited plist —
    // must not open a window with no pane selected.
    let defaults = freshDefaults()
    defaults.set("kitchen-sink", forKey: "vibecat.selectedPage")
    #expect(UserDefaultsPreferenceStore(defaults: defaults).load().selectedPage == "general")
}

// MARK: - fixture

/// A `UserDefaults` nobody else in the suite shares. The whole suite runs in
/// parallel and `.standard` is process-wide — two tests writing the same key
/// would flake in a way that looks like a bug in the store.
private func freshDefaults() -> UserDefaults {
    let suite = "vibecat.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}
