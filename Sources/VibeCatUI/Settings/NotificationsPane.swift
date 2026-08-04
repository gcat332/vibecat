import AppKit
import SwiftUI
import VibeCatCore

/// §14's Notifications page, assembled — `settings.html:323-378`, all three
/// groups in the prototype's own order: `Alert me when an agent`, `Sound`
/// (marked `new`), `Elsewhere`.
///
/// **This is what retired 6.4's owner note for `"notifications"`.** The note
/// existed so a pane with no controls would read as a schedule rather than a
/// bug; the controls are here, so `SettingsPage.ownerNote(for:)` now returns
/// `nil` for this key and `SettingsPaneView` draws this instead. The other three
/// panes keep theirs, and `everyPaneWithoutControlsAnnouncesWhichPlanOwnsThem`
/// in `SettingsSidebarTests` holds that line.
///
/// # The browser diff, 2026-08-04
///
/// `settings.html` was opened in Chrome (macOS 26.5.2) with this pane forced
/// active, and every element of it measured with `getBoundingClientRect` and
/// `getComputedStyle` against this implementation's own rasters. What agrees is
/// not listed here; what differs is, because a divergence nobody wrote down gets
/// re-introduced by the next person who notices it.
///
/// **Confirmed exact** (worth naming, because each was a guess before): `.row`
/// `padding:11px 14px` and `gap:14px` — a plain switch row is `44px` in the
/// browser and `44pt` here, and the track's right edge sits at `width − 14` in
/// both, now pinned by `theRowsPaddingIsThePrototypesElevenAndFourteen`; `.sw`
/// `38×22`; `.pill` `61.98×13.5` with a `13px` dot and a `9px` glyph in `#111`;
/// `.new` `9.5px/0.57px/1px @45%/radius 4/1-5 padding/margin-left 7`; the
/// detail line's `line-height:16.675px`; `.ctlarea{width:180px}` on the volume
/// row and its `value="60"`; every colour token (`--card` `rgb(42,42,45)`,
/// `--card2` `rgb(50,50,54)`, `--haze` `rgb(154,154,162)`, `--blue`
/// `rgb(10,132,255)`, `.sw` off `rgb(72,72,78)`, `.pill.ok` `rgb(63,217,155)`).
/// And `.group > .row:first-child{box-shadow:none}` reads `none` on all three
/// groups' first rows, which is what Task 7 implemented and Task 2 had recorded
/// as missing.
///
/// **Six differences, all recorded, three fixed:**
///
/// 1. **The prototype never has to scroll, and we do — fixed by the
///    `ScrollView` in `SettingsPaneView`.** `.body{min-height:620px}` is a
///    *min*: with this pane active the browser's `.win` grows to `914.2px` and
///    the pane itself is `802.2px` tall. A real `NSWindow` cannot grow to fit,
///    and 6.4 pinned the content area at `900×620`, so 771pt of page has to
///    scroll inside 552pt. The prototype is simply silent on this, not
///    permissive: nothing in it is ever clipped.
/// 2. **A detail row is `1.67pt` shorter here** (`55` against `56.67`), and a
///    heading `1pt` taller (`23` against `22`) — so the assembled page comes out
///    ~7pt shorter than the browser's. Both are the half-leading trade
///    `SettingsPaneView.ownerNote` already recorded and chose: CSS pads half a
///    line above the first line and below the last, `lineSpacing` cannot, and
///    matching the block height would visibly widen the line pitch. Pitch wins;
///    the residue is this.
/// 3. **`.sel` had no disclosure arrow — fixed.** The prototype's is a real
///    `<select>`, so the browser draws the arrow and no CSS rule mentions it:
///    `148.5px` wide against `129pt` of text and padding here. A hand-drawn
///    select with no arrow reads as static text, which is a lost affordance
///    rather than a lost pixel. See `SettingsSelect.body`.
/// 4. **The volume control is not the prototype's.** `input[type=range]` is a
///    `180×4` track with an overflowing thumb; SwiftUI's `Slider` is `180×16`
///    with a larger knob, which makes that row `38pt` against `37px`. Task 6
///    left this open explicitly ("may yet turn this into a fourth hand-drawn
///    control"); it stays open, because the row height agrees to a point and the
///    control is the platform's own.
/// 5. **`.btn` is `27pt` here against `26.5px`, `.sel` `26pt` against `27px`.**
///    Sub-point font-metric differences between Chrome's line boxes and
///    AppKit's, in opposite directions; both rows they sit in agree to within a
///    point. Not chased.
/// 6. **The content column is `656pt` wide against the prototype's `654px`.**
///    Already recorded by 6.4: `.win`'s `1px` border is the browser standing in
///    for window chrome AppKit draws outside the content rect.
struct NotificationsPane: View {
    let model: NotificationsPaneModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AlertsSection(model: model)
            SoundSection(model: model.sound)
            ElsewhereSection(model: model)
        }
        // A fresh read whenever the page comes up: a permission granted in
        // System Settings — quite possibly *from this page's own button*, which
        // is the whole point of that button — changes nothing here until
        // something asks the system again.
        .onAppear { model.notifier.refresh() }
    }
}

