import Testing
import Foundation
@testable import VibeCatUI
import VibeCatCore

/// `SoundSectionModel` and the note-resolution it wires up in `SoundPack.swift`
/// / `SoundPlayer.swift` — Plan 6.5 Task 6.
///
/// **Six near-identical writers is this task's own named defect class.**
/// The settings-writer tests below, plus the volume and Do Not Disturb cases
/// beside them, are what a copy-paste error — one control's setter reaching
/// into a neighbour's `Preferences` field — would break. Every one of the six
/// was mutation-verified by hand: the setter's own field swapped for a
/// neighbour's, `swift build` (compiles, since both sides are the same
/// type), `swift test --filter` (the corresponding test goes red), then
/// reverted. See the task report for the table.
///
/// **Spies, not a real `SoundPlayer`, for every test that is not itself about
/// rendering.** `SoundSectionModel` takes two closures (`syncSettings`,
/// `playCue`) rather than a concrete `SoundPlayer` for exactly this reason —
/// see that type's own doc comment. First shipped with a real `SoundPlayer`
/// behind every test here (`Self.makeModel` constructing one directly), and
/// `eachPlayButtonReachesItsOwnRowsCue` calling `model.playFail()` reached a
/// real, uncached `.error` render on `SoundPlayer`'s own background
/// `DispatchQueue` — fire-and-forget, ~858ms of real CPU that outlives the
/// test. Measured against the full suite: with that version, `swift test`
/// failed `PipelineTests.aPermissionAnsweredInTheIslandReachesTheCLI` (an
/// already-documented ~1-in-20 flake) 3 times in 8 full runs; the baseline
/// without this file failed it 0 times in 8. Switching every test that does
/// not need real audio to closures over a plain spy — and keeping the two
/// tests that genuinely exercise `SoundPlayer`'s cache down to its cheapest
/// cues (`.ask`, `.done`, never `.error`) — brought that back to 0 failures
/// in 8 full runs, reported in the task report rather than left assumed.
@Suite("Sound section")
struct SoundSectionTests {
    /// Records what a real `SoundPlayer` would have been told, with none of
    /// the cost of actually being one.
    @MainActor
    final class EngineSpy {
        private(set) var lastSettings: SoundSettings?
        private(set) var playedCues: [Cue] = []
        func sync(_ settings: SoundSettings) { lastSettings = settings }
        func play(_ cue: Cue) { playedCues.append(cue) }
    }

    @MainActor
    static func makeModel(_ prefs: Preferences = Preferences())
        -> (model: SoundSectionModel, store: InMemoryPreferenceStore, spy: EngineSpy) {
        let store = InMemoryPreferenceStore(prefs)
        let spy = EngineSpy()
        let model = SoundSectionModel(store: store, syncSettings: spy.sync, playCue: spy.play)
        return (model, store, spy)
    }

    // MARK: - Each control writes its own field, and only its own field

    @Test @MainActor func settingThePackWritesOnlyPack() {
        let (model, store, spy) = Self.makeModel()
        model.setPack(.silent)
        #expect(store.load().pack == .silent)
        #expect(spy.lastSettings?.pack == .silent)
        // Untouched: a crossed key here would show up as one of these moving
        // instead.
        #expect(store.load().choiceForNeedsAnswer == .standard)
        #expect(store.load().choiceForFinish == .standard)
        #expect(store.load().choiceForFail == .standard)
    }

    @Test @MainActor func settingNeedsAnswerWritesOnlyItsOwnChoice() {
        let (model, store, spy) = Self.makeModel()
        model.setChoiceForNeedsAnswer(.meow)
        #expect(store.load().choiceForNeedsAnswer == .meow)
        #expect(spy.lastSettings?.choiceForNeedsAnswer == .meow)
        #expect(store.load().choiceForFinish == .standard, "finish's key is crossed")
        #expect(store.load().choiceForFail == .standard, "fail's key is crossed")
    }

