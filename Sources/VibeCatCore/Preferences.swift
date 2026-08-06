import Foundation

/// The preferences that exist today. **Fourteen, and each one has a control
/// that means something** — Plan 6.4 added the first four, Plan 6.5's
/// Notifications page four more, Plan 6.1's Task 1 two more (`motion`,
/// `rightFlank`), Plan 6.6's Task 1 the last two (`coat`, `cardOptions`).
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
    /// §9.3's motion level. Default `full` — read off `MotionPreference`'s own
    /// default `chosen`, not `settings.html`, since Plan 6.6's Display page owns
    /// this control and has not shipped yet.
    public var motion: MotionLevel
    /// §14's *"Follow the system Reduce Motion setting"*, on by default —
    /// `settings.html:506`'s `aria-checked="true"`.
    ///
    /// **§9.3 already required this and nothing needed correcting.** Its wording is
    /// *"Settings offers Full / Reduced / Off, and **by default** follows the system
    /// Reduce Motion setting"* — the qualifier presupposes a switch. Plan 6.6's plan
    /// file called it a contradiction because `CLAUDE.md`'s summary of §9.3 had
    /// dropped those two words.
    public var followsSystemReduceMotion: Bool
    /// §6.2's choosable right flank. Default `sessionCount`, matching
    /// `IslandModel.layout`'s hardcoded behaviour today (Plan 6.1's Task 5 makes
    /// this preference the thing that actually drives it).
    public var rightFlank: RightFlank
    /// §7.3's coat picker (`settings.html`'s `#skins`). Default `.tabby`,
    /// matching `IslandModel.coat`'s and `CatGrid`'s own default so a model
    /// built with no preference wired in yet renders exactly as it always has.
    public var coat: Coat
    /// §11's nine session-card switches (`settings.html:445-490`), as data —
    /// see `SessionCardOptions`'s own doc comment for why this is nine named
    /// `Bool`s rather than `SessionRow.Options`'s raw `Int`. Default is every
    /// field on, matching `SessionRow.Options.all` and `settings.html`'s own
    /// switches, every one of which is `aria-checked="true"`.
    public var cardOptions: SessionCardOptions

    /// How long the notch may hold a question before the decision goes back to the
    /// terminal, in **minutes**. `nil` is `Never`.
    ///
    /// **Measured, and it is why the default is one minute rather than twenty.** While a
    /// `PreToolUse` hook is blocked, Claude Code prints nothing at all and its own
    /// permission prompt does not appear until the hook returns — verified against 2.1.223
    /// with a hook that slept 3s, twice, headless. So this is not a timeout guarding
    /// against a hang; it is the **hand-back mechanism**, and without it the terminal
    /// never gets a prompt. Only one party can hold the decision at a time, so the notch
    /// should not hold it for long.
    ///
    /// `Double?` rather than a sentinel, because `Never` is not a duration and `0` is what
    /// a truncated or hand-edited plist holds. `UserDefaultsPreferenceStore` gives it its
    /// own boolean key for that reason.
    ///
    /// **Nothing reads this yet.** Plan 6.7's Integrations row writes it and Plan 6.7's
    /// own Task 7 teaches the hook to read it; `HookRunner` still uses
    /// `SocketClient.defaultAnswerDeadline`. Said plainly because a preference that is
    /// persisted and never read has shipped three times in this project.
    public var handBackToTerminalAfter: Double?

    public init(soundEnabled: Bool = true, volume: Double = 0.60,
                quietDuringDoNotDisturb: Bool = true, selectedPage: String = "general",
                alerts: AlertPolicy = AlertPolicy(), pack: SoundPack = .chiptune,
                choiceForNeedsAnswer: CueChoice = .standard,
                choiceForFinish: CueChoice = .standard,
                choiceForFail: CueChoice = .standard,
                postsSystemNotification: Bool = false,
                motion: MotionLevel = .full,
                followsSystemReduceMotion: Bool = true,
                rightFlank: RightFlank = .sessionCount,
                coat: Coat = .tabby,
                cardOptions: SessionCardOptions = SessionCardOptions(),
                handBackToTerminalAfter: Double? = 1.0) {
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
        self.motion = motion
        self.followsSystemReduceMotion = followsSystemReduceMotion
        self.rightFlank = rightFlank
        self.coat = coat
        self.cardOptions = cardOptions
        self.handBackToTerminalAfter = handBackToTerminalAfter
    }
}
