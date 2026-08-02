import Foundation

/// The shared vocabulary every adapter maps its CLI's own event names onto,
/// so the core never learns a vendor's terminology.
public enum Kind: String, Codable, Sendable, CaseIterable {
    case idle, running, done, permission, question, failed
}

public struct Choice: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

/// Where the agent is running. Captured by the hook from its own environment —
/// never read from a GUI app.
public struct Origin: Codable, Sendable, Equatable {
    public var app: String?
    public var termSession: String?
    public var vscodePid: String?

    public init(app: String? = nil, termSession: String? = nil, vscodePid: String? = nil) {
        self.app = app
        self.termSession = termSession
        self.vscodePid = vscodePid
    }
}

public struct TaskItem: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable { case open, doing, done }

    public var title: String
    public var status: Status

    public init(title: String, status: Status) {
        self.title = title
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case title = "t"
        case status = "s"
    }
}

public struct AgentItem: Codable, Sendable, Equatable {
    public var name: String
    public var elapsed: String
    public var model: String
    public var activity: String?
    public var finished: Bool

    public init(name: String, elapsed: String, model: String,
                activity: String? = nil, finished: Bool = false) {
        self.name = name
        self.elapsed = elapsed
        self.model = model
        self.activity = activity
        self.finished = finished
    }

    enum CodingKeys: String, CodingKey {
        case name = "n"
        case elapsed = "t"
        case model = "m"
        case activity = "sub"
        case finished = "done"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        elapsed = try c.decode(String.self, forKey: .elapsed)
        model = try c.decode(String.self, forKey: .model)
        activity = try c.decodeIfPresent(String.self, forKey: .activity)
        finished = try c.decodeIfPresent(Bool.self, forKey: .finished) ?? false
    }
}

public struct VibeEvent: Codable, Sendable, Equatable {
    public var v: Int
    public var id: String
    public var cli: String
    public var kind: Kind
    public var session: String
    public var cwd: String
    public var worktree: String?
    public var model: String?
    public var effort: String?
    public var title: String?
    public var body: String?
    public var choices: [Choice]?
    public var multi: Bool
    public var wantsReply: Bool
    /// How long the *hook* will wait for a human answer before it gives up
    /// and falls back to its own prompt. Carried on the event, rather than
    /// re-derived on the app side from a second constant, so the two never
    /// drift apart — see `SocketClient.defaultAnswerDeadline` and
    /// `HookRunner`, which sets this from `client.answerDeadline`. `nil` on
    /// any event the hook itself predates this field, or never sent it.
    public var answerDeadline: TimeInterval?
    public var tasks: [TaskItem]?
    public var agents: [AgentItem]?
    public var origin: Origin

    public init(v: Int = 1, id: String, cli: String, kind: Kind,
                session: String, cwd: String,
                worktree: String? = nil, model: String? = nil, effort: String? = nil,
                title: String? = nil, body: String? = nil,
                choices: [Choice]? = nil, multi: Bool = false, wantsReply: Bool = false,
                answerDeadline: TimeInterval? = nil,
                tasks: [TaskItem]? = nil, agents: [AgentItem]? = nil,
                origin: Origin = Origin()) {
        self.v = v
        self.id = id
        self.cli = cli
        self.kind = kind
        self.session = session
        self.cwd = cwd
        self.worktree = worktree
        self.model = model
        self.effort = effort
        self.title = title
        self.body = body
        self.choices = choices
        self.multi = multi
        self.wantsReply = wantsReply
        self.answerDeadline = answerDeadline
        self.tasks = tasks
        self.agents = agents
        self.origin = origin
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = try c.decodeIfPresent(Int.self, forKey: .v) ?? 1
        id = try c.decode(String.self, forKey: .id)
        cli = try c.decode(String.self, forKey: .cli)
        kind = try c.decode(Kind.self, forKey: .kind)
        session = try c.decode(String.self, forKey: .session)
        cwd = try c.decode(String.self, forKey: .cwd)
        worktree = try c.decodeIfPresent(String.self, forKey: .worktree)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        effort = try c.decodeIfPresent(String.self, forKey: .effort)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        body = try c.decodeIfPresent(String.self, forKey: .body)
        choices = try c.decodeIfPresent([Choice].self, forKey: .choices)
        multi = try c.decodeIfPresent(Bool.self, forKey: .multi) ?? false
        wantsReply = try c.decodeIfPresent(Bool.self, forKey: .wantsReply) ?? false
        answerDeadline = try c.decodeIfPresent(TimeInterval.self, forKey: .answerDeadline)
        tasks = try c.decodeIfPresent([TaskItem].self, forKey: .tasks)
        agents = try c.decodeIfPresent([AgentItem].self, forKey: .agents)
        origin = try c.decodeIfPresent(Origin.self, forKey: .origin) ?? Origin()
    }
}

public struct Reply: Codable, Sendable, Equatable {
    public var id: String
    public var choice: String?
    public var choices: [String]?
    public var text: String?

    public init(id: String, choice: String? = nil,
                choices: [String]? = nil, text: String? = nil) {
        self.id = id
        self.choice = choice
        self.choices = choices
        self.text = text
    }
}
