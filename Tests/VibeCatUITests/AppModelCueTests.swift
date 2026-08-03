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

// MARK: - The player's own machinery
//
// Everything below exists because of the whole-branch review's Important 2, 3 and
// 4. None of it can be observed through sound on this machine, so each test names
// the state it looks at and why that state is the consequence being pinned.

@Test @MainActor func aCueIsRenderedOnceAndThenReadFromTheCache() {
    // The cache is the fix for a measured 858ms of main-actor time per `error`
    // render. What has to be true for it to be a fix rather than a bug is that the
    // second read is the *same* samples and the cache is actually populated — a
    // `buffer(for:)` that rendered afresh every time would pass any assertion about
    // the samples alone, because rendering is deterministic.
    let player = SoundPlayer(settings: SoundSettings(), quietHours: NeverQuiet())
    #expect(player.rendered.isEmpty, "nothing should be rendered before it is asked for")
    let first = player.buffer(for: .ask)
    #expect(player.rendered[.ask] != nil, "the render was not kept")
    #expect(player.rendered.count == 1, "only the cue that was asked for should be rendered")
    #expect(player.buffer(for: .ask) == first)
}

@Test @MainActor func changingASettingThrowsTheRenderedCuesAway() {
    // Two renders differing in exactly one input, at the cache's boundary. Without
    // the key comparison a volume change would keep playing the old level for the
    // rest of the session, which is worse than the cost the cache was added to
    // avoid — it is the wrong sound, silently.
    let player = SoundPlayer(settings: SoundSettings(volume: 0.6), quietHours: NeverQuiet())
    let atSixty = player.buffer(for: .ask)!
    player.settings.volume = 0.3
    // The invalidation is lazy on purpose — it happens on the next use, where the
    // sample rate is read too, so there is one place that decides whether the cache
    // is still valid rather than a `didSet` on every input.
    let atThirty = player.buffer(for: .ask)!
    // Derived rather than asserted as "different": half the volume is half of every
    // sample, so the loudest sample must have halved.
    let i = atSixty.indices.max(by: { abs(atSixty[$0]) < abs(atSixty[$1]) })!
    #expect(abs(Double(atSixty[i]) / 2 - Double(atThirty[i])) < 1e-6,
            "at the loudest sample: \(atSixty[i]) then \(atThirty[i])")
}

@Test @MainActor func prewarmRendersEveryCueWithoutBlockingTheCaller() async throws {
    // `prewarm()` is what keeps the first `failed` event of a session from being the
    // one that waits 858ms. It must return before the work is done — that is the
    // whole point — so the assertion is that the cache fills *afterwards*, on the
    // render queue, and that the hop back to the main actor lands.
    let player = SoundPlayer(settings: SoundSettings(), quietHours: NeverQuiet())
    player.prewarm()
    #expect(player.rendered.count < Cue.allCases.count,
            "prewarm rendered synchronously; the main actor paid for all five")
    // Bounded, and generous: five debug renders total about a second of CPU on the
    // machine this was written on, and the suite runs in parallel. A fixed sleep
    // would be a flake under load.
    for _ in 0..<300 where player.rendered.count < Cue.allCases.count {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(player.rendered.count == Cue.allCases.count,
            "only \(player.rendered.count) of \(Cue.allCases.count) cues reached the cache")
}

@Test @MainActor func aConfigurationChangeDropsTheGraphAndEveryRenderedCue() async throws {
    // The review's Important 4, which it could not reproduce and neither could this:
    // a device being *replaced* mid-session. `AVAudioEngine` documents that a
    // configuration change stops the engine and invalidates the graph's connections,
    // and the old code never observed the notification at all — so `wired` stayed
    // true, the node was never re-connected, and every later cue was either silently
    // dropped or handed to a mismatched format.
    //
    // Posting the real notification for this engine is deliberate: a test that called
    // the handler directly would still pass with the observer deleted, which is
    // exactly the defect.
    let player = SoundPlayer(settings: SoundSettings(), quietHours: NeverQuiet())
    _ = player.buffer(for: .ask)
    player.connected = true
    #expect(player.rendered.count == 1)

    NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange,
                                    object: player.engine)
    // The observer is registered on `OperationQueue.main`, so it runs when the main
    // actor next yields rather than inside `post`. Bounded poll, not a fixed sleep.
    for _ in 0..<100 where player.connected {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(player.connected == false,
            "nothing observed AVAudioEngineConfigurationChange, so the graph was never re-made")
    // `count == 0` rather than `isEmpty`: a failing `#expect` prints the value, and
    // the value here is 29,000 floats.
    #expect(player.rendered.count == 0,
            "a replacement device may run at another rate; the old buffers are wrong, not stale")
}

// MARK: - The backlog bound

@Test func anEmptyQueueAdmitsACueImmediately() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let window = SoundPlayer.admission(now: now, queueEndsAt: .distantPast, duration: 0.93)
    #expect(window?.startsAt == now, "a cue with nothing ahead of it must start now")
    #expect(window?.endsAt == now.addingTimeInterval(0.93))
}

