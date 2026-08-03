import Testing
import Foundation
import VibeCatCore
@testable import VibeCatUI

// MARK: - AppModel → cue

// `VibeEvent.init` has no default for `id:`, and its label order is
// `v:id:cli:kind:session:cwd:`. Copied from the pattern at
// `Tests/VibeCatUITests/AppModelTests.swift:10` rather than invented.
private func event(_ kind: Kind, session: String) -> VibeEvent {
    VibeEvent(id: "e-\(session)", cli: "claude-code", kind: kind,
              session: session, cwd: "/tmp/\(session)")
}

/// The returned reader is `@MainActor` explicitly: it reads `Recorder`, which is
/// main-actor state, and a bare `() -> [Cue]` would drop that isolation on the
/// way out of this function.
@MainActor
private func modelWithRecorder() -> (AppModel, @MainActor () -> [Cue]) {
    let model = AppModel(socketPath: "/tmp/vibecat-cue-\(UUID().uuidString).sock")
    let box = Recorder()
    model.onCue = { box.cues.append($0) }
    return (model, { box.cues })
}

@MainActor private final class Recorder { var cues: [Cue] = [] }

@Test @MainActor func ingestingAQuestionFiresTheAskCue() {
    let (model, cues) = modelWithRecorder()
    model.ingest(event(.running, session: "a"))
    model.ingest(event(.permission, session: "a"))
    #expect(cues() == [.ask])
}

@Test @MainActor func aFinishFiresDoneEvenThoughTheStoreForgetsIt() {
    let (model, cues) = modelWithRecorder()
    model.ingest(event(.running, session: "a"))
    model.ingest(event(.done, session: "a"))
    #expect(cues() == [.done])
}

@Test @MainActor func aQuietChangeFiresNothingAtAll() {
    // Not "fires a quiet cue" — fires nothing. An `onCue?(nil)` would make
    // every consumer branch on a case that means "ignore me".
    let (model, cues) = modelWithRecorder()
    model.ingest(event(.running, session: "a"))
    #expect(cues().isEmpty)
}

@Test @MainActor func theCueIsComputedFromTheStoreAsItWasBeforeTheEventLanded() {
    // The whole rule depends on a before/after pair. If the hook were placed
    // after the store had already been mutated, `before` and `after` would be
    // identical and only `.done` would ever fire.
    let (model, cues) = modelWithRecorder()
    model.ingest(event(.permission, session: "a"))
    model.ingest(event(.question, session: "b"))
    #expect(cues() == [.ask, .askMulti])
}

@Test @MainActor func aPruneNeverCues() {
    // Sessions ageing out is not an event and must not sound like one.
    let (model, cues) = modelWithRecorder()
    model.ingest(event(.permission, session: "a"),
                 now: Date(timeIntervalSince1970: 1_800_000_000))
    model.prune(now: Date(timeIntervalSince1970: 1_800_000_000 + 3 * 3600))
    #expect(cues() == [.ask], "the prune must not have added anything")
}

/// The test above prunes a *waiting* session, which `SessionStore.prune` keeps —
/// so it stays green even against a `prune` that cues from inside its own
/// `store != before` guard. This one makes the prune actually remove a session,
/// which is the only shape of the defect the guard admits.
@Test @MainActor func aPruneThatRemovesASessionStillCuesNothing() {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let (model, cues) = modelWithRecorder()
    model.ingest(event(.done, session: "a"), now: t0)
    let removed = model.sessionCount
    model.prune(now: t0.addingTimeInterval(AppModel.idleTTL + 60))
    #expect(removed == 1 && model.sessionCount == 0, "the prune must have removed something")
    #expect(cues() == [.done], "and still added nothing of its own")
}

// MARK: - the quiet-hours gate

@Test @MainActor func aQuietMachinePlaysNothing() {
    struct AlwaysQuiet: QuietHours { var isQuiet: Bool { true } }
    let player = SoundPlayer(settings: SoundSettings(), quietHours: AlwaysQuiet())
    #expect(player.buffer(for: .ask)?.isEmpty ?? true, "nothing should be rendered while quiet")
}

@Test @MainActor func theQuietGateIsIgnoredWhenTheUserTurnedItOff() {
    struct AlwaysQuiet: QuietHours { var isQuiet: Bool { true } }
    var settings = SoundSettings()
    settings.quietDuringDoNotDisturb = false
    let player = SoundPlayer(settings: settings, quietHours: AlwaysQuiet())
    let buffer = player.buffer(for: .ask)
    #expect(!(buffer?.isEmpty ?? true), "the switch is off, so DND must not suppress")
}

@Test @MainActor func aLoudMachinePlaysTheCue() {
    let player = SoundPlayer(settings: SoundSettings(), quietHours: NeverQuiet())
    #expect(!(player.buffer(for: .ask)?.isEmpty ?? true))
}
