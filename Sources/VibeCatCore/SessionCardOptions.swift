import Foundation

/// Which fields of a session row/card are shown — §11's own switch set,
/// `settings.html:445-490`'s eight switches plus `project`, which
/// `SessionRow.Options` already had.
///
/// **A Core-side mirror of `SessionRow.Options`, not that type itself.**
/// `SessionRow.Options` is an `OptionSet` in `VibeCatUI` — Plan 5 built it as
/// this page's own switch point — and `Preferences` needs a visible type while
/// Core may never import `VibeCatUI`, the same seam `Coat`, `SoundPack` and
/// `MotionLevel` all hit before this. Task 4 re-threads `SessionListFace`'s
/// `options` parameter and is where this value turns into a `SessionRow
/// .Options` for rendering.
///
/// **Nine named `Bool`s, not `SessionRow.Options`'s raw `Int`.** The
/// alternative — persisting `options.rawValue` under one key — is compact, but
/// `SessionRow.Options` assigns bit positions by declaration order
/// (`.project` is `1 << 5` today) and silently reinterprets every flag if one
/// is ever renumbered or a case is inserted in the middle: a plist written by
/// an older build would read back as a *different* set of switches with no
/// error at all. Nine keys cannot be corrupted that way — a renumber changes
/// nothing about a key named `"cardOptions.project"` — and this repo already
/// has the precedent: `AlertPolicy`, the other multi-flag preference, persists
/// four named `Bool`s rather than a combined value. This follows it rather
/// than inventing a second shape for the same problem.
///
/// **All nine default to `true`.** `UserDefaultsPreferenceStore.load()` must
/// use the same `object(forKey:) != nil` presence guard `soundEnabled` and
/// `quietDuringDoNotDisturb` already use — `bool(forKey:)` returns `false` for
/// a key nobody ever wrote, and reading these nine unconditionally would ship
/// a fresh install with every session-card field hidden, which is not a
/// session list at all.
public struct SessionCardOptions: Sendable, Equatable {
    public var activity: Bool
    public var lastMessage: Bool
    public var tasks: Bool
    public var agents: Bool
    public var subagents: Bool
    public var project: Bool
    public var worktree: Bool
    public var model: Bool
    public var effort: Bool

    public init(activity: Bool = true, lastMessage: Bool = true, tasks: Bool = true,
                agents: Bool = true, subagents: Bool = true, project: Bool = true,
                worktree: Bool = true, model: Bool = true, effort: Bool = true) {
        self.activity = activity
        self.lastMessage = lastMessage
        self.tasks = tasks
        self.agents = agents
        self.subagents = subagents
        self.project = project
        self.worktree = worktree
        self.model = model
        self.effort = effort
    }
}
