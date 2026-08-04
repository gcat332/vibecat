import Foundation

/// Which sessions have gone quiet — pure, so it is testable without waiting
/// five minutes for a real clock to pass.
///
/// The prototype's own sub-label is the specification (`settings.html:334-335`):
/// *"Nothing has happened in the session and no question is pending."* A
/// session blocked on a question is not stalled, it is blocked — the island
/// already says so in amber, and a stall alert on top would be a second,
/// duller way of saying the same thing. A session that has already reached a
/// terminal state (`.idle`, having finished, or `.failed`) is not stalled
/// either: it already earned its own alert the moment it got there (Task 4's
/// `Finishes`/`Fails` switches), and re-announcing "nothing has happened"
/// five minutes after a run finished would be the exact double alert written
/// decision 3 exists to prevent. So only a session still `.running` can go
/// stale — this is why `aFailedSessionDoesNotAlsoStall` is in the required
/// test list beside the `.waiting` exclusion, not folded into it.
///
/// `AppModel` owns the timer (riding `prune`'s existing 60s tick rather than
/// adding a second one) and the `alreadyReported` set — this stays pure so
/// re-arming ("any event for that session clears its entry", written
/// decision 3) is entirely the caller's bookkeeping and this function never
/// needs to know a session's history, only its current state.
public struct StallDetector: Sendable {
    /// `settings.html:334`.
    public static let threshold: TimeInterval = 5 * 60

    public static func stalled(in store: SessionStore, now: Date,
                                alreadyReported: Set<SessionKey>) -> Set<SessionKey> {
        Set(store.sessions.compactMap { session -> SessionKey? in
            guard session.state == .running,
                  now.timeIntervalSince(session.updatedAt) >= threshold,
                  !alreadyReported.contains(session.id)
            else { return nil }
            return session.id
        })
    }
}
