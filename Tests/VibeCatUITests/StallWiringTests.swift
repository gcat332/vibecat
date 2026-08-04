import Testing
import Foundation
import VibeCatCore
@testable import VibeCatUI

// `StallDetectorTests.swift` (VibeCatCoreTests) proves the pure rule: which
// sessions are stalled, given a store and a clock. This file proves the part
// that lives in `AppModel` instead — riding `prune`'s existing 60s tick,
// gating on `AlertPolicy.allows(.stalled)`, and re-arming `stalledReported`
// the moment any event lands for a session (written decision 3).

private let t0 = Date(timeIntervalSince1970: 1_000_000)

private func event(_ kind: Kind, session: String) -> VibeEvent {
    VibeEvent(id: "e-\(session)", cli: "claude-code", kind: kind,
              session: session, cwd: "/dev/\(session)")
}

/// A reference type for the same reason `AppModelTests.ChangeCounter` is one:
/// a captured `var` mutated from inside an escaping closure and read from
/// outside it trips Swift 6's "mutated after capture" diagnostic.
@MainActor private final class StallRecorder {
    var keys: [SessionKey] = []
    func record(_ key: SessionKey) { keys.append(key) }
}

@MainActor @Test func aStalledRunningSessionFiresOnStallOncePolicyAllowsIt() {
    let store = InMemoryPreferenceStore(Preferences(alerts: AlertPolicy(onStall: true)))
    let m = AppModel(socketPath: "/tmp/vibecat-stall-unused.sock", preferences: store)
    let recorder = StallRecorder()
    m.onStall = { recorder.record($0) }

    _ = m.ingest(event(.running, session: "a"), now: t0)
    m.prune(now: t0.addingTimeInterval(299))
    #expect(recorder.keys.isEmpty, "must not fire before StallDetector's own threshold")

    m.prune(now: t0.addingTimeInterval(300))
    #expect(recorder.keys == [SessionKey(cli: "claude-code", session: "a")])
}

@Test @MainActor func theStallSwitchOffByDefaultMeansNoAlertEvenWhenQuiet() {
    // `AlertPolicy()`'s own default: `onStall` is off (settings.html:334's
    // `aria-checked="false"`) until someone turns it on. `AppModel` must not
    // fire `onStall` at all while the policy says not to — this is the gate
    // written decision 4 assigns to `AppModel`/`CueSelector`, not to
    // `StallDetector`, which knows nothing about `AlertPolicy`.
    let store = InMemoryPreferenceStore()
    let m = AppModel(socketPath: "/tmp/vibecat-stall-unused.sock", preferences: store)
    let recorder = StallRecorder()
    m.onStall = { recorder.record($0) }

    _ = m.ingest(event(.running, session: "a"), now: t0)
    m.prune(now: t0.addingTimeInterval(600))
    #expect(recorder.keys.isEmpty)
}

@MainActor @Test func aStallFiresOnceAndNotOnEveryFollowingTick() {
    let store = InMemoryPreferenceStore(Preferences(alerts: AlertPolicy(onStall: true)))
    let m = AppModel(socketPath: "/tmp/vibecat-stall-unused.sock", preferences: store)
    let recorder = StallRecorder()
    m.onStall = { recorder.record($0) }

    _ = m.ingest(event(.running, session: "a"), now: t0)
    m.prune(now: t0.addingTimeInterval(300))
    m.prune(now: t0.addingTimeInterval(360))
    m.prune(now: t0.addingTimeInterval(1_000))
    #expect(recorder.keys.count == 1, "written decision 3: one alert per quiet period, not every tick")
}

@MainActor @Test func anyEventForTheSessionReArmsItsStallEntry() {
    let store = InMemoryPreferenceStore(Preferences(alerts: AlertPolicy(onStall: true)))
    let m = AppModel(socketPath: "/tmp/vibecat-stall-unused.sock", preferences: store)
    let recorder = StallRecorder()
    m.onStall = { recorder.record($0) }

    _ = m.ingest(event(.running, session: "a"), now: t0)
    m.prune(now: t0.addingTimeInterval(300))
    #expect(recorder.keys.count == 1)

    // The session does something — this must clear its reported entry rather
    // than leaving it permanently silenced.
    _ = m.ingest(event(.running, session: "a"), now: t0.addingTimeInterval(310))
    m.prune(now: t0.addingTimeInterval(310))
    #expect(recorder.keys.count == 1, "must not refire just because an event landed — it isn't quiet yet")

    m.prune(now: t0.addingTimeInterval(310 + 300))
    #expect(recorder.keys.count == 2, "a second quiet period must alert again, per written decision 3")
}

// No test here for the `stalledReported.formIntersection(...)` cleanup in
// `prune` — tried one, and it could not fail. `applyAndNotify`'s own
// `stalledReported.remove(key)` already clears an entry the instant any event
// reuses that session's key, so nothing reachable through `AppModel`'s public
// surface can tell the intersection apart from its absence. See the comment
// on that line in `AppModel.swift` for the mutation that stayed green.
