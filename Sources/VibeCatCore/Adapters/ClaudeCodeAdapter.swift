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

        case "PostToolUse":
            // The tool has run and the agent is thinking again. Without this the
            // session would stay .waiting for the whole tool execution.
            event.kind = .running

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

    /// `tool_input` is shaped differently per tool. Try the keys that carry the
    /// useful detail, then fall back to any string in the payload — a prompt that
    /// names a tool but shows nothing leaves the user approving blind.
    static func command(from toolInput: Any?) -> String? {
        guard let dict = toolInput as? [String: Any] else { return nil }
        let preferred = ["command", "file_path", "pattern", "url", "query",
                         "prompt", "notebook_path", "path"]
        for key in preferred {
            if let value = dict[key] as? String, !value.isEmpty { return value }
        }
        // Deterministic order so the same payload always renders the same way.
        return dict.keys.sorted()
            .compactMap { dict[$0] as? String }
            .first { !$0.isEmpty }
    }
}
