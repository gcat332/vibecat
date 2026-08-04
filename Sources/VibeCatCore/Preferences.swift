import Foundation

/// The preferences that exist today. **Ten, and each one has a control that means
/// something** — Plan 6.4 added the first four, Plan 6.5's Notifications page the
/// rest.
///
/// §14 describes roughly 47 controls across four pages. The remaining keys arrive
/// with the pages that own them (6.6 Display, 6.7 General and Integrations),
/// because adding them now would mean inventing defaults for behaviour that does
/// not exist and shipping untested surface.
///
/// **Adding a field here means adding it to `save` *and* `load`.** Three fields
/// shipped in Plan 6.4 persisted but never read, through six task reviews, so
/// `aFieldAddedWithoutPersistenceFailsWithoutAnyoneRememberingToTestIt` enumerates
/// this struct with `Mirror` rather than naming fields — a new one that either half
/// forgets comes back as its default and fails, naming itself.
///
/// Every default below is read off `settings.html`, not chosen: the volume
/// slider's `value="60"` (line 358), the Do Not Disturb switch's
/// `aria-checked="true"` (line 359), and the General pane's `data-active="true"`
/// (line 210).
public struct Preferences: Sendable, Equatable {
    public var soundEnabled: Bool
    /// `0…1`, from `settings.html`'s `0…100` slider.
    public var volume: Double
    public var quietDuringDoNotDisturb: Bool
    /// Which pane the window reopens on. A key, not an index, so reordering the
    /// sidebar cannot silently change which page someone lands on.
    public var selectedPage: String
    /// §14's four switches, `Alert me when an agent…` (`settings.html:328-336`).
    public var alerts: AlertPolicy
    /// §14's Sound pack picker (`settings.html:341`).
    public var pack: SoundPack
    /// §14's three per-cue pickers (`settings.html:344-357`). Each defaults to
    /// the cue's own sound rather than any override.
    public var choiceForNeedsAnswer: CueChoice
    public var choiceForFinish: CueChoice
    public var choiceForFail: CueChoice
    /// §14's `Also post a system notification` (`settings.html:368`),
    /// `aria-checked="false"` — off until Task 7 gives it a real destination.
    public var postsSystemNotification: Bool

    public init(soundEnabled: Bool = true, volume: Double = 0.60,
                quietDuringDoNotDisturb: Bool = true, selectedPage: String = "general",
                alerts: AlertPolicy = AlertPolicy(), pack: SoundPack = .chiptune,
                choiceForNeedsAnswer: CueChoice = .standard,
                choiceForFinish: CueChoice = .standard,
                choiceForFail: CueChoice = .standard,
                postsSystemNotification: Bool = false) {
        self.soundEnabled = soundEnabled
        self.volume = volume
        self.quietDuringDoNotDisturb = quietDuringDoNotDisturb
        self.selectedPage = selectedPage
        self.alerts = alerts
        self.pack = pack
        self.choiceForNeedsAnswer = choiceForNeedsAnswer
        self.choiceForFinish = choiceForFinish
        self.choiceForFail = choiceForFail
        self.postsSystemNotification = postsSystemNotification
    }
}
