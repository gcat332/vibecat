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
    public let id: SessionKey
    public var cli: String
    public var cwd: String
    public var project: String
    public var worktree: String?
    public var model: String?
    public var effort: String?
    public var state: SessionState
    public var activity: String?
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
        activity = Session.activity(from: event)
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
        if let a = Session.activity(from: event) { activity = a }
        if let t = event.tasks { tasks = t }
        if let g = event.agents { agents = g }
        origin = event.origin
        updatedAt = now
    }

    static func project(from cwd: String) -> String {
        let trimmed = cwd.hasSuffix("/") ? String(cwd.dropLast()) : cwd
        return trimmed.split(separator: "/").last.map(String.init) ?? trimmed
    }

    static func activity(from event: VibeEvent) -> String? {
        switch (event.title, event.body) {
        case let (title?, body?): "\(title) \(body)"
        case let (title?, nil):   title
        case let (nil, body?):    body
        default:                  nil
        }
    }
}
