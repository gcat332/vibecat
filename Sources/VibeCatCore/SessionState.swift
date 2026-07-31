public enum SessionState: String, Codable, Sendable, CaseIterable {
    case idle, running, waiting, failed

    /// Lower is more urgent. `waiting` beats `failed` because a waiting agent is
    /// idling on you right now, while a failed one has already stopped.
    public var urgency: Int {
        switch self {
        case .waiting: 0
        case .failed:  1
        case .running: 2
        case .idle:    3
        }
    }

    public static func mostUrgent(_ states: [SessionState]) -> SessionState? {
        states.min { $0.urgency < $1.urgency }
    }

    public init(kind: Kind) {
        switch kind {
        case .permission, .question: self = .waiting
        case .running:               self = .running
        case .failed:                self = .failed
        case .done, .idle:           self = .idle
        }
    }
}