    @Test @MainActor func settingFinishWritesOnlyItsOwnChoice() {
        let (model, store, spy) = Self.makeModel()
        model.setChoiceForFinish(.none)
        #expect(store.load().choiceForFinish == .none)
        // `CueChoice.none`, spelled out — `spy.lastSettings?.choiceForFinish`
        // is `CueChoice?`, and a bare `.none` there is genuinely ambiguous
        // between "the `CueChoice` case named `none`" and "`Optional.none`",
        // i.e. nil. Caught by running this exact line: it read as `true`
        // against a `nil` `lastSettings`, which is not what this test claims
        // to check at all.
        #expect(spy.lastSettings?.choiceForFinish == CueChoice.none)
        #expect(store.load().choiceForNeedsAnswer == .standard, "needsAnswer's key is crossed")
        #expect(store.load().choiceForFail == .standard, "fail's key is crossed")
    }

    @Test @MainActor func settingFailWritesOnlyItsOwnChoice() {
        let (model, store, spy) = Self.makeModel()
        model.setChoiceForFail(.meow)
        #expect(store.load().choiceForFail == .meow)
        #expect(spy.lastSettings?.choiceForFail == .meow)
        #expect(store.load().choiceForNeedsAnswer == .standard, "needsAnswer's key is crossed")
        #expect(store.load().choiceForFinish == .standard, "finish's key is crossed")
    }

    @Test @MainActor func settingQuietDuringDoNotDisturbWritesOnlyItself() {
        let (model, store, spy) = Self.makeModel()
        model.setQuietDuringDoNotDisturb(false)
        #expect(store.load().quietDuringDoNotDisturb == false)
        #expect(spy.lastSettings?.quietDuringDoNotDisturb == false)
        #expect(store.load().volume == Preferences().volume, "volume's key is crossed")
        #expect(store.load().pack == .chiptune, "pack's key is crossed")
    }

    // MARK: - The volume hazard: commit on release, clamped

    @Test @MainActor func aDragFrameDoesNotWriteTheStoreOrTheEngine() {
        // The premise a naive `Binding` would violate: reading and writing
        // `volume` directly must never itself reach the store or the engine —
        // that is the whole fix for the measured 859ms-per-frame hazard.
        //
        // `spy.lastSettings` is not `nil` here — `init` syncs the engine once,
        // immediately, so the pane opens in step with the store (this type's
        // own doc comment). The claim under test is narrower: a drag frame
        // must not move it *again* past whatever `init` already set.
        let (model, store, spy) = Self.makeModel()
        let atOpen = spy.lastSettings
        model.volume = 0.05
        model.volume = 0.90
        model.volumeEditingChanged(true)   // still dragging
        #expect(store.load().volume == Preferences().volume, "a drag frame wrote the store")
        #expect(spy.lastSettings == atOpen, "a drag frame reached the engine")
    }

    @Test @MainActor func releasingTheSliderCommitsTheLiveValue() {
        let (model, store, spy) = Self.makeModel()
        model.volume = 0.31
        model.volumeEditingChanged(false)   // release
        #expect(store.load().volume == 0.31)
        #expect(spy.lastSettings?.volume == 0.31)
    }

    @Test @MainActor func theCommittedVolumeIsClampedRegardlessOfWhichStoreItReaches() {
        // `InMemoryPreferenceStore` does not clamp and `UserDefaultsPreferenceStore`
        // does (Global Constraint) — this model must not depend on either, so the
        // clamp has to be the model's own.
        let (model, store, spy) = Self.makeModel()
        model.volume = 4.2
        model.commitVolume()
        #expect(store.load().volume == 1.0)
        #expect(spy.lastSettings?.volume == 1.0)
    }

    // MARK: - The engine: a per-cue choice actually changes what renders
    //
    // The only two tests in this file that touch a real `SoundPlayer` —
    // deliberately restricted to `.ask`/`.done` (≈44ms/≈59ms to render in a
    // debug build) and never `.error` (≈858ms), for the reason this file's
    // own header note measures.