/// `settings.html:326-337`'s `Alert me when an agent` — four switches, and the
/// only page in this app whose controls change what the event pipeline does
/// rather than how it looks.
///
/// **Written decision 4, restated where the switches are:** these gate the
/// *cue* and the *notification*, never the island's own report. Turning
/// `Needs an answer` off does not stop a blocked agent turning the island
/// amber or opening the drawer — §4.2's worst-state-wins is not a preference.
struct AlertsSection: View {
    let model: NotificationsPaneModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeading("Alert me when an agent")
            SettingsGroup {
                SettingsRow("Needs an answer") {
                    SettingsSwitch(isOn: model.onNeedsAnswerBinding)
                }
                SettingsRow("Finishes") {
                    SettingsSwitch(isOn: model.onFinishBinding)
                }
                SettingsRow("Fails") {
                    SettingsSwitch(isOn: model.onFailBinding)
                }
                // The one switch the prototype ships off (`aria-checked="false"`,
                // `:334`) and the one marked `new`. Its sub-label is
                // `StallDetector`'s own specification, quoted verbatim from
                // `settings.html:335`.
                SettingsRow("Stalls for 5 minutes",
                    detail: "Nothing has happened in the session and no question is pending.",
                    isNew: true) {
                    SettingsSwitch(isOn: model.onStallBinding)
                }
            }
        }
    }
}

/// `settings.html:364-377`'s `Elsewhere`: the system-notification switch, and
/// the two permission rows §15 names.
///
/// **Both permission rows are reports, not requests** — each is a `.pill` plus
/// a `System Settings…` `.btn`, exactly as the prototype draws them
/// (`:369-376`). Neither button prompts: notification authorization is asked
/// for once at launch (`main.swift`), and Automation is never asked for at all
/// until jump ships (written decision 2). A button that opens the pane where
/// the user can change their mind is the honest control for a permission this
/// app cannot re-ask for.
///
/// `Automation permission`'s detail line — *"macOS requires this to focus a
/// terminal window on your behalf."* — is the prototype's (`:374`), and it is
/// **not** in the plan's own summary of this page's contents. The prototype is
/// the authority on appearance; the summary was lossy.
///
/// **What `Also post a system notification` gates, written down because the
/// answer has a consequence.** §14 calls this the *system notification
/// fallback*, so it is the channel's own switch: nothing posts while it is off.
/// The one producer today is a stall (`Notifier.postStalls`), which means a user
/// who turns `Stalls for 5 minutes` on and leaves this off gets **no alert at
/// all** — a stall has no `Cue` (§12 defines five, none of them "stalled") and
/// no island state of its own, so this channel is the only thing it could ever
/// reach. Recorded rather than quietly resolved either way: the alternative,
/// letting a stall post regardless, would make a switch that says it controls
/// notifications not control one, which is worse. Wiring the other three
/// triggers to this channel is not this task's — a *fallback* implies knowing
/// the island cannot be seen, and nothing in the app measures that yet.
struct ElsewhereSection: View {
    let model: NotificationsPaneModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeading("Elsewhere")
            SettingsGroup {
                SettingsRow("Also post a system notification",
                    detail: "Reaches you when the island is on another Space or a "
                        + "fullscreen app is in front.") {
                    SettingsSwitch(isOn: model.postsSystemNotificationBinding)
                }
                SettingsRow("Notification permission") {
                    SettingsPill(model.notifier.notificationPermission)
                    SettingsButton("System Settings…") {
                        model.openSystemSettings(.notifications)
                    }
                }
                SettingsRow("Automation permission",
                    detail: "macOS requires this to focus a terminal window on your behalf.") {
                    SettingsPill(model.notifier.automationPermission)
                    SettingsButton("System Settings…") {
                        model.openSystemSettings(.automation)
                    }
                }
            }
        }
    }
}

