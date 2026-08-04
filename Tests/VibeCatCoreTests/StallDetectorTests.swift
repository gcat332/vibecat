import Testing
import Foundation
@testable import VibeCatCore

// `VibeEvent.init` has no default for `id:`, and its label order is
// `v:id:cli:kind:session:cwd:`. Copied from `CueSelectorTests.swift`'s own
// helper rather than invented, with an `at:` added so a test can put a
// session's `updatedAt` at a known instant instead of "whenever the test
// runs".
private func session(_ id: String, _ kind: Kind) -> VibeEvent {
    VibeEvent(id: "e-\(id)", cli: "claude-code", kind: kind, session: id, cwd: "/tmp/\(id)")
}

private func store(_ events: [VibeEvent], at t: Date) -> SessionStore {
    var s = SessionStore()
    for e in events { s.apply(e, now: t) }
    return s
}

@Test func aSessionQuietForFiveMinutesStalls() {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let s = store([session("a", .running)], at: t0)
    #expect(StallDetector.stalled(in: s, now: t0.addingTimeInterval(299), alreadyReported: []).isEmpty)
    #expect(StallDetector.stalled(in: s, now: t0.addingTimeInterval(300), alreadyReported: [])
            == [SessionKey(cli: "claude-code", session: "a")])
}

@Test func aSessionWaitingOnAQuestionIsBlockedRatherThanStalled() {
    // The prototype's own sub-label: "and no question is pending". The island is
    // already amber for this session; a stall alert would be a second, duller
    // way of saying the same thing.
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let s = store([session("a", .permission)], at: t0)
    #expect(StallDetector.stalled(in: s, now: t0.addingTimeInterval(3600), alreadyReported: []).isEmpty)
}

@Test func aStallIsReportedOnceAndNotEveryTick() {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let s = store([session("a", .running)], at: t0)
    let key = SessionKey(cli: "claude-code", session: "a")
    #expect(StallDetector.stalled(in: s, now: t0.addingTimeInterval(600), alreadyReported: [key]).isEmpty)
}

@Test func aFailedSessionDoesNotAlsoStall() {
    // A failed run has already stopped, and §4.2 says so explicitly. Alerting
    // twice for one event is the defect.
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let s = store([session("a", .failed)], at: t0)
    #expect(StallDetector.stalled(in: s, now: t0.addingTimeInterval(3600), alreadyReported: []).isEmpty)
}

@Test func theThresholdIsTheProtoypesFiveMinutes() {
    #expect(StallDetector.threshold == 300)
}