    @Test @MainActor func aNoneChoiceRendersNothingWhileTheOtherCuesStillRender() {
        var settings = SoundSettings()
        settings.choiceForNeedsAnswer = .none
        let player = SoundPlayer(settings: settings, quietHours: NeverQuiet())
        #expect(player.buffer(for: .ask) == nil, "'None' must render nothing for its own cue")
        #expect(player.buffer(for: .askMulti) == nil, "askMulti shares the same row's choice")
        #expect(player.buffer(for: .done) != nil, "a sibling row's cue must still render")
    }

    @Test @MainActor func aMeowChoiceSubstitutesTheMeowTableForThatCueOnly() {
        // `.done`/`choiceForFinish`, not `.error`/`choiceForFail` — the logic
        // under test (`SoundSettings.notes(for:)`) is identical across all
        // three rows.
        var settings = SoundSettings()
        settings.choiceForFinish = .meow
        let meowyDone = CueRenderer.render(.done, settings: settings, sampleRate: 48_000)
        let plainDone = CueRenderer.render(.done, settings: SoundSettings(), sampleRate: 48_000)
        let plainMeow = CueRenderer.render(.meow, settings: SoundSettings(), sampleRate: 48_000)
        #expect(meowyDone != plainDone, "the override did nothing")
        #expect(meowyDone == plainMeow, "the override did not actually substitute meow's own table")
        // A sibling row's cue, given the same settings, is untouched.
        let ask = CueRenderer.render(.ask, settings: settings, sampleRate: 48_000)
        let plainAsk = CueRenderer.render(.ask, settings: SoundSettings(), sampleRate: 48_000)
        #expect(ask == plainAsk, "finish's override leaked into needsAnswer's cue")
    }

    @Test @MainActor func aCachedCueIsInvalidatedWhenItsOwnChoiceChanges() {
        // The cache-key hazard this task's own comment in `SoundPlayer.swift`
        // records: a buffer rendered under one choice must not survive a
        // change to that choice, or a "Needs an answer" switched from
        // standard to Meow mid-session would keep playing the old rising
        // call from cache for the rest of the session. Driven through the
        // model (so the write path is real) but checked against a real,
        // separate `SoundPlayer` fed the spy's recorded settings — exactly
        // what production wiring would hand the real engine.
        let (model, _, spy) = Self.makeModel()
        let rate = 48_000.0
        let player = SoundPlayer(settings: SoundSettings(), quietHours: NeverQuiet())
        let standard = player.buffer(for: .ask)
        model.setChoiceForNeedsAnswer(.meow)
        player.settings = try! #require(spy.lastSettings)
        // `buffer(for:)` re-renders because `discardCacheIfInputsChanged` sees
        // the moved key — this asserts the *outcome*, not the cache internals.
        let afterChoice = player.buffer(for: .ask)
        #expect(standard != afterChoice, "the cache served a stale rendering after the choice changed")
        #expect(afterChoice == CueRenderer.render(.meow, settings: player.settings, sampleRate: rate))
    }

    // MARK: - The store → engine seam, enumerated rather than named

