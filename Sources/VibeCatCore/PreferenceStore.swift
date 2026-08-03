import Foundation

public protocol PreferenceStoring: Sendable {
    func load() -> Preferences
    func save(_ preferences: Preferences)
}

/// Preferences in `UserDefaults`, **clamped on the way in**.
///
/// The clamping is the boundary, not defensive padding. A `UserDefaults` plist is
/// a file any process running as this user can edit, Plans 6.5–6.7 will write
/// these keys, and an unclamped `volume` reaches an `AVAudioEngine` gain. This
/// repo already has the precedent in a harsher form: every interval that becomes
/// a deadline goes through one clamp, because a value read off the socket can
/// saturate a `DispatchTime` into `.distantFuture` and park a thread forever.
///
/// `NaN` needs its own branch. It fails every comparison, so `min(max(x, 0), 1)`
/// passes it straight through — clamping alone does not catch it.
public struct UserDefaultsPreferenceStore: PreferenceStoring {
    // UserDefaults is documented as thread-safe for concurrent reads and writes
    // but predates Sendable and isn't annotated; `nonisolated(unsafe)` records
    // that this is a deliberate, checked exception rather than an oversight.
    private nonisolated(unsafe) let defaults: UserDefaults
    private let keyPrefix: String

    public init(defaults: UserDefaults = .standard, keyPrefix: String = "vibecat.") {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    private func key(_ name: String) -> String { keyPrefix + name }

    public func load() -> Preferences {
        let fallback = Preferences()
        var prefs = fallback
        // `bool(forKey:)` returns `false` for a key that was never written, and
        // both of these default to `true` — reading unconditionally would ship a
        // fresh install with sound off and DND-respect off. The presence check is
        // the whole point.
        if defaults.object(forKey: key("soundEnabled")) != nil {
            prefs.soundEnabled = defaults.bool(forKey: key("soundEnabled"))
        }
        if defaults.object(forKey: key("quietDuringDoNotDisturb")) != nil {
            prefs.quietDuringDoNotDisturb = defaults.bool(forKey: key("quietDuringDoNotDisturb"))
        }
        if defaults.object(forKey: key("volume")) != nil {
            prefs.volume = Self.clampedVolume(defaults.double(forKey: key("volume")),
                                              fallback: fallback.volume)
        }
        if let page = defaults.string(forKey: key("selectedPage")),
           SettingsPageKey.isKnown(page) {
            prefs.selectedPage = page
        }
        return prefs
    }

    public func save(_ preferences: Preferences) {
        defaults.set(preferences.soundEnabled, forKey: key("soundEnabled"))
        defaults.set(preferences.volume, forKey: key("volume"))
        defaults.set(preferences.quietDuringDoNotDisturb, forKey: key("quietDuringDoNotDisturb"))
        defaults.set(preferences.selectedPage, forKey: key("selectedPage"))
    }

    static func clampedVolume(_ value: Double, fallback: Double) -> Double {
        guard !value.isNaN else { return fallback }
        return min(max(value, 0), 1)
    }
}

/// The page keys, here rather than in `VibeCatUI`, because `load()` has to reject
/// a key that no longer names a pane and `VibeCatCore` cannot see the views.
/// Kept in step with `SettingsPage.all` by `theCoreAndTheUIAgreeOnThePageKeys`.
public enum SettingsPageKey {
    public static let all = ["general", "integrations", "notifications", "display"]
    public static func isKnown(_ key: String) -> Bool { all.contains(key) }
}

/// For tests, and for any surface that should not touch the user's real defaults.
public struct InMemoryPreferenceStore: PreferenceStoring {
    private final class Box: @unchecked Sendable { var value: Preferences; init(_ v: Preferences) { value = v } }
    private let box: Box
    public init(_ initial: Preferences = Preferences()) { box = Box(initial) }
    public func load() -> Preferences { box.value }
    public func save(_ preferences: Preferences) { box.value = preferences }
}
