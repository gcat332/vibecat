import Foundation

public struct SessionKey: Hashable, Sendable {
    public let cli: String
    public let session: String
    public init(cli: String, session: String) {
        self.cli = cli
        self.session = session
    }
}

public struct Session: Identifiable, Sendable, Equatable {
    /// §11's line 2, in the two halves the wire already sends it in.
    ///
    /// This used to be one `String`: `Session.activity(from:)` joined
    /// `VibeEvent.title` and `.body` with a space and nothing downstream could
    /// take them apart again. The reference prototype
    /// (`docs/superpowers/prototypes/island-motion.html`, `renderRows` line 845)
    /// keeps them as two fields and emphasises the second —
    /// `${s.act} <em>${s.code}</em>`, where `em` is monospace and a brighter
    /// ink — because in a list whose whole job is triage at a glance, "Asking to
    /// run" is the boilerplate and `rm -rf build/` is the thing you are being
    /// asked about. Merging them threw exactly that distinction away.
    ///
    /// Both halves are optional because an event may carry either alone; the
    /// initialiser below is failable so "neither" stays representable as `nil`
    /// activity rather than as an `Activity` with nothing in it.
    public struct Activity: Sendable, Equatable {
        /// `VibeEvent.title` — the prototype's `act`. What the agent is doing:
        /// "Asking to run", "Editing", "Stopped at".
        public var sentence: String?
        /// `VibeEvent.body` — the prototype's `code`. What it is doing it to:
        /// a command, a path, a script.
        public var command: String?

        public init(sentence: String? = nil, command: String? = nil) {
            self.sentence = sentence
            self.command = command
        }

        public init?(event: VibeEvent) {
            guard event.title != nil || event.body != nil else { return nil }
            self.init(sentence: event.title, command: event.body)
        }
    }

    public let id: SessionKey
    public var cli: String
    public var cwd: String
    public var project: String
    public var worktree: String?
    public var model: String?
    public var effort: String?
    public var state: SessionState
    public var activity: Activity?
    public var lastUserMessage: String?
    /// §3's *"a swappable runtime asset"*, resolved for **this session**
    /// rather than looked up from a registry inside the view —
    /// `SessionRow` reads this directly and falls back to `CLIMark(cli:)`'s
    /// geometric mark whenever it is `nil`, the same fallback
    /// `SourceIcon` itself uses for a path that turns out to be bad.
    ///
    /// **Set at ingest, from the app's own `SourceRegistry`.** Plan 7 Task 6:
    /// `AppModel.init(sources:)` builds a registry through the same
    /// `SourceRegistry.loadingCustomSources(builtIns:from:)` the hook uses, so
    /// the two processes cannot disagree about which sources exist, and
    /// `AppModel.applyAndNotify` passes `registry.adapter(for: event.cli)?
    /// .icon` into `SessionStore.apply(_:now:icon:)`. That is one lookup, at
    /// the one point a `Session` is built or merged — never inside
    /// `SessionRow`, which could not then be rasterised by any test without a
    /// registry to hand it.
    ///
    /// **The resolution deliberately happens on the app side rather than on
    /// the wire.** `VibeEvent` carries no icon field and must not gain one: the
    /// icon is a display concern, the app is what displays, and putting a
    /// presentation detail on a socket that four processes speak would make
    /// every future change to how an icon is named a wire-protocol change. The
    /// wire keeps speaking only the shared `kind` vocabulary.
    ///
    /// Still `nil` for every **built-in** source, and that is by design rather
    /// than an omission: no adapter in `Adapters/` may set `icon`, because a
    /// committed vendor logo is a trademark question MIT cannot settle (§3).
    /// A real path comes from a *custom* source — a file on the user's own
    /// disk, named in `custom-sources.json`.
    ///
    /// `public var`, not `let`: `SessionStore.apply` assigns it after
    /// `init(event:now:)` has run, and tests set it directly to render a row
    /// without a registry.
    public var icon: String?
    public var tasks: [TaskItem]
    public var agents: [AgentItem]
    public var origin: Origin
    public var startedAt: Date
    public var updatedAt: Date

    public init(event: VibeEvent, now: Date) {
        id = SessionKey(cli: event.cli, session: event.session)
        cli = event.cli
        cwd = event.cwd
        project = Session.project(from: event.cwd)
        worktree = event.worktree
        model = event.model
        effort = event.effort
        state = SessionState(kind: event.kind)
        activity = Activity(event: event)
        lastUserMessage = nil
        tasks = event.tasks ?? []
        agents = event.agents ?? []
        origin = event.origin
        startedAt = now
        updatedAt = now
    }

    /// An event carries only what changed, so anything it omits is left alone.
    public mutating func merge(_ event: VibeEvent, now: Date) {
        cwd = event.cwd
        project = Session.project(from: event.cwd)
        if let w = event.worktree { worktree = w }
        if let m = event.model { model = m }
        if let e = event.effort { effort = e }
        state = SessionState(kind: event.kind)
        if let a = Activity(event: event) { activity = a }
        if let t = event.tasks { tasks = t }
        if let g = event.agents { agents = g }
        origin = event.origin
        updatedAt = now
    }

    static func project(from cwd: String) -> String {
        let trimmed = cwd.hasSuffix("/") ? String(cwd.dropLast()) : cwd
        return trimmed.split(separator: "/").last.map(String.init) ?? trimmed
    }
}
