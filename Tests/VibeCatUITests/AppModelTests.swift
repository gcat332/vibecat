import Foundation
import Testing
import VibeCatCore
@testable import VibeCatUI

private let t0 = Date(timeIntervalSince1970: 1_000_000)

private func event(_ kind: Kind, session: String) -> VibeEvent {
    VibeEvent(id: "e-\(session)", cli: "claude-code", kind: kind,
              session: session, cwd: "/dev/\(session)")
}

/// Counts `onChange` firings. A reference type rather than a captured `var`,
/// matching HoverMonitorTests' `Fake` — a local `var` mutated from inside an
/// escaping closure and then read from outside it trips Swift 6's "mutated
/// after capture by sendable closure" diagnostic.
@MainActor private final class ChangeCounter {
    var count = 0
    func fire() { count += 1 }
}

@MainActor @Test func aFreshModelIsDormant() {
    let m = AppModel(socketPath: "/tmp/vibecat-test-unused.sock")
    #expect(m.islandState == .dormant)
    #expect(m.sessionCount == 0)
}

@MainActor @Test func ingestingAnEventUpdatesTheIslandState() {
    let m = AppModel(socketPath: "/tmp/vibecat-test-unused.sock")
    _ = m.ingest(event(.running, session: "a"), now: t0)
    #expect(m.islandState == .running)
    #expect(m.sessionCount == 1)

    _ = m.ingest(event(.permission, session: "b"), now: t0)
    #expect(m.islandState == .waiting)   // the worst state wins
    #expect(m.sessionCount == 2)
}

/// Plan 2 cannot answer anything yet, and nil is what makes the hook fall
/// through to the CLI's own prompt rather than hanging.
@MainActor @Test func everyEventIsAnsweredWithNoReplyForNow() {
    let m = AppModel(socketPath: "/tmp/vibecat-test-unused.sock")
    #expect(m.ingest(event(.permission, session: "a"), now: t0) == nil)
    #expect(m.ingest(event(.question, session: "b"), now: t0) == nil)
}

@MainActor @Test func pruningDropsStaleFinishedSessionsOnly() {
    let m = AppModel(socketPath: "/tmp/vibecat-test-unused.sock")
    _ = m.ingest(event(.done, session: "old"), now: t0)
    _ = m.ingest(event(.running, session: "busy"), now: t0)
    m.prune(now: t0.addingTimeInterval(AppModel.idleTTL + 1))
    #expect(m.sessionCount == 1)
    #expect(m.store.sessions.first?.id.session == "busy")
}

@MainActor @Test func theSameSessionUpdatesInPlace() {
    let m = AppModel(socketPath: "/tmp/vibecat-test-unused.sock")
    _ = m.ingest(event(.running, session: "a"), now: t0)
    _ = m.ingest(event(.failed, session: "a"), now: t0.addingTimeInterval(1))
    #expect(m.sessionCount == 1)
    #expect(m.islandState == .failed)
}

/// `NotchController` re-renders off this callback rather than a
/// `withObservationTracking` bridge specifically because that bridge's
/// one-shot `onChange` can drop a second, closely-following mutation while
/// the re-arm is still in flight. This pins the behaviour it replaces.
@MainActor @Test func onChangeFiresOnEveryIngestIncludingTheSecond() {
    let m = AppModel(socketPath: "/tmp/vibecat-test-unused.sock")
    let counter = ChangeCounter()
    m.onChange = { counter.fire() }

    _ = m.ingest(event(.running, session: "a"), now: t0)
    #expect(counter.count == 1)

    _ = m.ingest(event(.permission, session: "b"), now: t0)
    #expect(counter.count == 2)
}

@MainActor @Test func onChangeFiresOnPruneOnlyWhenSomethingWasActuallyRemoved() {
    let m = AppModel(socketPath: "/tmp/vibecat-test-unused.sock")
    _ = m.ingest(event(.done, session: "old"), now: t0)
    _ = m.ingest(event(.running, session: "busy"), now: t0)

    let counter = ChangeCounter()
    m.onChange = { counter.fire() }

    // Neither session is stale yet — a no-op prune must not fire.
    m.prune(now: t0)
    #expect(counter.count == 0)

    // "old" is idle and past the TTL now; "busy" survives regardless of age.
    m.prune(now: t0.addingTimeInterval(AppModel.idleTTL + 1))
    #expect(counter.count == 1)
    #expect(m.sessionCount == 1)

    // Nothing left to remove — no further fire.
    m.prune(now: t0.addingTimeInterval(AppModel.idleTTL + 2))
    #expect(counter.count == 1)
}
