import Foundation
import Testing
@testable import VibeCatCore

private let t0 = Date(timeIntervalSince1970: 1_000_000)

private func event(_ kind: Kind, session: String, cli: String = "claude-code") -> VibeEvent {
    VibeEvent(id: "e-\(session)", cli: cli, kind: kind, session: session, cwd: "/dev/\(session)")
}

@Test func applyInsertsThenUpdatesInPlace() {
    var store = SessionStore()
    store.apply(event(.running, session: "a"), now: t0)
    store.apply(event(.permission, session: "a"), now: t0.addingTimeInterval(5))
    #expect(store.sessions.count == 1)
    #expect(store.sessions[0].state == .waiting)
}

@Test func sameSessionIdOnDifferentCliIsADifferentSession() {
    var store = SessionStore()
    store.apply(event(.running, session: "a", cli: "claude-code"), now: t0)
    store.apply(event(.running, session: "a", cli: "codex"), now: t0)
    #expect(store.sessions.count == 2)
}

@Test func aggregateTakesTheMostUrgentSession() {
    var store = SessionStore()
    store.apply(event(.running, session: "a"), now: t0)
    store.apply(event(.failed, session: "b"), now: t0)
    store.apply(event(.permission, session: "c"), now: t0)
    #expect(store.aggregate == .waiting)
}

@Test func aggregateOfAnEmptyStoreIsIdle() {
    #expect(SessionStore().aggregate == .idle)
}

@Test func countsGroupByState() {
    var store = SessionStore()
    store.apply(event(.permission, session: "a"), now: t0)
    store.apply(event(.running, session: "b"), now: t0)
    store.apply(event(.running, session: "c"), now: t0)
    #expect(store.counts[.waiting] == 1)
    #expect(store.counts[.running] == 2)
    #expect(store.counts[.failed] == nil)
}

@Test func pruneDropsStaleIdleSessionsOnly() {
    var store = SessionStore()
    store.apply(event(.done, session: "old"), now: t0)
    store.apply(event(.permission, session: "waiting"), now: t0)
    store.apply(event(.running, session: "busy"), now: t0)

    store.prune(idleFor: 3600, now: t0.addingTimeInterval(7200))

    let ids = store.sessions.map(\.id.session).sorted()
    #expect(ids == ["busy", "waiting"])   // a stale session that still needs you is kept
}

@Test func pruneKeepsRecentIdleSessions() {
    var store = SessionStore()
    store.apply(event(.done, session: "recent"), now: t0)
    store.prune(idleFor: 3600, now: t0.addingTimeInterval(60))
    #expect(store.sessions.count == 1)
}
