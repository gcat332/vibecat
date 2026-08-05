import Foundation

/// A value type on purpose: the app can hold one in an `@Observable` box and the
/// tests can drive it with no concurrency at all.
public struct SessionStore: Sendable, Equatable {
    public private(set) var sessions: [Session] = []

    public init() {}

    /// `icon` is §3's *"swappable runtime asset"* for the source this event came
    /// from, already resolved to a path by whoever holds a `SourceRegistry` —
    /// `AppModel.applyAndNotify` on the app side. It arrives as a parameter
    /// rather than being looked up here for two reasons: this type is a
    /// `Sendable`, `Equatable` value and a registry is neither, and the lookup
    /// is a *display* concern that must not be able to change what state the
    /// store reports.
    ///
    /// Defaulted, so the ~60 existing call sites that have no registry to ask
    /// keep compiling and keep getting `nil` — which is exactly the geometric
    /// fallback `SourceIcon` draws for a source with no icon.
    ///
    /// Assigned on **create** and, when non-`nil`, on **merge**. The merge case
    /// looks redundant — `cli` is half the `SessionKey`, so a session's source
    /// never changes and the resolved icon cannot change with it — and it is
    /// kept for the case that is not covered by that argument: a session
    /// created before its source's definition was loaded (a custom source
    /// added, then the first event of an already-open session arriving after)
    /// would otherwise keep a `nil` icon for its whole life. `if let`, not an
    /// unconditional assignment, follows `Session.merge`'s own rule that an
    /// event omitting something leaves it alone.
    public mutating func apply(_ event: VibeEvent, now: Date, icon: String? = nil) {
        let key = SessionKey(cli: event.cli, session: event.session)
        if let i = sessions.firstIndex(where: { $0.id == key }) {
            sessions[i].merge(event, now: now)
            if let icon { sessions[i].icon = icon }
        } else {
            var session = Session(event: event, now: now)
            session.icon = icon
            sessions.append(session)
        }
    }

    /// The island reports the most urgent session, not the most common one.
    public var aggregate: SessionState {
        SessionState.mostUrgent(sessions.map(\.state)) ?? .idle
    }

    /// The single session `IslandModel.revealed` names, so the hover reveal
    /// points at the same session `aggregate` already summarises the state
    /// of — one notion of "most urgent", not two.
    ///
    /// Expressed as `mostUrgentFirst.first` rather than a second `min(by:)`
    /// over the same comparator: two independent orderings of "most urgent"
    /// in one file is exactly the kind of drift that would let the island's
    /// hover reveal and the session list disagree about which session
    /// matters, so there is only one comparator and this just asks it for
    /// its head. `mostUrgentFirst`'s own stable tie-break — earliest arrival
    /// wins — is what makes this equivalent to the old direct
    /// `sessions.min { $0.state.urgency < $1.state.urgency }`: `min(by:)`
    /// with a strict `<` also keeps the first-encountered minimum on a tie,
    /// so neither behaviour nor the existing tests here changed.
    public var mostUrgentSession: Session? {
        mostUrgentFirst.first
    }

    /// §11: most urgent first, using §4.2's own ordering so the list and the
    /// island never disagree about which session matters. Two sessions of
    /// one state should keep the order they arrived in rather than shuffling
    /// on every render, so the index is carried in the comparator explicitly
    /// (`$0.offset < $1.offset` on a tie) rather than leaning on `sorted(by:)`
    /// itself to preserve order — that way this ordering's correctness
    /// doesn't depend on the sort's stability at all, whatever that turns
    /// out to be. Whether `sorted(by:)` is in fact guaranteed stable on this
    /// toolchain is an open question this comment does not settle either
    /// way: dropping this tie-break does not currently make
    /// `theListPutsTheMostUrgentSessionFirst` fail, because the sort behaves
    /// stably here in practice — so that half of the test cannot fail today,
    /// and the tie-break is kept for independence from that fact rather than
    /// because a mutation proved it necessary.
    public var mostUrgentFirst: [Session] {
        sessions.enumerated()
            .sorted {
                $0.element.state.urgency == $1.element.state.urgency
                    ? $0.offset < $1.offset
                    : $0.element.state.urgency < $1.element.state.urgency
            }
            .map(\.element)
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