/// Everything the Notifications page reads and writes, in one observable place.
///
/// The same shape as `SoundSectionModel` (which it owns) and
/// `SettingsWindowModel`, and for the same three reasons: every write is a named
/// method doing `load()` / mutate / `save(_:)` against the store **as it is
/// right now** rather than against a held snapshot (this page alone adds ten
/// writers, and `save(_:)` writes the whole struct); every binding goes through
/// one of those methods rather than `@Bindable`'s straight-to-storage form, which
/// is how `selectedPage` shipped persisted-by-nothing; and the one side effect
/// that touches the OS — opening System Settings — is a closure, so a test can
/// see which pane a button asked for without a window server or a real
/// `NSWorkspace`.
@MainActor @Observable final class NotificationsPaneModel {
    /// Task 6's section, owned rather than rebuilt: the pack, the three per-cue
    /// choices, the volume and the Do Not Disturb switch all live there.
    let sound: SoundSectionModel
    /// Task 7's, read by both permission rows. `@Observable` itself, so a
    /// permission read that lands after the page is drawn redraws the pills.
    let notifier: Notifier

    private(set) var alerts: AlertPolicy
    private(set) var postsSystemNotification: Bool

    private let store: PreferenceStoring
    private let openPane: (SystemSettingsPane) -> Void

    init(store: PreferenceStoring, sound: SoundSectionModel, notifier: Notifier = Notifier(),
         openPane: @escaping (SystemSettingsPane) -> Void = { pane in
            NSWorkspace.shared.open(pane.url)
         }) {
        let prefs = store.load()
        self.alerts = prefs.alerts
        self.postsSystemNotification = prefs.postsSystemNotification
        self.store = store
        self.sound = sound
        self.notifier = notifier
        self.openPane = openPane
    }

    /// The shape production reaches for: one store, one live sound engine.
    convenience init(store: PreferenceStoring,
                     syncSoundSettings: @escaping (SoundSettings) -> Void,
                     playCue: @escaping (Cue) -> Void) {
        self.init(store: store,
                  sound: SoundSectionModel(store: store, syncSettings: syncSoundSettings,
                                           playCue: playCue))
    }

    // MARK: - Bindings

    var onNeedsAnswerBinding: Binding<Bool> {
        Binding(get: { self.alerts.onNeedsAnswer }, set: { self.setOnNeedsAnswer($0) })
    }
    var onFinishBinding: Binding<Bool> {
        Binding(get: { self.alerts.onFinish }, set: { self.setOnFinish($0) })
    }
    var onFailBinding: Binding<Bool> {
        Binding(get: { self.alerts.onFail }, set: { self.setOnFail($0) })
    }
    var onStallBinding: Binding<Bool> {
        Binding(get: { self.alerts.onStall }, set: { self.setOnStall($0) })
    }
    var postsSystemNotificationBinding: Binding<Bool> {
        Binding(get: { self.postsSystemNotification },
                set: { self.setPostsSystemNotification($0) })
    }

    // MARK: - Writers
    //
    // **Four near-identical bodies over one nested struct is a sharper version
    // of the defect class `SoundSectionModel`'s writers already name**: here a
    // copy-paste slip does not even change the type it assigns to, because all
    // four fields of `AlertPolicy` are `Bool`. So each is mutation-verified by
    // hand, one at a time — point a setter at a neighbour's field, confirm the
    // matching `NotificationsPaneTests` case goes red, revert. The table is in
    // this task's report.
    //
    // No `syncSettings` call in any of them, unlike Task 6's writers: nothing
    // caches an `AlertPolicy`. `AppModel.applyAndNotify` reads
    // `preferences.load().alerts` fresh on every event and `Notifier
    // .postStalls` reads `postsSystemNotification` fresh on every stall, so a
    // saved switch is live on the next event with nothing else to wire. That is
    // the property that makes this page not decorative, and it is asserted end
    // to end by `aFlippedSwitchSilencesTheVeryNextEvent`.

