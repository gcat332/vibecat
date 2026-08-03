import Foundation
import Testing
@testable import VibeCatCore

private let t0 = Date(timeIntervalSince1970: 1_000_000)

private func event(_ kind: Kind, session: String, cli: String = "claude-code") -> VibeEvent {
    VibeEvent(id: "e-\(session)", cli: cli, kind: kind, session: session, cwd: "/dev/\(session)")
}

@Test func applyInsertsThenUpdatesInPlace() throws {
    var store = SessionStore()
    store.apply(event(.running, session: "a"), now: t0)
    store.apply(event(.permission, session: "a"), now: t0.addingTimeInterval(5))
    #expect(store.sessions.count == 1)
    let session = try #require(store.sessions.first)
    #expect(session.state == .waiting)
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

/// Deliberately out of urgency order, and with two sessions tied at the most
/// urgent state (`.waiting`), so a single assertion distinguishes a correct
/// comparator from two different broken ones at once.
@Test func mostUrgentSessionPicksTheMostUrgentNotTheFirstOrLast() {
    var store = SessionStore()
    store.apply(event(.running, session: "b-running"), now: t0)           // urgency 2
    store.apply(event(.permission, session: "a-waiting-first"), now: t0)  // urgency 0 — first waiting
    store.apply(event(.done, session: "c-idle"), now: t0)                 // urgency 3 — least urgent
    store.apply(event(.permission, session: "d-waiting-second"), now: t0) // urgency 0 — ties "a-waiting-first"

    // Correct: `.waiting` (urgency 0) is the most urgent state present, and
    // of the two sessions tied there, `min(by:)` keeps whichever it visits
    // first — "a-waiting-first", inserted before "d-waiting-second".
    //
    // A comparator reversed (`>` in place of `<`) would instead report
    // "c-idle" — urgency 3, the *least* urgent session in the store, the
    // opposite of what this property promises.
    //
    // A tie-break that preferred the last match instead of the first (or an
    // unstable sort standing in for `min(by:)`) would report
    // "d-waiting-second" instead of "a-waiting-first".
    #expect(store.mostUrgentSession?.id.session == "a-waiting-first")
}

/// `render()` calls this on every event, and a dormant island (no sessions at
/// all) is the common case — the one `IslandModel.revealed` most needs to
/// come back `nil` for rather than trap on an empty `sessions` array.
@Test func mostUrgentSessionOfAnEmptyStoreIsNil() {
    #expect(SessionStore().mostUrgentSession == nil)
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

/// §11: "Sort order defaults to most urgent first" — the same
/// `waiting > failed > running > idle` §4.2 gives the island, so the list and
/// the island agree about which session matters.
///
/// The fixture is deliberately in the *opposite* order and includes two
/// sessions of one state, because a sort that merely reverses, or one that is
/// unstable within a state, both satisfy a weaker assertion.
@Test func theListPutsTheMostUrgentSessionFirst() {
    var store = SessionStore()
    let now = Date(timeIntervalSince1970: 1_000_000)
    for (session, kind) in [("a", Kind.idle), ("b", .running),
                            ("c", .running), ("d", .failed), ("e", .permission)] {
        store.apply(VibeEvent(id: session, cli: "claude-code", kind: kind,
                              session: session, cwd: "/tmp/\(session)"), now: now)
    }
    let order = store.mostUrgentFirst.map(\.id.session)
    #expect(order == ["e", "d", "b", "c", "a"],
            "got \(order) — expected waiting, failed, then the two running in the order they arrived, then idle")
}
