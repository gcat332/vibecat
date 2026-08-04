import SwiftUI
import VibeCatCore

/// §14's Sound group — Plan 6.5 Task 6, `settings.html:339-361`. Six rows: the
/// pack picker, three per-cue pickers each with a `Play` button, the volume
/// slider, and the Do Not Disturb switch.
///
/// **Not yet reachable from the running app.** `SettingsPage.ownerNote(for:)`
/// still shows 6.4's placeholder for `"notifications"`, and `SettingsShell`
/// does not construct this type — Task 7 assembles the whole page (this
/// group plus `Alert me when an agent` and `Elsewhere`) and retires the
/// owner note. Building and testing this section in isolation first is the
/// same order Tasks 2 and 3 built their primitives in, before anything used
/// them.
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
