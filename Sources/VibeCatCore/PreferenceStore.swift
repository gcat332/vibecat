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
        // Three of `AlertPolicy`'s four fields default to `true`, exactly the
        // trap `soundEnabled` and `quietDuringDoNotDisturb` above already guard
        // against: `bool(forKey:)` returns `false` for an absent key, so reading
        // unconditionally would ship a fresh install with alerts off.
        var alerts = fallback.alerts
        if defaults.object(forKey: key("alerts.onNeedsAnswer")) != nil {
            alerts.onNeedsAnswer = defaults.bool(forKey: key("alerts.onNeedsAnswer"))
        }
        if defaults.object(forKey: key("alerts.onFinish")) != nil {
            alerts.onFinish = defaults.bool(forKey: key("alerts.onFinish"))
        }
        if defaults.object(forKey: key("alerts.onFail")) != nil {
            alerts.onFail = defaults.bool(forKey: key("alerts.onFail"))
        }
        if defaults.object(forKey: key("alerts.onStall")) != nil {
            alerts.onStall = defaults.bool(forKey: key("alerts.onStall"))
        }
        prefs.alerts = alerts
        // `SoundPack(rawValue:)` and `CueChoice(rawValue:)` both fail rather than
        // crash on an unrecognised string — written decision 1: a plist naming a
        // pack or choice this build does not implement (`"soft"`, `"blip"`) must
        // fall back to the prototype's default, not force-unwrap into a trap.
        if let raw = defaults.string(forKey: key("pack")) {
            prefs.pack = SoundPack(rawValue: raw) ?? fallback.pack
        }
        if let raw = defaults.string(forKey: key("choiceForNeedsAnswer")) {
            prefs.choiceForNeedsAnswer = CueChoice(rawValue: raw) ?? fallback.choiceForNeedsAnswer
        }
        if let raw = defaults.string(forKey: key("choiceForFinish")) {
            prefs.choiceForFinish = CueChoice(rawValue: raw) ?? fallback.choiceForFinish
        }
        if let raw = defaults.string(forKey: key("choiceForFail")) {
            prefs.choiceForFail = CueChoice(rawValue: raw) ?? fallback.choiceForFail
        }
        prefs.postsSystemNotification = defaults.bool(forKey: key("postsSystemNotification"))
        // Same shape as `pack` and the three `CueChoice` fields above: an
        // unrecognised raw value (a future build's level, a hand-edited plist)
        // falls back to the default rather than crashing. `MotionLevel(rawValue:
        // )!` is not an option here — that would turn an untrusted plist value
        // into a production crash, the exact thing this file's own doc comment
        // says the clamping boundary exists to prevent.
        if let raw = defaults.string(forKey: key("motion")) {
            prefs.motion = MotionLevel(rawValue: raw) ?? fallback.motion
        }
        if let raw = defaults.string(forKey: key("rightFlank")) {
            prefs.rightFlank = RightFlank(rawValue: raw) ?? fallback.rightFlank
        }
        if let raw = defaults.string(forKey: key("coat")) {
            prefs.coat = Coat(rawValue: raw) ?? fallback.coat
        }
        // `SessionCardOptions`'s nine fields all default to `true`, exactly the
        // trap `soundEnabled` and the alert switches above already guard
        // against: `bool(forKey:)` returns `false` for a key nobody ever wrote,
        // so reading any of these nine unconditionally would ship a fresh
        // install with a blank session list.
        var cardOptions = fallback.cardOptions
        if defaults.object(forKey: key("cardOptions.activity")) != nil {
            cardOptions.activity = defaults.bool(forKey: key("cardOptions.activity"))
        }
        if defaults.object(forKey: key("cardOptions.lastMessage")) != nil {
            cardOptions.lastMessage = defaults.bool(forKey: key("cardOptions.lastMessage"))
        }
        if defaults.object(forKey: key("cardOptions.tasks")) != nil {
            cardOptions.tasks = defaults.bool(forKey: key("cardOptions.tasks"))
        }
        if defaults.object(forKey: key("cardOptions.agents")) != nil {
            cardOptions.agents = defaults.bool(forKey: key("cardOptions.agents"))
        }
        if defaults.object(forKey: key("cardOptions.subagents")) != nil {
            cardOptions.subagents = defaults.bool(forKey: key("cardOptions.subagents"))
        }
        if defaults.object(forKey: key("cardOptions.project")) != nil {
            cardOptions.project = defaults.bool(forKey: key("cardOptions.project"))
        }
        if defaults.object(forKey: key("cardOptions.worktree")) != nil {
            cardOptions.worktree = defaults.bool(forKey: key("cardOptions.worktree"))
        }
        if defaults.object(forKey: key("cardOptions.model")) != nil {
            cardOptions.model = defaults.bool(forKey: key("cardOptions.model"))
        }
        if defaults.object(forKey: key("cardOptions.effort")) != nil {
            cardOptions.effort = defaults.bool(forKey: key("cardOptions.effort"))
        }
        prefs.cardOptions = cardOptions
        return prefs
    }

    public func save(_ preferences: Preferences) {
        defaults.set(preferences.soundEnabled, forKey: key("soundEnabled"))
        defaults.set(preferences.volume, forKey: key("volume"))
        defaults.set(preferences.quietDuringDoNotDisturb, forKey: key("quietDuringDoNotDisturb"))
        defaults.set(preferences.selectedPage, forKey: key("selectedPage"))
        defaults.set(preferences.alerts.onNeedsAnswer, forKey: key("alerts.onNeedsAnswer"))
        defaults.set(preferences.alerts.onFinish, forKey: key("alerts.onFinish"))
        defaults.set(preferences.alerts.onFail, forKey: key("alerts.onFail"))
        defaults.set(preferences.alerts.onStall, forKey: key("alerts.onStall"))
        defaults.set(preferences.pack.rawValue, forKey: key("pack"))
        defaults.set(preferences.choiceForNeedsAnswer.rawValue, forKey: key("choiceForNeedsAnswer"))
        defaults.set(preferences.choiceForFinish.rawValue, forKey: key("choiceForFinish"))
        defaults.set(preferences.choiceForFail.rawValue, forKey: key("choiceForFail"))
        defaults.set(preferences.postsSystemNotification, forKey: key("postsSystemNotification"))
        defaults.set(preferences.motion.rawValue, forKey: key("motion"))
        defaults.set(preferences.rightFlank.rawValue, forKey: key("rightFlank"))
        defaults.set(preferences.coat.rawValue, forKey: key("coat"))
        defaults.set(preferences.cardOptions.activity, forKey: key("cardOptions.activity"))
        defaults.set(preferences.cardOptions.lastMessage, forKey: key("cardOptions.lastMessage"))
        defaults.set(preferences.cardOptions.tasks, forKey: key("cardOptions.tasks"))
        defaults.set(preferences.cardOptions.agents, forKey: key("cardOptions.agents"))
        defaults.set(preferences.cardOptions.subagents, forKey: key("cardOptions.subagents"))
        defaults.set(preferences.cardOptions.project, forKey: key("cardOptions.project"))
        defaults.set(preferences.cardOptions.worktree, forKey: key("cardOptions.worktree"))
        defaults.set(preferences.cardOptions.model, forKey: key("cardOptions.model"))
        defaults.set(preferences.cardOptions.effort, forKey: key("cardOptions.effort"))
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
    /// Named because two places branch on this one key: `SettingsPaneView` draws
    /// real controls for it rather than an owner note, and `SettingsPage
    /// .ownerNote(for:)` no longer answers for it. A string literal in both is
    /// how one of them silently stops matching.
    public static let notifications = "notifications"
    public static let all = ["general", "integrations", notifications, "display"]
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
