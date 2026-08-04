import Foundation
import VibeCatCore

/// The island's presented state, reduced to what has a sound.
///
/// The prototype cues on a change of its own presented state
/// (`island-motion.html:957`), over the vocabulary
/// `['dormant','working','multi','done','ask','askmulti','error','list']`. Two
/// of those matter here and `IslandState` cannot express either: `ask` and
/// `askmulti` are **different states** there, so a second session asking is a
/// change; and `done` is a state there but not here, because
/// `SessionState.init(kind:)` folds `.done` into `.idle`.
///
/// `dormant`, `idle` and `running` collapse into `quiet` — the prototype has no
/// `CUES` entry for `dormant`, `working`, `multi` or `list` either, so its
/// `cue()` returns early for all four.
public enum CueKey: Equatable, Sendable {
    case quiet
    case ask, askMulti, failed

    public init(store: SessionStore) {
        guard !store.sessions.isEmpty else { self = .quiet; return }
        switch store.aggregate {
        case .waiting: self = (store.counts[.waiting] ?? 0) > 1 ? .askMulti : .ask
        case .failed:  self = .failed
        case .running, .idle: self = .quiet
        }
    }

    /// How many agents this key says are waiting on a person: 0, 1, or "more
    /// than one". Used to tell a rise in demand from a fall.
    var waitingRank: Int {
        switch self {
        case .askMulti: 2
        case .ask:      1
        case .quiet, .failed: 0
        }
    }
}

/// Which cue an event earns, if any.
public struct CueSelector: Sendable {
    /// `policy` has no default. Plan 6.5 Task 4's own written risk is a caller
    /// quietly reaching for `AlertPolicy()` instead of the user's stored one —
    /// exactly Plan 6.4's `volume`/`quietDuringDoNotDisturb`/`selectedPage`
    /// shape, which shipped through six task reviews three times. A default
    /// here would let that happen without the compiler ever objecting; the
    /// eleven tests below that predate this parameter are amended to pass
    /// `AlertPolicy()` explicitly instead of getting it for free, so that the
    /// one real call site — `AppModel.applyAndNotify` — has no way to omit it
    /// either.
    public static func cue(for event: VibeEvent, before: SessionStore, after: SessionStore,
                           policy: AlertPolicy) -> Cue? {
        // A finished run is the one thing that cannot be read off the state.
        // `SessionState.init(kind:)` maps `.done` to `.idle`, so once `after`
        // exists there is no trace of anything having completed — and §4.2's
        // worst-state-wins governs what the island *displays*, not what
        // happened, so a finish while another agent waits is still news.
        //
        // The gate is applied to *this branch's own return*, not ahead of the
        // `if`: gating earlier — a `guard policy.allows(.finished) else return
        // nil` before this check — would make a silenced "Finishes" switch
        // swallow every other cue too, because nothing downstream would ever
        // run. Written decision 4 is that a switch here gates the cue alone;
        // it must not reach past its own trigger.
        if event.kind == .done {
            return policy.allows(.finished) ? .done : nil
        }

        let old = CueKey(store: before), new = CueKey(store: after)
        guard old != new else { return nil }

        switch new {
        case .failed:
            return policy.allows(.failed) ? .error : nil
        case .ask, .askMulti:
            // Only a rise in demand is news. The prototype cues on any change,
            // so answering one of two questions takes it `askmulti → ask` and
            // sounds the alert again — congratulating you for the thing you just
            // did. Clicking buttons in a browser hides that; a person being
            // interrupted would not miss it.
            guard new.waitingRank > old.waitingRank else { return nil }
            // Written decision 4: this gates the *cue* only. `old`/`new` above
            // were computed from the real `SessionStore`s and are returned to
            // nobody — `IslandState(store:)` reads the store directly and
            // never sees this policy, so a silenced "Needs an answer" switch
            // cannot touch what the island reports or the drawer shows.
            guard policy.allows(.needsAnswer) else { return nil }
            return new == .askMulti ? .askMulti : .ask
        case .quiet:
            return nil
        }
    }
}
