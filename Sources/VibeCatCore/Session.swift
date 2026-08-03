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
