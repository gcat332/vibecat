import Foundation
import VibeCatCore
import VibeCatTransport

/// Everything the hook does except touching stdin, stdout and the process exit
/// code — which is what makes it testable.
public struct HookRunner {
    let registry: SourceRegistry
    let client: SocketClient
    let env: [String: String]

    public init(registry: SourceRegistry, client: SocketClient, env: [String: String]) {
        self.registry = registry
        self.client = client
        self.env = env
    }

    /// Returns what to print on stdout, or nil to stay silent.
    /// Any failure at all — bad JSON, unknown CLI, dead socket, slow reply —
    /// returns nil so the calling CLI carries on with its own default.
    public func run(cli: String, stdin: Data) -> String? {
        guard let adapter = registry.adapter(for: cli),
              let raw = try? JSONSerialization.jsonObject(with: stdin) as? [String: Any],
              var event = try? adapter.parse(raw, origin: OriginReader.read(env: env))
        else { return nil }
        // The app must honour the same bound this hook is about to wait on
        // (below, via sendExpectingReply), not a second constant re-derived on
        // the app side that could drift from it — so the deadline travels on
        // the event itself.
        event.answerDeadline = client.answerDeadline
        guard let line = try? WireCodec.encode(event) else { return nil }

        guard event.wantsReply else {
            client.send(line)
            return nil
        }

        // The reply must be for the event we actually sent. This is the last
        // checkpoint before authorising a destructive command, so a crossed or
        // stale answer fails open rather than being honoured.
        guard let data = client.sendExpectingReply(line, deadline: client.answerDeadline),
              let reply = try? WireCodec.decode(Reply.self, from: data),
              reply.id == event.id
        else { return nil }

        return Self.stdout(for: cli, reply: reply)
    }

    /// Each CLI wants its answer in its own shape.
    static func stdout(for cli: String, reply: Reply) -> String? {
        switch cli {
        case "claude-code":
            guard let choice = reply.choice else { return nil }
            let decision = switch choice {
                case "allow", "always": "allow"
                case "deny":            "deny"
                default:                "ask"
            }
            let payload: [String: Any] = [
                "hookSpecificOutput": [
                    "hookEventName": "PreToolUse",
                    "permissionDecision": decision,
                    "permissionDecisionReason": "Answered in VibeCat",
                ],
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: payload,
                                                         options: [.sortedKeys]),
                  let text = String(data: data, encoding: .utf8) else { return nil }
            return text
        default:
            return nil
        }
    }
}
