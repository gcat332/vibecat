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
    public static func cue(for event: VibeEvent,
                           before: SessionStore, after: SessionStore) -> Cue? {
        // A finished run is the one thing that cannot be read off the state.
        // `SessionState.init(kind:)` maps `.done` to `.idle`, so once `after`
        // exists there is no trace of anything having completed — and §4.2's
        // worst-state-wins governs what the island *displays*, not what
        // happened, so a finish while another agent waits is still news.
        if event.kind == .done { return .done }

        let old = CueKey(store: before), new = CueKey(store: after)
        guard old != new else { return nil }

        switch new {
        case .failed: return .error
        case .ask, .askMulti:
            // Only a rise in demand is news. The prototype cues on any change,
            // so answering one of two questions takes it `askmulti → ask` and
            // sounds the alert again — congratulating you for the thing you just
            // did. Clicking buttons in a browser hides that; a person being
            // interrupted would not miss it.
            guard new.waitingRank > old.waitingRank else { return nil }
            return new == .askMulti ? .askMulti : .ask
        case .quiet:
            return nil
        }
    }
}
