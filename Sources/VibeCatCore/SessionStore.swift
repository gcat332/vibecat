import Foundation

/// A value type on purpose: the app can hold one in an `@Observable` box and the
/// tests can drive it with no concurrency at all.
public struct SessionStore: Sendable, Equatable {
    public private(set) var sessions: [Session] = []

    public init() {}

    public mutating func apply(_ event: VibeEvent, now: Date) {
        let key = SessionKey(cli: event.cli, session: event.session)
        if let i = sessions.firstIndex(where: { $0.id == key }) {
            sessions[i].merge(event, now: now)
        } else {
            sessions.append(Session(event: event, now: now))
        }
    }

    /// The island reports the most urgent session, not the most common one.
    public var aggregate: SessionState {
        SessionState.mostUrgent(sessions.map(\.state)) ?? .idle
    }

    /// The single session `IslandModel.revealed` names, so the hover reveal
    /// points at the same session `aggregate` already summarises the state
    /// of — one notion of "most urgent", not two. `min(by:)` over
    /// `SessionState.urgency` (lower is more urgent) rather than reusing
    /// `aggregate` plus a lookup, since that would only find *a* session in
    /// that state, not necessarily the single most urgent one when several
    /// tie. Ties resolve to whichever comes first in `sessions` — a full,
    /// deterministic ordering across ties belongs to whatever renders the
    /// scrolling session list, not to this.
    public var mostUrgentSession: Session? {
        sessions.min { $0.state.urgency < $1.state.urgency }
    }

    public var counts: [SessionState: Int] {
        Dictionary(grouping: sessions, by: \.state).mapValues(\.count)
    }

    /// Only sessions that are finished *and* stale go away. Anything still
    /// running, or still waiting on you, stays however old it is.
    public mutating func prune(idleFor: TimeInterval, now: Date) {
        sessions.removeAll { session in
            session.state == .idle && now.timeIntervalSince(session.updatedAt) > idleFor
        }
    }
}