    @Test func aSoundFieldAddedWithoutMappingFailsWithoutAnyoneRememberingToTestIt() {
        // **The fifth instance of "persisted but never read" in this project was
        // found on this exact seam.** `SoundSettings(_ preferences:)` silently
        // dropped `pack` and all three `CueChoice` fields until Task 6 noticed;
        // `volume` and `quietDuringDoNotDisturb` had already been dropped by the
        // same initialiser once before that. Plan 6.5 Task 1 put a `Mirror` guard
        // on the *store* seam (`aFieldAddedWithoutPersistenceFailsWithout
        // AnyoneRememberingToTestIt`, `PreferenceStoreTests.swift`) — this is
        // Task 7 closing the other half, the store→engine one, which had none.
        //
        // Every field of `written` differs from `Preferences()`'s default, so
        // every field of the mapped `SoundSettings` must differ from
        // `SoundSettings()`'s. Nothing is named: a field added to both types and
        // forgotten in the mapping comes back as its default and fails here,
        // saying which. A field added to `Preferences` alone trips the `count`
        // assertion instead, which is the prompt to decide whether the engine
        // needs it.
        let written = Preferences(
            soundEnabled: false, volume: 0.23, quietDuringDoNotDisturb: false,
            selectedPage: "integrations",
            alerts: AlertPolicy(onNeedsAnswer: false, onFinish: false, onFail: false, onStall: true),
            pack: .silent,
            choiceForNeedsAnswer: .meow, choiceForFinish: .meow, choiceForFail: .meow,
            postsSystemNotification: true)
        let mapped = SoundSettings(written)

        let defaults = Dictionary(uniqueKeysWithValues:
            Mirror(reflecting: SoundSettings()).children.map {
                ($0.label ?? "?", String(describing: $0.value))
            })
        let mappedChildren = Mirror(reflecting: mapped).children.map {
            ($0.label ?? "?", String(describing: $0.value))
        }

        #expect(mappedChildren.count == 7,
                "SoundSettings grew or shrank — check `SoundSettings(_ preferences:)` maps the new field")
        for (label, value) in mappedChildren {
            #expect(value != defaults[label],
                    "`\(label)` is at its default after mapping a non-default Preferences, so `SoundSettings(_ preferences:)` is not reading it")
        }
        // The other direction, which the enumeration above cannot see: every
        // field of `SoundSettings` must have a `Preferences` field behind it. A
        // mapping that hardcoded a non-default constant would pass the loop.
        #expect(mapped == SoundSettings(enabled: false, volume: 0.23,
                                        quietDuringDoNotDisturb: false, pack: .silent,
                                        choiceForNeedsAnswer: .meow, choiceForFinish: .meow,
                                        choiceForFail: .meow))
    }

    // MARK: - Play bypasses AlertPolicy and reaches the row's own cue

    @Test @MainActor func eachPlayButtonReachesItsOwnRowsCue() {
        // The copy-paste risk this task's plan names explicitly: a row's
        // `Play` wired to another row's cue. `lastPlayedCueForTesting` is the
        // only way to see which `Cue` actually reached the engine, the same
        // limit `SettingsButton.actionForTesting()` already documents for a
        // `Button` tap.
        let (model, _, spy) = Self.makeModel()
        model.playNeedsAnswer()
        #expect(model.lastPlayedCueForTesting == .ask)
        model.playFinish()
        #expect(model.lastPlayedCueForTesting == .done)
        model.playFail()
        #expect(model.lastPlayedCueForTesting == .error)
        #expect(spy.playedCues == [.ask, .done, .error])
    }

    // **Not a test, recorded as a limit instead.** The natural next assertion —
    // "Play ignores `AlertPolicy`" — cannot be written as anything but a test
    // that always passes: `SoundSectionModel` has no `AlertPolicy` field for a
    // silenced switch to reach through, so there is no wrong behaviour to
    // provoke and no failing input that would prove the guarantee rather than
    // restate it. Per this repo's own rule ("a test that cannot fail is not a
    // test"), that guarantee is left as the doc comment on `play(_:)` and this
    // note, not as a green `#expect(true)`.

    // MARK: - Labels show the current value, not a fixed one

    @Test @MainActor func eachRowsLabelFunctionNamesItsOwnDefaultDifferently() {
        // The six-near-identical-rows defect class, caught at the label
        // layer: if "Finished"'s label closure were copy-pasted from
        // "Failed"'s without editing the default's name, this would still
        // compile and still pass every writer test above, and only this
        // assertion would catch it.
        #expect(SoundSection.needsAnswerLabel(.standard) == "Rising call (default)")
        #expect(SoundSection.finishLabel(.standard) == "Arpeggio (default)")
        #expect(SoundSection.failLabel(.standard) == "Falling thirds (default)")
        #expect(SoundSection.packLabel(.chiptune) == "Chiptune (default)")
        // And the shared cases really are shared, not one row's private copy.
        #expect(SoundSection.needsAnswerLabel(.meow) == "Meow")
        #expect(SoundSection.finishLabel(.meow) == "Meow")
        #expect(SoundSection.failLabel(.meow) == "Meow")
        #expect(SoundSection.needsAnswerLabel(.none) == "None")
        #expect(SoundSection.finishLabel(.none) == "None")
        #expect(SoundSection.failLabel(.none) == "None")
    }

    // MARK: - The slider's measured cost, before and after the fix
    //
    //     VIBECAT_SOUND_COST=1 swift test --filter volumeDragCost
    //
    // `getrusage(RUSAGE_SELF)`, never `ps %cpu` — the same rule and the same
    // reason `SoundCostProbe.swift` already states: a decaying average
    // produced a false failure in this repo once. Env-gated and printed
    // rather than asserted on, because a CPU figure is a property of the
    // machine that ran it. This is the one place in this file a real
    // `SoundPlayer` is deliberately re-introduced — the whole point is to
    // measure its real render cost — and it is a no-op without the env var,
    // so it carries none of this file's own full-suite cost the rest of it
    // was rewritten to avoid.

    private static func userCPUSeconds() -> Double {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return .nan }
        return Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
    }

    @Test @MainActor func volumeDragCost() {
        guard ProcessInfo.processInfo.environment["VIBECAT_SOUND_COST"] != nil else { return }
        // The hazard only shows up once *something downstream* consults the
        // player after a commit moves the cache key — `commitVolume()` alone
        // just writes a struct field. A live drag naturally wants the engine
        // ready to play whatever cue comes next, so the naive shape this
        // measures is "commit, then keep every cue warm" once per frame,
        // which is `prewarm()`'s own job in `main.swift` at launch repeated
        // every frame over one drag gesture. Five frames, not sixty: this
        // loop is genuinely hundreds of milliseconds each once `error`'s
        // 94-harmonic sawtooth is in it, and the point is the *shape* (linear
        // in frame count), not surviving a full drag's worth of it.
        let naiveFrames = 5
        let fixedFrames = 60   // a full ~1s drag at 60fps costs nothing to simulate when nothing renders

        func realPlayer() -> SoundPlayer { SoundPlayer(settings: SoundSettings(), quietHours: NeverQuiet()) }

        // "naive": what this task's hazard warns against — committing (and so
        // moving the cache key) and then re-warming every cue, on every drag
        // frame, instead of only on release.
        let naivePlayer = realPlayer()
        let (naiveModel, _, naiveSpy) = Self.makeModel()
        for cue in Cue.allCases { _ = naivePlayer.buffer(for: cue) }   // warm, like launch's prewarm()
        var mark = Self.userCPUSeconds()
        for i in 0..<naiveFrames {
            naiveModel.volume = Double(i) / Double(naiveFrames)
            naiveModel.commitVolume()
            if let settings = naiveSpy.lastSettings { naivePlayer.settings = settings }
            for cue in Cue.allCases { _ = naivePlayer.buffer(for: cue) }
        }
        let naive = (Self.userCPUSeconds() - mark) * 1000

        // "fixed": this task's shipped behaviour — the live value moves every
        // frame with no side effect, and only the release commits (and, with
        // it, pays one re-render of whatever the new inputs invalidated).
        let fixedPlayer = realPlayer()
        let (fixedModel, _, fixedSpy) = Self.makeModel()
        for cue in Cue.allCases { _ = fixedPlayer.buffer(for: cue) }
        mark = Self.userCPUSeconds()
        for i in 0..<fixedFrames {
            fixedModel.volume = Double(i) / Double(fixedFrames)
        }
        fixedModel.volumeEditingChanged(false)
        if let settings = fixedSpy.lastSettings { fixedPlayer.settings = settings }
        for cue in Cue.allCases { _ = fixedPlayer.buffer(for: cue) }   // the one re-render this pays
        let fixed = (Self.userCPUSeconds() - mark) * 1000

        print(String(format: "VOLUMEDRAG naive (%d frames, re-warm every frame): %.2fms total, %.2fms/frame | "
                     + "fixed (%d frames, commit+re-warm once on release): %.2fms total",
                     naiveFrames, naive, naive / Double(naiveFrames), fixedFrames, fixed))
    }
}