    func setOnNeedsAnswer(_ value: Bool) {
        guard value != alerts.onNeedsAnswer else { return }
        alerts.onNeedsAnswer = value
        var prefs = store.load()
        prefs.alerts.onNeedsAnswer = value
        store.save(prefs)
    }

    func setOnFinish(_ value: Bool) {
        guard value != alerts.onFinish else { return }
        alerts.onFinish = value
        var prefs = store.load()
        prefs.alerts.onFinish = value
        store.save(prefs)
    }

    func setOnFail(_ value: Bool) {
        guard value != alerts.onFail else { return }
        alerts.onFail = value
        var prefs = store.load()
        prefs.alerts.onFail = value
        store.save(prefs)
    }

    func setOnStall(_ value: Bool) {
        guard value != alerts.onStall else { return }
        alerts.onStall = value
        var prefs = store.load()
        prefs.alerts.onStall = value
        store.save(prefs)
    }

    func setPostsSystemNotification(_ value: Bool) {
        guard value != postsSystemNotification else { return }
        postsSystemNotification = value
        var prefs = store.load()
        prefs.postsSystemNotification = value
        store.save(prefs)
    }

    // MARK: - The two buttons

    /// Recorded before the closure fires, for the same reason
    /// `SoundSectionModel.lastPlayedCueForTesting` exists: the thing a
    /// copy-paste error would get wrong here is *which pane* a row's button
    /// asked for, and a real `NSWorkspace.open` proves nothing headlessly.
    private(set) var lastOpenedPaneForTesting: SystemSettingsPane?

    func openSystemSettings(_ pane: SystemSettingsPane) {
        lastOpenedPaneForTesting = pane
        openPane(pane)
    }
}

/// §14's Sound group — Plan 6.5 Task 6, `settings.html:339-361`. Six rows: the
/// pack picker, three per-cue pickers each with a `Play` button, the volume
/// slider, and the Do Not Disturb switch.
///
/// Assembled into the real page by `NotificationsPane` (below, Task 7), which
/// is also where 6.4's `"notifications"` owner note was retired.
///
/// **Everything this section writes goes through `SoundSectionModel`, never
/// a stored property directly** — see that type's own doc comment for why a
/// `@Bindable`-style direct write was rejected the same way
/// `SettingsWindowModel.pageBinding` already rejected it for the sidebar.
struct SoundSection: View {
    let model: SoundSectionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeading("Sound", isNew: true)
            SettingsGroup {
                SettingsRow("Sound pack",
                    detail: "Synthesised on the fly — no audio files, so a pack is a "
                        + "handful of oscillator settings.") {
                    SettingsSelect(model.packBinding, label: Self.packLabel)
                }
                SettingsRow("Needs an answer", detail: "G5–C6–E6 rising, held on C6.") {
                    SettingsSelect(model.choiceForNeedsAnswerBinding, label: Self.needsAnswerLabel)
                    SettingsButton("Play") { model.playNeedsAnswer() }
                }
                SettingsRow("Finished",
                    detail: "Major arpeggio over two octaves, held at the top.") {
                    SettingsSelect(model.choiceForFinishBinding, label: Self.finishLabel)
                    SettingsButton("Play") { model.playFinish() }
                }
                SettingsRow("Failed",
                    detail: "Falling minor thirds on a saw, sagging at the end.") {
                    SettingsSelect(model.choiceForFailBinding, label: Self.failLabel)
                    SettingsButton("Play") { model.playFail() }
                }
                SettingsRow("Volume") {
                    // `settings.html:358`'s `.ctlarea{width:180px}` — the one row
                    // whose control area gets an explicit width rather than
                    // hugging its content, because a slider has none of its own.
                    //
                    // A plain `Slider`, not hand-drawn like `.sel`/`.btn`/`.sw`:
                    // none of those three were hand-drawn on a whim — each had a
                    // measured, documented reason (`SettingsControls.swift`,
                    // `SettingsSwitch.swift`) that a native control drew the
                    // wrong colour or the wrong size. Nothing here measured the
                    // same failure for `Slider`, and Task 6's own required tests
                    // are about *wiring* (what the commit writes, when it
                    // writes), not about matching this control's exact pixels —
                    // that comparison is Task 7's browser diff, which may yet
                    // turn this into a fourth hand-drawn control with its own
                    // written reason.
                    Slider(value: model.volumeBinding, in: 0...1,
                          onEditingChanged: model.volumeEditingChanged)
                        .tint(Color(SettingsPalette.systemBlue))
                        .frame(width: 180)
                }
                SettingsRow("Stay quiet during Do Not Disturb") {
                    SettingsSwitch(isOn: model.quietDuringDoNotDisturbBinding)
                }
            }
        }
    }

    // MARK: - Per-row labels
    //
    // Six near-identical rows is this task's own named defect class — a label
    // closure copied and only half-edited would show the wrong "(default)"
    // name against the right cue and nothing would render differently enough
    // to notice by eye. Each function below is named for the row it belongs
    // to and returns exactly the prototype's own option text
    // (`settings.html:341-357`), minus `Blip`/`Buzz`/`Soft`/`System` — written
    // decision 1, nothing in this repo defines what any of those four sound
    // like.

    static func packLabel(_ pack: SoundPack) -> String {
        switch pack {
        case .chiptune: "Chiptune (default)"
        case .silent:   "Silent"
        }
    }

    static func needsAnswerLabel(_ choice: CueChoice) -> String {
        switch choice {
        case .standard: "Rising call (default)"
        case .meow:     "Meow"
        case .none:     "None"
        }
    }

    static func finishLabel(_ choice: CueChoice) -> String {
        switch choice {
        case .standard: "Arpeggio (default)"
        case .meow:     "Meow"
        case .none:     "None"
        }
    }

    static func failLabel(_ choice: CueChoice) -> String {
        switch choice {
        case .standard: "Falling thirds (default)"
        case .meow:     "Meow"
        case .none:     "None"
        }
    }
}

