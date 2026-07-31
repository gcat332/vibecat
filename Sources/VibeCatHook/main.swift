import Foundation
import VibeCatCore
import VibeCatTransport
import VibeCatHookKit

// usage: vibecat-hook <cli-id>
let cli = CommandLine.arguments.dropFirst().first ?? "claude-code"
let env = ProcessInfo.processInfo.environment

let deadline = env["VIBECAT_TIMEOUT_MS"].flatMap(Double.init).map { $0 / 1000 } ?? 0.3

let runner = HookRunner(
    registry: SourceRegistry(adapters: [ClaudeCodeAdapter()]),
    client: SocketClient(path: SocketPath.default, deadline: deadline),
    env: env)

let input = FileHandle.standardInput.readDataToEndOfFile()

if let out = runner.run(cli: cli, stdin: input) {
    print(out)
}

// Always zero. A hook that fails must never fail the agent's turn.
exit(0)