@Test func oneCueAlreadyPlayingStillAdmitsTheNext() {
    // At most one may wait. `error` is the longest cue at 0.93s, and the bound is
    // 1.0s, so a second `error` arriving the instant the first started is admitted —
    // it begins 0.93s late, which is the cost of serial playback and is accepted.
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let window = SoundPlayer.admission(now: now, queueEndsAt: now.addingTimeInterval(0.93),
                                       duration: 0.93)
    #expect(window?.startsAt == now.addingTimeInterval(0.93))
    // Compared as an interval, not an instant, and with a slop derived rather than
    // widened until it passed: a `Date` is a `Double` of seconds since 2001, so at
    // 2027 the representable resolution is about 2e-7 seconds. Two additions of 0.93
    // cannot land closer than that.
    #expect(abs(window!.endsAt.timeIntervalSince(now) - 1.86) < 1e-6,
            "got \(window!.endsAt.timeIntervalSince(now))")
}

@Test func aThirdCueInABurstIsDroppedRatherThanQueued() {
    // The defect this bounds: N events put the Nth alert 0.6…0.9s × (N−1) after the
    // thing it announces, with nothing capping N. An alert two seconds late is not
    // information, and the state it would have announced is on the island already.
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let queued = now.addingTimeInterval(SoundPlayer.maximumBacklog)
    #expect(SoundPlayer.admission(now: now, queueEndsAt: queued, duration: 0.93) == nil,
            "a cue a full backlog behind must be dropped")
}

@Test func theBoundHealsItselfAsTimePasses() {
    // Why the bound is wall-clock and not a count of outstanding buffers: a counter
    // decremented by a completion handler that never fires would silence the app for
    // the rest of the session. Time needs nobody to reset it.
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let queued = start.addingTimeInterval(2)
    #expect(SoundPlayer.admission(now: start, queueEndsAt: queued, duration: 0.93) == nil)
    let later = start.addingTimeInterval(1.5)
    #expect(SoundPlayer.admission(now: later, queueEndsAt: queued, duration: 0.93) != nil,
            "once the queue is within the bound again, cues must resume")
}

// MARK: - The branch production actually takes

/// Every cue test above is `@MainActor` and calls `ingest` directly, so all of them
/// take `applyAndNotify`'s `Thread.isMainThread` branch. **Production never takes
/// that branch**: `SocketServer` hands each event to a fresh thread, so the three
/// duplicated lines in the `Task { @MainActor }` branch are the only ones that ever
/// run against a real agent — and nothing exercised them. The duplication is
/// justified (de-duplicating it is precisely the change `AppModel.swift:100-128`
/// records as having reproduced a full-suite-only flake), but its cost is that the
/// two copies can drift and nothing would go red.
///
/// **Why this is safe to write, having read that comment.** The hazard it documents
/// is `DispatchQueue.main.sync` called from a task on Swift's small shared
/// cooperative pool: enough of those threads blocked at once leaves none free to run
/// the `Task { @MainActor … }` hops that would unblock them. Nothing here blocks. The
/// detached task calls `ingest` for an event with `wantsReply == false`, which
/// returns without touching `PendingQuestion.await()`; `applyAndNotify` then only
/// *enqueues* a main-actor task. The test's own `await` releases the main actor,
/// which is what lets that enqueued task run at all — and the wait is a bounded poll,
/// so it cannot hang the suite even if the cue never arrives.
@Test @MainActor func aCueFiresWhenTheEventArrivesOffTheMainThread() async throws {
    let (model, cues) = modelWithRecorder()
    // Both events go through the non-main branch, in order, so the before/after pair
    // `CueSelector` needs is formed there too rather than half on each branch.
    await Task.detached { _ = model.ingest(event(.running, session: "a")) }.value
    await Task.detached { _ = model.ingest(event(.permission, session: "a")) }.value
    for _ in 0..<200 where cues().isEmpty {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(cues() == [.ask],
            "the fire-and-forget branch either never cued or cued the wrong thing")
    #expect(model.sessionCount == 1, "and the store must have been applied on it too")
}

/// The mirror of `aQuietChangeFiresNothingAtAll`, on the other branch. Without it a
/// non-main copy that fired unconditionally — dropping the `if let cue` — would still
/// pass the test above.
@Test @MainActor func aQuietChangeOffTheMainThreadFiresNothingEither() async throws {
    let (model, cues) = modelWithRecorder()
    await Task.detached { _ = model.ingest(event(.running, session: "a")) }.value
    // Nothing to poll *for*, so this waits for the enqueued main-actor task to have
    // run at all — the store landing is the observable proof that it did.
    for _ in 0..<200 where model.sessionCount == 0 {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(model.sessionCount == 1, "the event never landed, so this proves nothing yet")
    #expect(cues().isEmpty, "a run starting is not news")
}