/// Everything the Sound section reads and writes, in one observable place —
/// the same shape as `SettingsWindowModel` and for the same reason: every
/// write goes through a named method that does read-modify-write against the
/// store *as it is right now* (never a snapshot this object is holding, per
/// the Global Constraint — `store.load()` happens inside each setter, not
/// once in `init` and reused), and then keeps the live `SoundPlayer` this
/// section previews through in step, so a choice made here is audible on the
/// very next `Play` without needing the pane to be reopened.
///
/// **The volume hazard this exists to close.** Plan 6.4 measured that
/// changing `SoundSettings.volume` moves the render's own cache key, so the
/// first cue rendered after a volume change re-pays the full render cost for
/// every cue not already cached — 859ms for `error` alone in a debug build,
/// measured with the whole-settings key this repo shipped before that plan's
/// own fix round. A `Slider` reports a new value on every drag frame, and a
/// naive `Binding` that called `commitVolume()` on each one would pay that
/// cost dozens of times over a single drag gesture. So `volume` is a live,
/// side-effect-free property — reading and writing it only moves the number
/// the `Slider` shows — and `commitVolume()`, the only thing that touches the
/// store or the player, fires exactly once, from `volumeEditingChanged(_:)`
/// on release. `SoundSectionTests.volumeDragCost` measures both shapes with
/// `getrusage(RUSAGE_SELF)`, never `ps %cpu`.
@MainActor @Observable final class SoundSectionModel {
    private(set) var pack: SoundPack
    private(set) var choiceForNeedsAnswer: CueChoice
    private(set) var choiceForFinish: CueChoice
    private(set) var choiceForFail: CueChoice
    /// The live drag value. Reading and writing this alone never reaches the
    /// store or the player — see this type's own doc comment.
    var volume: Double
    private(set) var quietDuringDoNotDisturb: Bool

