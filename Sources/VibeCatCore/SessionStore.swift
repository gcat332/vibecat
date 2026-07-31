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
