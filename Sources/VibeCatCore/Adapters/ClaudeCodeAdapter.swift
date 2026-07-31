import Foundation

public struct ClaudeCodeAdapter: SourceAdapter {
    public let id = "claude-code"
    public let displayName = "Claude Code"
    public let jumpStrategy = JumpStrategy.terminalSession
    public let reports: Set<Kind> = [.running, .done, .permission, .question, .failed]

    public init() {}

    public func parse(_ raw: [String: Any], origin: Origin) throws -> VibeEvent? {
        guard let hook = raw["hook_event_name"] as? String else {
            throw AdapterError.missingField("hook_event_name")
        }
        guard let session = raw["session_id"] as? String else {
            throw AdapterError.missingField("session_id")
        }
        guard let cwd = raw["cwd"] as? String else {
            throw AdapterError.missingField("cwd")
        }

        var event = VibeEvent(
            id: UUID().uuidString,
            cli: id,
            kind: .running,
            session: session,
            cwd: cwd,
            model: raw["model"] as? String,
            effort: raw["reasoning_effort"] as? String,
            origin: origin)

        switch hook {
        case "PreToolUse":
            event.kind = .permission
            event.title = raw["tool_name"] as? String
            event.body = Self.command(from: raw["tool_input"])
            event.wantsReply = true
            event.choices = [
                Choice(id: "allow",  label: "Allow once"),
                Choice(id: "always", label: "Allow every \(raw["tool_name"] as? String ?? "tool") call this session"),
                Choice(id: "deny",   label: "Deny"),
            ]

        case "Notification":
            event.kind = .question
            event.body = raw["message"] as? String

        case "Stop":
            event.kind = .done

        case "SubagentStop":
            event.kind = .running

        default:
            // A hook we deliberately do not surface. Not an error.
            return nil
        }

        return event
    }

    /// `tool_input` is shaped differently per tool; the command is the useful
    /// part for Bash and the file path for edits.
    static func command(from toolInput: Any?) -> String? {
        guard let dict = toolInput as? [String: Any] else { return nil }
        if let c = dict["command"] as? String { return c }
        if let p = dict["file_path"] as? String { return p }
        return nil
    }
}