    private let store: PreferenceStoring
    /// Where a write's fresh `SoundSettings` reaches the engine this section
    /// previews through — a closure over `player.settings = `, not a held
    /// `SoundPlayer`, for the same reason `SettingsWindowModel.persist` is a
    /// closure over a store rather than the store itself: a test can
    /// substitute a spy with no real `AVAudioEngine` behind it at all.
    ///
    /// **That distinction is load-bearing here in a way it merely would have
    /// been convenient elsewhere.** A real `SoundPlayer.play(_:)` for an
    /// uncached cue renders on a background `DispatchQueue`, fire-and-forget
    /// — `.error`'s 94-harmonic sawtooth costs ~858ms of real CPU on a real
    /// thread that outlives the call, and outlives the test that made it.
    /// Measured against this suite: with `eachPlayButtonReachesItsOwnRowsCue`
    /// driving a real `SoundPlayer`, `swift test` (full suite) failed
    /// `PipelineTests.aPermissionAnsweredInTheIslandReachesTheCLI` — an
    /// already-documented ~1-in-20 flake — 3 times in 8 runs; the identical
    /// suite without this file failed it 0 times in 8. Closures let that test
    /// assert on `Cue` values reaching a spy instead of provoking a real
    /// background render, which is the fix; see `SoundSectionTests`' own
    /// header note for the full comparison.
    private let syncSettings: (SoundSettings) -> Void
    private let playCue: (Cue) -> Void

    /// The shape a test reaches for: no `SoundPlayer`, no `AVAudioEngine`, just
    /// two closures a spy can record calls to.
    init(store: PreferenceStoring, syncSettings: @escaping (SoundSettings) -> Void,
         playCue: @escaping (Cue) -> Void) {
        let prefs = store.load()
        pack = prefs.pack
        choiceForNeedsAnswer = prefs.choiceForNeedsAnswer
        choiceForFinish = prefs.choiceForFinish
        choiceForFail = prefs.choiceForFail
        volume = prefs.volume
        quietDuringDoNotDisturb = prefs.quietDuringDoNotDisturb
        self.store = store
        self.syncSettings = syncSettings
        self.playCue = playCue
        // The engine this section previews through starts in step with
        // whatever is actually stored, the moment the pane is built — not
        // whatever it happened to be constructed with. `SoundSettings(_:)`
        // is the one place that mapping already lives.
        syncSettings(SoundSettings(prefs))
    }

    /// The shape production reaches for: a real `SoundPlayer`, wired through
    /// exactly the two operations above.
    convenience init(store: PreferenceStoring, player: SoundPlayer) {
        self.init(store: store,
                  syncSettings: { player.settings = $0 },
                  playCue: { player.play($0) })
    }

    // MARK: - Bindings
    //
    // `Binding(get:set:)` over the model's own setters, never `@Bindable`'s
    // direct-to-storage form — `SettingsWindowModel.pageBinding`'s own doc
    // comment already recorded why: a binding that writes the stored property
    // straight through is a binding with no seam for persistence to hang off,
    // which is exactly how `selectedPage` shipped unpersisted the first time.

    var packBinding: Binding<SoundPack> {
        Binding(get: { self.pack }, set: { self.setPack($0) })
    }
    var choiceForNeedsAnswerBinding: Binding<CueChoice> {
        Binding(get: { self.choiceForNeedsAnswer }, set: { self.setChoiceForNeedsAnswer($0) })
    }
    var choiceForFinishBinding: Binding<CueChoice> {
        Binding(get: { self.choiceForFinish }, set: { self.setChoiceForFinish($0) })
    }
    var choiceForFailBinding: Binding<CueChoice> {
        Binding(get: { self.choiceForFail }, set: { self.setChoiceForFail($0) })
    }
    var quietDuringDoNotDisturbBinding: Binding<Bool> {
        Binding(get: { self.quietDuringDoNotDisturb }, set: { self.setQuietDuringDoNotDisturb($0) })
    }
    /// The live drag value only — see `volume`'s own doc comment. This does
    /// **not** route through a setter that touches the store; that is the
    /// entire point of it.
    var volumeBinding: Binding<Double> {
        Binding(get: { self.volume }, set: { self.volume = $0 })
    }

    // MARK: - Writers
    //
    // One method per field, each doing its own `store.load()` /
    // `store.save(_:)` — never a `Preferences` snapshot held across the six
    // rows and saved once, which is the shape that would let two rows'
    // writes race and one silently clobber the other, per the Global
    // Constraint that `save(_:)` writes the whole struct.
    //
    // **Six near-identical bodies is this task's own named defect class.**
    // Mutation-verified by hand, one at a time: pointing each setter at a
    // neighbour's `Preferences` field, confirming the corresponding
    // `SoundSectionTests` case goes red, then reverting. See the task report
    // for the table.
    //
    // Each writer calls `syncSettings(SoundSettings(prefs))` with the very
    // `Preferences` it just saved, not a hand-built partial update — so the
    // engine sees every field the store currently holds (including whatever
    // another surface, e.g. the panel's mute toggle, wrote to `soundEnabled`
    // between this row's `load()` and now), never only the one field this
    // writer itself cares about.

    func setPack(_ value: SoundPack) {
        guard value != pack else { return }
        pack = value
        var prefs = store.load()
        prefs.pack = value
        store.save(prefs)
        syncSettings(SoundSettings(prefs))
    }

    func setChoiceForNeedsAnswer(_ value: CueChoice) {
        guard value != choiceForNeedsAnswer else { return }
        choiceForNeedsAnswer = value
        var prefs = store.load()
        prefs.choiceForNeedsAnswer = value
        store.save(prefs)
        syncSettings(SoundSettings(prefs))
    }

    func setChoiceForFinish(_ value: CueChoice) {
        guard value != choiceForFinish else { return }
        choiceForFinish = value
        var prefs = store.load()
        prefs.choiceForFinish = value
        store.save(prefs)
        syncSettings(SoundSettings(prefs))
    }

    func setChoiceForFail(_ value: CueChoice) {
        guard value != choiceForFail else { return }
        choiceForFail = value
        var prefs = store.load()
        prefs.choiceForFail = value
        store.save(prefs)
        syncSettings(SoundSettings(prefs))
    }

    func setQuietDuringDoNotDisturb(_ value: Bool) {
        guard value != quietDuringDoNotDisturb else { return }
        quietDuringDoNotDisturb = value
        var prefs = store.load()
        prefs.quietDuringDoNotDisturb = value
        store.save(prefs)
        syncSettings(SoundSettings(prefs))
    }

    /// `Slider(onEditingChanged:)`'s own contract: `true` when a drag begins,
    /// `false` exactly once, when it ends. Only the `false` edge commits —
    /// see this type's own doc comment on the render cost a per-frame commit
    /// would pay.
    func volumeEditingChanged(_ editing: Bool) {
        guard !editing else { return }
        commitVolume()
    }

    /// The only thing that writes `volume` to the store or the engine.
    /// `public` (well, internal) rather than `private` so a test can call it
    /// directly — nothing headless can drive a real `Slider`'s drag gesture
    /// to its release, the same limit `SettingsButton.actionForTesting()`
    /// already documents for a `Button` tap.
    func commitVolume() {
        let clamped = SoundSettings.clampedVolume(volume)
        volume = clamped
        var prefs = store.load()
        prefs.volume = clamped
        store.save(prefs)
        syncSettings(SoundSettings(prefs))
    }

    // MARK: - Play
    //
    // **Bypasses `AlertPolicy` entirely, and must.** This model never holds
    // one — there is no field here an `AlertPolicy` could gate — so a
    // silenced "Needs an answer" switch has no way to reach into this preview
    // at all. That is deliberate, not an oversight: Task 4's own last
    // mutation was `AppModel` passing a default policy instead of the user's
    // stored one, which would leave the *real* event pipeline decorative
    // while looking, from this button alone, exactly as if it worked. A
    // working `Play` proves the engine can render and schedule a cue; it
    // proves nothing about whether an actual agent event would have reached
    // it. Recorded here rather than left for a future reader to assume
    // otherwise from a green suite and a button that audibly (unverified —
    // see `SoundPlayer`'s own doc comment) works.

    /// `internal`, for `SoundSectionTests` only — the same shape as
    /// `SettingsButton.actionForTesting()` and `PanelBar.toggleMuteForTesting()`:
    /// nothing headless can observe a real `AVAudioEngine` finish playing, so
    /// this records which `Cue` the last `play…()` call actually reached the
    /// player with. That is the thing a copy-paste wiring error — a row's
    /// `Play` button reaching for another row's cue — would get wrong.
    private(set) var lastPlayedCueForTesting: Cue?

    private func play(_ cue: Cue) {
        lastPlayedCueForTesting = cue
        playCue(cue)
    }

    func playNeedsAnswer() { play(.ask) }
    func playFinish() { play(.done) }
    func playFail() { play(.error) }
}
